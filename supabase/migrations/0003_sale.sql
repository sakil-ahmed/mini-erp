-- =============================================================================
-- 0003_sale.sql — create_sale RPC
-- Posts a sale in one transaction: lines (cost snapshot), stock out, balanced GL.
-- Clients never touch stock_movements / journal_*; this SECURITY DEFINER RPC does.
-- =============================================================================

-- Persist discount / cash received on the header (mirrors purchases).
alter table public.sales
  add column if not exists discount numeric(14, 2) not null default 0
    check (discount >= 0),
  add column if not exists amount_paid numeric(14, 2) not null default 0
    check (amount_paid >= 0);

alter table public.sales
  drop constraint if exists sales_paid_lte_total;

alter table public.sales
  add constraint sales_paid_lte_total
  check (amount_paid <= total);

-- ---------------------------------------------------------------------------
-- create_sale
-- p_items JSON: [{"product_id":"<uuid>","qty":1,"unit_price":12.00}, ...]
-- unit_cost is NOT accepted from the client — snapshotted from products.avg_cost.
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

  v_discount := coalesce(p_discount, 0);
  v_paid := coalesce(p_paid, 0);

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

  -- Validate lines + prices (stock checked under row lock below).
  for v_item in select value from jsonb_array_elements(p_items)
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
    customer_id,
    doc_date,
    subtotal,
    discount,
    total,
    amount_paid,
    status,
    created_by
  )
  values (
    p_customer,
    p_date,
    v_subtotal,
    v_discount,
    v_total,
    v_paid,
    'posted',
    v_user
  )
  returning id into v_sale_id;

  -- Lock → reject oversell → snapshot cost → stock out.
  for v_item in select value from jsonb_array_elements(p_items)
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

    -- Snapshot avg_cost at post time (COGS basis; product avg_cost unchanged).
    v_unit_cost := v_old_avg;
    v_line_cogs := round(v_qty * v_unit_cost, 2);
    v_cogs_total := v_cogs_total + v_line_cogs;
    v_new_qty := v_old_qty - v_qty;

    insert into public.sale_items (
      sale_id,
      product_id,
      qty,
      unit_price,
      unit_cost,
      line_total,
      created_by
    )
    values (
      v_sale_id,
      v_product_id,
      v_qty,
      v_unit_price,
      v_unit_cost,
      v_line_total,
      v_user
    );

    update public.products
    set stock_qty = v_new_qty
    where id = v_product_id;

    insert into public.stock_movements (
      product_id,
      kind,
      qty_delta,
      source_type,
      source_id,
      note,
      created_by
    )
    values (
      v_product_id,
      'sale',
      -v_qty, -- negative = stock out
      'sale',
      v_sale_id,
      'Sale issue',
      v_user
    );
  end loop;

  -- Single balanced journal:
  --   Dr Cash (paid) + Dr Receivable (due) + Dr COGS
  --   Cr Sales Revenue (total) + Cr Inventory (COGS)
  insert into public.journal_entries (
    entry_date,
    status,
    memo,
    source_type,
    source_id,
    created_by
  )
  values (
    p_date,
    'posted',
    'Sale ' || v_sale_id::text,
    'sale',
    v_sale_id,
    v_user
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

  -- COGS leg (skip if zero-cost inventory — XOR forbids 0/0 lines).
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
      kind,
      party_id,
      account_id,
      amount,
      status,
      payment_date,
      source_type,
      source_id,
      created_by
    )
    values (
      'receipt',
      p_customer,
      v_cash_account,
      v_paid,
      'posted',
      p_date,
      'sale',
      v_sale_id,
      v_user
    );
  end if;

  return v_sale_id;
end;
$$;

comment on function public.create_sale(uuid, date, jsonb, numeric, numeric) is
  'Post a sale: cost snapshot, stock out, Dr Cash+AR+COGS / Cr Revenue+Inventory.';

revoke all on function public.create_sale(uuid, date, jsonb, numeric, numeric)
  from public, anon;

grant execute on function public.create_sale(uuid, date, jsonb, numeric, numeric)
  to authenticated;
