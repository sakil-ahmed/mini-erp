-- =============================================================================
-- 0010_integrity_fixes.sql
-- Top integrity fixes from CTO review:
--   1) record_payment: one payment+journal per doc (void-safe); lock before sum
--   2) create_purchase: net inv_amount so avg_cost matches Inventory GL
--   3) Guard products.stock_qty/avg_cost; lock products in uuid order
-- =============================================================================

-- ---------------------------------------------------------------------------
-- purchase_items.inv_amount — inventory valuation credited to the line (net
-- of header discount). unit_cost/line_total stay commercial (gross).
-- ---------------------------------------------------------------------------
alter table public.purchase_items
  add column if not exists inv_amount numeric(14, 2);

update public.purchase_items pi
set inv_amount = case
  when p.subtotal = 0 then 0
  else round(pi.line_total * (p.total / p.subtotal), 2)
end
from public.purchases p
where p.id = pi.purchase_id
  and pi.inv_amount is null;

-- Penny-fix: push remainder of (total − sum(inv_amount)) onto the last line.
with sums as (
  select
    pi.purchase_id,
    p.total,
    sum(pi.inv_amount) as inv_sum,
    (
      select pi2.id
      from public.purchase_items pi2
      where pi2.purchase_id = pi.purchase_id
      order by pi2.product_id desc, pi2.id desc
      limit 1
    ) as last_id
  from public.purchase_items pi
  join public.purchases p on p.id = pi.purchase_id
  group by pi.purchase_id, p.total
)
update public.purchase_items pi
set inv_amount = pi.inv_amount + (s.total - s.inv_sum)
from sums s
where pi.id = s.last_id
  and s.total <> s.inv_sum;

alter table public.purchase_items
  alter column inv_amount set not null;

alter table public.purchase_items
  drop constraint if exists purchase_items_inv_amount_nonneg;

alter table public.purchase_items
  add constraint purchase_items_inv_amount_nonneg check (inv_amount >= 0);

-- ---------------------------------------------------------------------------
-- Block client/admin REST updates to stock_qty / avg_cost (RPC-only via GUC).
-- ---------------------------------------------------------------------------
create or replace function public.protect_product_valuation()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE'
     and (
       new.stock_qty is distinct from old.stock_qty
       or new.avg_cost is distinct from old.avg_cost
     )
     and coalesce(current_setting('app.allow_stock_mutation', true), '') <> '1'
  then
    raise exception
      'products.stock_qty/avg_cost are RPC-only; use create_purchase/create_sale/void_*';
  end if;
  return new;
end;
$$;

drop trigger if exists products_protect_valuation on public.products;
create trigger products_protect_valuation
  before update on public.products
  for each row
  execute function public.protect_product_valuation();

-- ---------------------------------------------------------------------------
-- create_purchase — ordered locks + net inv_amount into moving average
-- ---------------------------------------------------------------------------
create or replace function public.create_purchase(
  p_supplier uuid,
  p_date date,
  p_items jsonb,
  p_discount numeric,
  p_paid numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_purchase_id uuid;
  v_journal_id uuid;
  v_subtotal numeric(14, 2) := 0;
  v_total numeric(14, 2);
  v_discount numeric(14, 2);
  v_paid numeric(14, 2);
  v_payable numeric(14, 2);
  v_item jsonb;
  v_product_id uuid;
  v_qty numeric(14, 3);
  v_unit_cost numeric(14, 2);
  v_line_total numeric(14, 2);
  v_inv_amount numeric(14, 2);
  v_old_qty numeric(14, 3);
  v_old_avg numeric(14, 2);
  v_new_qty numeric(14, 3);
  v_new_avg numeric(14, 2);
  v_inv_account uuid;
  v_cash_account uuid;
  v_payable_account uuid;
  v_supplier_ok boolean;
  v_line_count integer := 0;
  v_line_idx integer := 0;
  v_discount_allocated numeric(14, 2) := 0;
  v_share numeric(14, 2);
begin
  if not public.has_role(array['admin', 'purchase']::public.app_role[]) then
    raise exception 'permission denied: requires admin or purchase role';
  end if;

  if v_user is null then
    raise exception 'not authenticated';
  end if;

  if p_supplier is null then
    raise exception 'supplier is required';
  end if;

  if p_date is null then
    raise exception 'purchase date is required';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'p_items must be a non-empty JSON array';
  end if;

  perform set_config('app.allow_stock_mutation', '1', true);

  v_discount := round(coalesce(p_discount, 0), 2);
  v_paid := round(coalesce(p_paid, 0), 2);

  if v_discount < 0 then
    raise exception 'discount must be >= 0 (got %)', v_discount;
  end if;

  if v_paid < 0 then
    raise exception 'paid amount must be >= 0 (got %)', v_paid;
  end if;

  select exists (
    select 1
    from public.parties
    where id = p_supplier
      and kind = 'supplier'
      and is_active
  ) into v_supplier_ok;

  if not v_supplier_ok then
    raise exception 'supplier % not found or not an active supplier', p_supplier;
  end if;

  select id into v_inv_account from public.accounts where code = '1200';
  select id into v_cash_account from public.accounts where code = '1010';
  select id into v_payable_account from public.accounts where code = '2100';

  if v_inv_account is null or v_cash_account is null or v_payable_account is null then
    raise exception 'chart of accounts missing 1200/1010/2100 — run 0001_schema seed';
  end if;

  for v_item in
    select value
    from jsonb_array_elements(p_items) as t(value)
    order by (t.value ->> 'product_id')::uuid
  loop
    if v_item ->> 'product_id' is null then
      raise exception 'each item requires product_id';
    end if;

    v_product_id := (v_item ->> 'product_id')::uuid;
    v_qty := (v_item ->> 'qty')::numeric(14, 3);
    v_unit_cost := (v_item ->> 'unit_cost')::numeric(14, 2);

    if v_qty is null or v_qty <= 0 then
      raise exception 'item qty must be > 0 (product %, qty %)', v_product_id, v_qty;
    end if;

    if v_unit_cost is null or v_unit_cost < 0 then
      raise exception 'item unit_cost must be >= 0 (product %, cost %)', v_product_id, v_unit_cost;
    end if;

    if not exists (
      select 1 from public.products where id = v_product_id and is_active
    ) then
      raise exception 'product % not found or inactive', v_product_id;
    end if;

    v_line_total := round(v_qty * v_unit_cost, 2);
    v_subtotal := v_subtotal + v_line_total;
    v_line_count := v_line_count + 1;
  end loop;

  if v_discount > v_subtotal then
    raise exception 'discount (%) cannot exceed subtotal (%)', v_discount, v_subtotal;
  end if;

  v_total := round(v_subtotal - v_discount, 2);

  if v_total <= 0 then
    raise exception 'purchase total must be > 0 after discount (subtotal %, discount %)',
      v_subtotal, v_discount;
  end if;

  if v_paid > v_total then
    raise exception 'paid (%) cannot exceed total (%)', v_paid, v_total;
  end if;

  v_payable := round(v_total - v_paid, 2);

  insert into public.purchases (
    supplier_id, doc_date, subtotal, discount, total, amount_paid, status, created_by
  )
  values (
    p_supplier, p_date, v_subtotal, v_discount, v_total, v_paid, 'posted', v_user
  )
  returning id into v_purchase_id;

  for v_item in
    select value
    from jsonb_array_elements(p_items) as t(value)
    order by (t.value ->> 'product_id')::uuid
  loop
    v_line_idx := v_line_idx + 1;
    v_product_id := (v_item ->> 'product_id')::uuid;
    v_qty := (v_item ->> 'qty')::numeric(14, 3);
    v_unit_cost := (v_item ->> 'unit_cost')::numeric(14, 2);
    v_line_total := round(v_qty * v_unit_cost, 2);

    -- Net inventory amount: proportional discount; last line takes remainder.
    if v_line_idx = v_line_count then
      v_inv_amount := round(v_line_total - (v_discount - v_discount_allocated), 2);
    else
      if v_subtotal = 0 then
        v_share := 0;
      else
        v_share := round(v_line_total * v_discount / v_subtotal, 2);
      end if;
      v_discount_allocated := v_discount_allocated + v_share;
      v_inv_amount := round(v_line_total - v_share, 2);
    end if;

    insert into public.purchase_items (
      purchase_id, product_id, qty, unit_cost, line_total, inv_amount, created_by
    )
    values (
      v_purchase_id, v_product_id, v_qty, v_unit_cost, v_line_total, v_inv_amount, v_user
    );

    select stock_qty, avg_cost
    into v_old_qty, v_old_avg
    from public.products
    where id = v_product_id
    for update;

    v_new_qty := v_old_qty + v_qty;

    if v_old_qty = 0 then
      v_new_avg := case
        when v_new_qty = 0 then 0
        else round(v_inv_amount / v_new_qty, 2)
      end;
    else
      v_new_avg := round(
        (v_old_qty * v_old_avg + v_inv_amount) / v_new_qty,
        2
      );
    end if;

    update public.products
    set
      stock_qty = v_new_qty,
      avg_cost = v_new_avg
    where id = v_product_id;

    insert into public.stock_movements (
      product_id, kind, qty_delta, source_type, source_id, note, created_by
    )
    values (
      v_product_id, 'purchase', v_qty, 'purchase', v_purchase_id, 'Purchase receipt', v_user
    );
  end loop;

  insert into public.journal_entries (
    entry_date, status, memo, source_type, source_id, created_by
  )
  values (
    p_date, 'posted', 'Purchase ' || v_purchase_id::text, 'purchase', v_purchase_id, v_user
  )
  returning id into v_journal_id;

  insert into public.journal_lines (
    journal_entry_id, account_id, debit, credit, created_by
  )
  values (v_journal_id, v_inv_account, v_total, 0, v_user);

  if v_paid > 0 then
    insert into public.journal_lines (
      journal_entry_id, account_id, debit, credit, created_by
    )
    values (v_journal_id, v_cash_account, 0, v_paid, v_user);
  end if;

  if v_payable > 0 then
    insert into public.journal_lines (
      journal_entry_id, account_id, debit, credit, created_by
    )
    values (v_journal_id, v_payable_account, 0, v_payable, v_user);
  end if;

  if v_paid > 0 then
    insert into public.payments (
      kind, party_id, account_id, amount, status, payment_date,
      source_type, source_id, created_by
    )
    values (
      'disbursement', p_supplier, v_cash_account, v_paid, 'posted', p_date,
      'purchase', v_purchase_id, v_user
    );
  end if;

  return v_purchase_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- create_sale — ordered product locks + money round + stock GUC
-- ---------------------------------------------------------------------------
create or replace function public.create_sale(
  p_customer uuid,
  p_date date,
  p_items jsonb,
  p_discount numeric,
  p_paid numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_sale_id uuid;
  v_journal_id uuid;
  v_subtotal numeric(14, 2) := 0;
  v_total numeric(14, 2);
  v_discount numeric(14, 2);
  v_paid numeric(14, 2);
  v_receivable numeric(14, 2);
  v_cogs_total numeric(14, 2) := 0;
  v_item jsonb;
  v_product_id uuid;
  v_qty numeric(14, 3);
  v_unit_price numeric(14, 2);
  v_unit_cost numeric(14, 2);
  v_line_total numeric(14, 2);
  v_line_cogs numeric(14, 2);
  v_old_qty numeric(14, 3);
  v_old_avg numeric(14, 2);
  v_new_qty numeric(14, 3);
  v_cash_account uuid;
  v_ar_account uuid;
  v_revenue_account uuid;
  v_cogs_account uuid;
  v_inv_account uuid;
  v_customer_ok boolean;
begin
  if not public.has_role(array['admin', 'sales']::public.app_role[]) then
    raise exception 'permission denied: requires admin or sales role';
  end if;

  if v_user is null then
    raise exception 'not authenticated';
  end if;

  if p_customer is null then
    raise exception 'customer is required';
  end if;

  if p_date is null then
    raise exception 'sale date is required';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'p_items must be a non-empty JSON array';
  end if;

  perform set_config('app.allow_stock_mutation', '1', true);

  v_discount := round(coalesce(p_discount, 0), 2);
  v_paid := round(coalesce(p_paid, 0), 2);

  if v_discount < 0 then
    raise exception 'discount must be >= 0 (got %)', v_discount;
  end if;

  if v_paid < 0 then
    raise exception 'paid amount must be >= 0 (got %)', v_paid;
  end if;

  select exists (
    select 1
    from public.parties
    where id = p_customer
      and kind = 'customer'
      and is_active
  ) into v_customer_ok;

  if not v_customer_ok then
    raise exception 'customer % not found or not an active customer', p_customer;
  end if;

  select id into v_cash_account from public.accounts where code = '1010';
  select id into v_ar_account from public.accounts where code = '1100';
  select id into v_revenue_account from public.accounts where code = '4000';
  select id into v_cogs_account from public.accounts where code = '5000';
  select id into v_inv_account from public.accounts where code = '1200';

  if v_cash_account is null
     or v_ar_account is null
     or v_revenue_account is null
     or v_cogs_account is null
     or v_inv_account is null then
    raise exception 'chart of accounts missing 1010/1100/4000/5000/1200 — run 0001_schema seed';
  end if;

  for v_item in
    select value
    from jsonb_array_elements(p_items) as t(value)
    order by (t.value ->> 'product_id')::uuid
  loop
    if v_item ->> 'product_id' is null then
      raise exception 'each item requires product_id';
    end if;

    v_product_id := (v_item ->> 'product_id')::uuid;
    v_qty := (v_item ->> 'qty')::numeric(14, 3);
    v_unit_price := (v_item ->> 'unit_price')::numeric(14, 2);

    if v_qty is null or v_qty <= 0 then
      raise exception 'item qty must be > 0 (product %, qty %)', v_product_id, v_qty;
    end if;

    if v_unit_price is null or v_unit_price < 0 then
      raise exception 'item unit_price must be >= 0 (product %, price %)',
        v_product_id, v_unit_price;
    end if;

    if not exists (
      select 1 from public.products where id = v_product_id and is_active
    ) then
      raise exception 'product % not found or inactive', v_product_id;
    end if;

    v_line_total := round(v_qty * v_unit_price, 2);
    v_subtotal := v_subtotal + v_line_total;
  end loop;

  if v_discount > v_subtotal then
    raise exception 'discount (%) cannot exceed subtotal (%)', v_discount, v_subtotal;
  end if;

  v_total := round(v_subtotal - v_discount, 2);

  if v_total <= 0 then
    raise exception 'sale total must be > 0 after discount (subtotal %, discount %)',
      v_subtotal, v_discount;
  end if;

  if v_paid > v_total then
    raise exception 'paid (%) cannot exceed total (%)', v_paid, v_total;
  end if;

  v_receivable := round(v_total - v_paid, 2);

  insert into public.sales (
    customer_id, doc_date, subtotal, discount, total, amount_paid, status, created_by
  )
  values (
    p_customer, p_date, v_subtotal, v_discount, v_total, v_paid, 'posted', v_user
  )
  returning id into v_sale_id;

  for v_item in
    select value
    from jsonb_array_elements(p_items) as t(value)
    order by (t.value ->> 'product_id')::uuid
  loop
    v_product_id := (v_item ->> 'product_id')::uuid;
    v_qty := (v_item ->> 'qty')::numeric(14, 3);
    v_unit_price := (v_item ->> 'unit_price')::numeric(14, 2);
    v_line_total := round(v_qty * v_unit_price, 2);

    select stock_qty, avg_cost
    into v_old_qty, v_old_avg
    from public.products
    where id = v_product_id
    for update;

    if v_old_qty < v_qty then
      raise exception
        'insufficient stock for product % (available %, requested %)',
        v_product_id, v_old_qty, v_qty;
    end if;

    v_unit_cost := v_old_avg;
    v_line_cogs := round(v_qty * v_unit_cost, 2);
    v_cogs_total := v_cogs_total + v_line_cogs;
    v_new_qty := v_old_qty - v_qty;

    insert into public.sale_items (
      sale_id, product_id, qty, unit_price, unit_cost, line_total, created_by
    )
    values (
      v_sale_id, v_product_id, v_qty, v_unit_price, v_unit_cost, v_line_total, v_user
    );

    update public.products
    set stock_qty = v_new_qty
    where id = v_product_id;

    insert into public.stock_movements (
      product_id, kind, qty_delta, source_type, source_id, note, created_by
    )
    values (
      v_product_id, 'sale', -v_qty, 'sale', v_sale_id, 'Sale issue', v_user
    );
  end loop;

  insert into public.journal_entries (
    entry_date, status, memo, source_type, source_id, created_by
  )
  values (
    p_date, 'posted', 'Sale ' || v_sale_id::text, 'sale', v_sale_id, v_user
  )
  returning id into v_journal_id;

  if v_paid > 0 then
    insert into public.journal_lines (
      journal_entry_id, account_id, debit, credit, created_by
    )
    values (v_journal_id, v_cash_account, v_paid, 0, v_user);
  end if;

  if v_receivable > 0 then
    insert into public.journal_lines (
      journal_entry_id, account_id, debit, credit, created_by
    )
    values (v_journal_id, v_ar_account, v_receivable, 0, v_user);
  end if;

  insert into public.journal_lines (
    journal_entry_id, account_id, debit, credit, created_by
  )
  values (v_journal_id, v_revenue_account, 0, v_total, v_user);

  if v_cogs_total > 0 then
    insert into public.journal_lines (
      journal_entry_id, account_id, debit, credit, created_by
    )
    values (v_journal_id, v_cogs_account, v_cogs_total, 0, v_user);

    insert into public.journal_lines (
      journal_entry_id, account_id, debit, credit, created_by
    )
    values (v_journal_id, v_inv_account, 0, v_cogs_total, v_user);
  end if;

  if v_paid > 0 then
    insert into public.payments (
      kind, party_id, account_id, amount, status, payment_date,
      source_type, source_id, created_by
    )
    values (
      'receipt', p_customer, v_cash_account, v_paid, 'posted', p_date,
      'sale', v_sale_id, v_user
    );
  end if;

  return v_sale_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- void_purchase — reverse using inv_amount; set stock GUC
-- ---------------------------------------------------------------------------
create or replace function public.void_purchase(p_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_status public.doc_status;
  v_item record;
  v_old_qty numeric(14, 3);
  v_old_avg numeric(14, 2);
  v_new_qty numeric(14, 3);
  v_new_avg numeric(14, 2);
  v_pay record;
begin
  if not public.has_role(array['admin']::public.app_role[]) then
    raise exception 'permission denied: requires admin role';
  end if;

  if v_user is null then
    raise exception 'not authenticated';
  end if;

  if p_id is null then
    raise exception 'purchase id is required';
  end if;

  perform set_config('app.allow_stock_mutation', '1', true);

  select status into v_status
  from public.purchases
  where id = p_id
  for update;

  if v_status is null then
    raise exception 'purchase % not found', p_id;
  end if;

  if v_status = 'void' then
    raise exception 'purchase % is already void', p_id;
  end if;

  for v_item in
    select product_id, qty, inv_amount
    from public.purchase_items
    where purchase_id = p_id
    order by product_id, id
  loop
    select stock_qty, avg_cost
    into v_old_qty, v_old_avg
    from public.products
    where id = v_item.product_id
    for update;

    if v_old_qty < v_item.qty then
      raise exception
        'cannot void purchase %: product % stock would go negative (available %, void qty %)',
        p_id, v_item.product_id, v_old_qty, v_item.qty;
    end if;

    v_new_qty := v_old_qty - v_item.qty;

    if v_new_qty = 0 then
      v_new_avg := 0;
    else
      v_new_avg := round(
        (v_old_qty * v_old_avg - v_item.inv_amount) / v_new_qty,
        2
      );
      if v_new_avg < 0 then
        v_new_avg := 0;
      end if;
    end if;

    update public.products
    set
      stock_qty = v_new_qty,
      avg_cost = v_new_avg
    where id = v_item.product_id;

    insert into public.stock_movements (
      product_id, kind, qty_delta, source_type, source_id, note, created_by
    )
    values (
      v_item.product_id, 'void_reversal', -v_item.qty, 'purchase', p_id,
      'Void purchase reversal', v_user
    );
  end loop;

  perform public.reverse_journals_for_source(
    'purchase', p_id, 'Void purchase ' || p_id::text, v_user
  );

  for v_pay in
    select id
    from public.payments
    where source_type = 'purchase'
      and source_id = p_id
      and status = 'posted'
    for update
  loop
    perform public.reverse_journals_for_source(
      'payment', v_pay.id, 'Void purchase payment ' || v_pay.id::text, v_user
    );

    update public.payments
    set status = 'void'
    where id = v_pay.id;
  end loop;

  update public.purchases
  set status = 'void'
  where id = p_id;

  return p_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- void_sale — stock GUC (ordered locks already present)
-- ---------------------------------------------------------------------------
create or replace function public.void_sale(p_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_status public.doc_status;
  v_item record;
  v_old_qty numeric(14, 3);
  v_pay record;
begin
  if not public.has_role(array['admin']::public.app_role[]) then
    raise exception 'permission denied: requires admin role';
  end if;

  if v_user is null then
    raise exception 'not authenticated';
  end if;

  if p_id is null then
    raise exception 'sale id is required';
  end if;

  perform set_config('app.allow_stock_mutation', '1', true);

  select status into v_status
  from public.sales
  where id = p_id
  for update;

  if v_status is null then
    raise exception 'sale % not found', p_id;
  end if;

  if v_status = 'void' then
    raise exception 'sale % is already void', p_id;
  end if;

  for v_item in
    select product_id, qty
    from public.sale_items
    where sale_id = p_id
    order by product_id, id
  loop
    select stock_qty
    into v_old_qty
    from public.products
    where id = v_item.product_id
    for update;

    update public.products
    set stock_qty = v_old_qty + v_item.qty
    where id = v_item.product_id;

    insert into public.stock_movements (
      product_id, kind, qty_delta, source_type, source_id, note, created_by
    )
    values (
      v_item.product_id, 'void_reversal', v_item.qty, 'sale', p_id,
      'Void sale reversal', v_user
    );
  end loop;

  perform public.reverse_journals_for_source(
    'sale', p_id, 'Void sale ' || p_id::text, v_user
  );

  for v_pay in
    select id
    from public.payments
    where source_type = 'sale'
      and source_id = p_id
      and status = 'posted'
    for update
  loop
    perform public.reverse_journals_for_source(
      'payment', v_pay.id, 'Void sale payment ' || v_pay.id::text, v_user
    );

    update public.payments
    set status = 'void'
    where id = v_pay.id;
  end loop;

  update public.sales
  set status = 'void'
  where id = p_id;

  return p_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- record_payment — lock docs before outstanding; one payment+journal per doc
-- (void of a single doc no longer reverses sibling allocations).
-- ---------------------------------------------------------------------------
create or replace function public.record_payment(
  p_party uuid,
  p_amount numeric,
  p_direction text,
  p_method text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_amount numeric(14, 2);
  v_direction text;
  v_method text;
  v_kind public.payment_kind;
  v_party_kind public.party_kind;
  v_cash_account uuid;
  v_ar_account uuid;
  v_ap_account uuid;
  v_account uuid;
  v_payment_id uuid;
  v_first_payment_id uuid;
  v_journal_id uuid;
  v_outstanding numeric(14, 2);
  v_remaining numeric(14, 2);
  v_apply numeric(14, 2);
  v_doc record;
begin
  if not public.has_role(array['admin', 'accountant']::public.app_role[]) then
    raise exception 'permission denied: requires admin or accountant role';
  end if;

  if v_user is null then
    raise exception 'not authenticated';
  end if;

  if p_party is null then
    raise exception 'party is required';
  end if;

  v_amount := round(coalesce(p_amount, 0), 2);
  if v_amount <= 0 then
    raise exception 'payment amount must be > 0 (got %)', p_amount;
  end if;

  v_direction := lower(trim(coalesce(p_direction, '')));
  v_method := lower(trim(coalesce(p_method, '')));

  if v_direction in ('receipt', 'in', 'customer') then
    v_kind := 'receipt';
  elsif v_direction in ('disbursement', 'out', 'supplier') then
    v_kind := 'disbursement';
  else
    raise exception
      'p_direction must be receipt|in|customer or disbursement|out|supplier (got %)',
      p_direction;
  end if;

  if v_method not in ('cash', 'bank') then
    raise exception 'p_method must be cash or bank (got %)', p_method;
  end if;

  select kind into v_party_kind
  from public.parties
  where id = p_party and is_active
  for update;

  if v_party_kind is null then
    raise exception 'party % not found or inactive', p_party;
  end if;

  if v_kind = 'receipt' and v_party_kind <> 'customer' then
    raise exception 'receipt payments require a customer party';
  end if;

  if v_kind = 'disbursement' and v_party_kind <> 'supplier' then
    raise exception 'disbursement payments require a supplier party';
  end if;

  select id into v_cash_account
  from public.accounts
  where code = case when v_method = 'cash' then '1010' else '1020' end;

  select id into v_ar_account from public.accounts where code = '1100';
  select id into v_ap_account from public.accounts where code = '2100';

  if v_cash_account is null or v_ar_account is null or v_ap_account is null then
    raise exception 'chart of accounts missing 1010/1020/1100/2100';
  end if;

  v_account := v_cash_account;

  -- Lock every open doc first, then sum outstanding (closes TOCTOU race).
  if v_kind = 'receipt' then
    perform 1
    from public.sales
    where customer_id = p_party
      and status = 'posted'
      and amount_paid < total
    order by doc_date asc, created_at asc, id asc
    for update;

    select coalesce(sum(total - amount_paid), 0)
    into v_outstanding
    from public.sales
    where customer_id = p_party
      and status = 'posted'
      and amount_paid < total;
  else
    perform 1
    from public.purchases
    where supplier_id = p_party
      and status = 'posted'
      and amount_paid < total
    order by doc_date asc, created_at asc, id asc
    for update;

    select coalesce(sum(total - amount_paid), 0)
    into v_outstanding
    from public.purchases
    where supplier_id = p_party
      and status = 'posted'
      and amount_paid < total;
  end if;

  if v_amount > v_outstanding then
    raise exception
      'overpayment: amount % exceeds outstanding % for party %',
      v_amount, v_outstanding, p_party;
  end if;

  v_remaining := v_amount;

  if v_kind = 'receipt' then
    for v_doc in
      select id, total, amount_paid
      from public.sales
      where customer_id = p_party
        and status = 'posted'
        and amount_paid < total
      order by doc_date asc, created_at asc, id asc
    loop
      exit when v_remaining <= 0;
      v_apply := least(v_remaining, round(v_doc.total - v_doc.amount_paid, 2));

      update public.sales
      set amount_paid = amount_paid + v_apply
      where id = v_doc.id;

      insert into public.payments (
        kind, party_id, account_id, amount, status, payment_date,
        reference, source_type, source_id, created_by
      )
      values (
        v_kind, p_party, v_account, v_apply, 'posted',
        (timezone('utc', now()))::date, v_method, 'sale', v_doc.id, v_user
      )
      returning id into v_payment_id;

      if v_first_payment_id is null then
        v_first_payment_id := v_payment_id;
      end if;

      insert into public.journal_entries (
        entry_date, status, memo, source_type, source_id, created_by
      )
      values (
        (timezone('utc', now()))::date, 'posted',
        'Payment ' || v_payment_id::text, 'payment', v_payment_id, v_user
      )
      returning id into v_journal_id;

      insert into public.journal_lines (
        journal_entry_id, account_id, debit, credit, created_by
      ) values
        (v_journal_id, v_account, v_apply, 0, v_user),
        (v_journal_id, v_ar_account, 0, v_apply, v_user);

      v_remaining := round(v_remaining - v_apply, 2);
    end loop;
  else
    for v_doc in
      select id, total, amount_paid
      from public.purchases
      where supplier_id = p_party
        and status = 'posted'
        and amount_paid < total
      order by doc_date asc, created_at asc, id asc
    loop
      exit when v_remaining <= 0;
      v_apply := least(v_remaining, round(v_doc.total - v_doc.amount_paid, 2));

      update public.purchases
      set amount_paid = amount_paid + v_apply
      where id = v_doc.id;

      insert into public.payments (
        kind, party_id, account_id, amount, status, payment_date,
        reference, source_type, source_id, created_by
      )
      values (
        v_kind, p_party, v_account, v_apply, 'posted',
        (timezone('utc', now()))::date, v_method, 'purchase', v_doc.id, v_user
      )
      returning id into v_payment_id;

      if v_first_payment_id is null then
        v_first_payment_id := v_payment_id;
      end if;

      insert into public.journal_entries (
        entry_date, status, memo, source_type, source_id, created_by
      )
      values (
        (timezone('utc', now()))::date, 'posted',
        'Payment ' || v_payment_id::text, 'payment', v_payment_id, v_user
      )
      returning id into v_journal_id;

      insert into public.journal_lines (
        journal_entry_id, account_id, debit, credit, created_by
      ) values
        (v_journal_id, v_ap_account, v_apply, 0, v_user),
        (v_journal_id, v_account, 0, v_apply, v_user);

      v_remaining := round(v_remaining - v_apply, 2);
    end loop;
  end if;

  if v_remaining <> 0 then
    raise exception 'payment allocation incomplete; remaining %', v_remaining;
  end if;

  if v_first_payment_id is null then
    raise exception 'payment allocation produced no documents';
  end if;

  return v_first_payment_id;
end;
$$;

comment on function public.create_purchase(uuid, date, jsonb, numeric, numeric) is
  'Post purchase with net inv_amount (discounted) into moving avg; ordered locks.';

comment on function public.record_payment(uuid, numeric, text, text) is
  'FIFO payment: locks open docs first; one payment+journal per document applied.';
