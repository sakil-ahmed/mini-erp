-- =============================================================================
-- SQL tests for public.create_purchase
-- Run after 0001_schema + 0002_purchase (e.g. supabase db reset && psql -f …).
-- Entire script is wrapped in a transaction and rolled back.
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Fixture: auth user + purchase-role profile (auth.uid via JWT claim)
-- ---------------------------------------------------------------------------
do $$
declare
  v_user_id uuid := 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
begin
  -- Minimal auth.users row compatible with local Supabase Auth schema.
  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change
  )
  values (
    '00000000-0000-0000-0000-000000000000',
    v_user_id,
    'authenticated',
    'authenticated',
    'purchase-tester@example.com',
    crypt('test-password', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"Purchase Tester"}'::jsonb,
    now(),
    now(),
    '',
    '',
    '',
    ''
  )
  on conflict (id) do nothing;

  -- Trigger may have inserted sales; force purchase role for the RPC gate.
  insert into public.profiles (id, full_name, role)
  values (v_user_id, 'Purchase Tester', 'purchase')
  on conflict (id) do update
    set role = excluded.role,
        full_name = excluded.full_name;

  perform set_config('request.jwt.claim.sub', v_user_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_user_id)::text, true);
end;
$$;

-- ---------------------------------------------------------------------------
-- Fixture: supplier + product with known starting stock / avg_cost
-- Start: qty 10 @ avg 5.00 → after buy 10 @ 7.00 → qty 20, avg 6.00
-- ---------------------------------------------------------------------------
do $$
declare
  v_supplier uuid;
  v_product uuid;
  v_purchase uuid;
  v_stock numeric(14, 3);
  v_avg numeric(14, 2);
  v_move_qty numeric(14, 3);
  v_dr numeric(14, 2);
  v_cr numeric(14, 2);
  v_inv_dr numeric(14, 2);
  v_cash_cr numeric(14, 2);
  v_ap_cr numeric(14, 2);
  v_journal uuid;
begin
  insert into public.parties (kind, name, is_active)
  values ('supplier', 'Test Supplier Co', true)
  returning id into v_supplier;

  insert into public.products (
    sku, name, unit, sale_price, avg_cost, stock_qty, reorder_level, is_active
  )
  values (
    'TEST-SKU-001', 'Widget', 'ea', 12.00, 5.00, 10.000, 2.000, true
  )
  returning id into v_product;

  -- Purchase: 10 units @ 7.00 = 70.00; discount 10 → total 60; paid 25 → AP 35
  v_purchase := public.create_purchase(
    v_supplier,
    current_date,
    jsonb_build_array(
      jsonb_build_object(
        'product_id', v_product,
        'qty', 10,
        'unit_cost', 7.00
      )
    ),
    10.00, -- discount
    25.00  -- paid
  );

  if v_purchase is null then
    raise exception 'TEST FAIL: create_purchase returned null';
  end if;

  -- 1) Stock increased by purchased qty
  select stock_qty, avg_cost into v_stock, v_avg
  from public.products where id = v_product;

  if v_stock <> 20.000 then
    raise exception 'TEST FAIL: expected stock_qty 20.000, got %', v_stock;
  end if;

  -- 2) Moving average: (10*5 + 10*7) / 20 = 6.00
  if v_avg <> 6.00 then
    raise exception 'TEST FAIL: expected avg_cost 6.00, got %', v_avg;
  end if;

  select qty_delta into v_move_qty
  from public.stock_movements
  where source_type = 'purchase'
    and source_id = v_purchase
    and product_id = v_product;

  if v_move_qty is distinct from 10.000 then
    raise exception 'TEST FAIL: expected stock_movement +10, got %', v_move_qty;
  end if;

  -- 3) Journal balances and matches Dr Inventory / Cr Cash / Cr Payable
  select id into v_journal
  from public.journal_entries
  where source_type = 'purchase' and source_id = v_purchase;

  if v_journal is null then
    raise exception 'TEST FAIL: journal entry missing for purchase %', v_purchase;
  end if;

  select
    coalesce(sum(debit), 0),
    coalesce(sum(credit), 0)
  into v_dr, v_cr
  from public.journal_lines
  where journal_entry_id = v_journal;

  if v_dr <> v_cr then
    raise exception 'TEST FAIL: journal unbalanced debit=% credit=%', v_dr, v_cr;
  end if;

  if v_dr <> 60.00 then
    raise exception 'TEST FAIL: expected journal total 60.00, got debit %', v_dr;
  end if;

  select jl.debit into v_inv_dr
  from public.journal_lines jl
  join public.accounts a on a.id = jl.account_id
  where jl.journal_entry_id = v_journal and a.code = '1200';

  select jl.credit into v_cash_cr
  from public.journal_lines jl
  join public.accounts a on a.id = jl.account_id
  where jl.journal_entry_id = v_journal and a.code = '1010';

  select jl.credit into v_ap_cr
  from public.journal_lines jl
  join public.accounts a on a.id = jl.account_id
  where jl.journal_entry_id = v_journal and a.code = '2100';

  if v_inv_dr is distinct from 60.00 then
    raise exception 'TEST FAIL: Inventory debit expected 60.00, got %', v_inv_dr;
  end if;

  if v_cash_cr is distinct from 25.00 then
    raise exception 'TEST FAIL: Cash credit expected 25.00, got %', v_cash_cr;
  end if;

  if v_ap_cr is distinct from 35.00 then
    raise exception 'TEST FAIL: Payable credit expected 35.00, got %', v_ap_cr;
  end if;

  raise notice 'PASS: stock, avg_cost, and journal assertions OK (purchase %)', v_purchase;
end;
$$;

-- ---------------------------------------------------------------------------
-- Negative cases: clear validation errors
-- ---------------------------------------------------------------------------
do $$
declare
  v_supplier uuid;
  v_product uuid;
  v_ok boolean;
begin
  select id into v_supplier from public.parties where name = 'Test Supplier Co' limit 1;
  select id into v_product from public.products where sku = 'TEST-SKU-001' limit 1;

  -- qty <= 0
  begin
    perform public.create_purchase(
      v_supplier,
      current_date,
      jsonb_build_array(
        jsonb_build_object('product_id', v_product, 'qty', 0, 'unit_cost', 1)
      ),
      0,
      0
    );
    raise exception 'TEST FAIL: expected qty > 0 error';
  exception
    when others then
      if sqlerrm not like '%qty must be > 0%' then
        raise exception 'TEST FAIL: unexpected error for qty: %', sqlerrm;
      end if;
  end;

  -- cost < 0
  begin
    perform public.create_purchase(
      v_supplier,
      current_date,
      jsonb_build_array(
        jsonb_build_object('product_id', v_product, 'qty', 1, 'unit_cost', -1)
      ),
      0,
      0
    );
    raise exception 'TEST FAIL: expected unit_cost >= 0 error';
  exception
    when others then
      if sqlerrm not like '%unit_cost must be >= 0%' then
        raise exception 'TEST FAIL: unexpected error for cost: %', sqlerrm;
      end if;
  end;

  -- paid > total
  begin
    perform public.create_purchase(
      v_supplier,
      current_date,
      jsonb_build_array(
        jsonb_build_object('product_id', v_product, 'qty', 1, 'unit_cost', 10)
      ),
      0,
      99
    );
    raise exception 'TEST FAIL: expected paid <= total error';
  exception
    when others then
      if sqlerrm not like '%cannot exceed total%' then
        raise exception 'TEST FAIL: unexpected error for paid: %', sqlerrm;
      end if;
  end;

  raise notice 'PASS: validation error messages OK';
end;
$$;

raise notice 'ALL create_purchase tests passed';

rollback;
