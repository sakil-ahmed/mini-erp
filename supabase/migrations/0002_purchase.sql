-- =============================================================================
-- 0002_purchase.sql — create_purchase RPC
-- Posts a purchase in one transaction: lines, stock in, moving avg, balanced GL.
-- Clients never touch stock_movements / journal_*; this SECURITY DEFINER RPC does.
-- =============================================================================

-- Persist discount / cash paid on the header (inputs are not only GL-side).
alter table public.purchases
  add column if not exists discount numeric(14, 2) not null default 0
    check (discount >= 0),
  add column if not exists amount_paid numeric(14, 2) not null default 0
    check (amount_paid >= 0);

alter table public.purchases
  drop constraint if exists purchases_paid_lte_total;

alter table public.purchases
  add constraint purchases_paid_lte_total
  check (amount_paid <= total);

-- Overload: allow has_role(array['admin','purchase']) style checks.
create or replace function public.has_role(required public.app_role[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = any (required)
  );
$$;

comment on function public.has_role(public.app_role[]) is
  'True if current user role is any of the given roles.';

-- ---------------------------------------------------------------------------
-- create_purchase
-- p_items JSON: [{"product_id":"<uuid>","qty":1,"unit_cost":10.00}, ...]
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
  v_old_qty numeric(14, 3);
  v_old_avg numeric(14, 2);
  v_new_qty numeric(14, 3);
  v_new_avg numeric(14, 2);
  v_inv_account uuid;
  v_cash_account uuid;
  v_payable_account uuid;
  v_supplier_ok boolean;
begin
  -- Role gate first (fail closed before any writes).
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

  -- First pass: validate lines and compute subtotal (no mutations yet).
  for v_item in select value from jsonb_array_elements(p_items)
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

  -- Header
  insert into public.purchases (
    supplier_id,
    doc_date,
    subtotal,
    discount,
    total,
    amount_paid,
    status,
    created_by
  )
  values (
    p_supplier,
    p_date,
    v_subtotal,
    v_discount,
    v_total,
    v_paid,
    'posted',
    v_user
  )
  returning id into v_purchase_id;

  -- Lines + stock + moving average (row lock per product).
  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item ->> 'product_id')::uuid;
    v_qty := (v_item ->> 'qty')::numeric(14, 3);
    v_unit_cost := (v_item ->> 'unit_cost')::numeric(14, 2);
    v_line_total := round(v_qty * v_unit_cost, 2);

    insert into public.purchase_items (
      purchase_id,
      product_id,
      qty,
      unit_cost,
      line_total,
      created_by
    )
    values (
      v_purchase_id,
      v_product_id,
      v_qty,
      v_unit_cost,
      v_line_total,
      v_user
    );

    select stock_qty, avg_cost
    into v_old_qty, v_old_avg
    from public.products
    where id = v_product_id
    for update;

    v_new_qty := v_old_qty + v_qty;

    -- Moving average: (old_qty*old_avg + qty*unit_cost) / (old_qty+qty).
    if v_old_qty = 0 then
      v_new_avg := round(v_unit_cost, 2);
    else
      v_new_avg := round(
        (v_old_qty * v_old_avg + v_qty * v_unit_cost) / v_new_qty,
        2
      );
    end if;

    update public.products
    set
      stock_qty = v_new_qty,
      avg_cost = v_new_avg
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
      'purchase',
      v_qty, -- positive = stock in
      'purchase',
      v_purchase_id,
      'Purchase receipt',
      v_user
    );
  end loop;

  -- Balanced journal: Dr Inventory total; Cr Cash paid; Cr Payable remainder.
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
    'Purchase ' || v_purchase_id::text,
    'purchase',
    v_purchase_id,
    v_user
  )
  returning id into v_journal_id;

  insert into public.journal_lines (
    journal_entry_id,
    account_id,
    debit,
    credit,
    created_by
  )
  values (
    v_journal_id,
    v_inv_account,
    v_total,
    0,
    v_user
  );

  if v_paid > 0 then
    insert into public.journal_lines (
      journal_entry_id,
      account_id,
      debit,
      credit,
      created_by
    )
    values (
      v_journal_id,
      v_cash_account,
      0,
      v_paid,
      v_user
    );
  end if;

  if v_payable > 0 then
    insert into public.journal_lines (
      journal_entry_id,
      account_id,
      debit,
      credit,
      created_by
    )
    values (
      v_journal_id,
      v_payable_account,
      0,
      v_payable,
      v_user
    );
  end if;

  -- Optional cash payment row when money left the till (same tx).
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
      'disbursement',
      p_supplier,
      v_cash_account,
      v_paid,
      'posted',
      p_date,
      'purchase',
      v_purchase_id,
      v_user
    );
  end if;

  return v_purchase_id;
end;
$$;

comment on function public.create_purchase(uuid, date, jsonb, numeric, numeric) is
  'Post a purchase: items, stock in, moving avg_cost, Dr Inventory / Cr Cash+Payable.';

revoke all on function public.create_purchase(uuid, date, jsonb, numeric, numeric)
  from public, anon;

grant execute on function public.create_purchase(uuid, date, jsonb, numeric, numeric)
  to authenticated;
