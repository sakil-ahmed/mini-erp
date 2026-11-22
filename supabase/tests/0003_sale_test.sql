-- =============================================================================
-- SQL tests for public.create_sale
-- Run after 0001–0003 (e.g. supabase db reset && psql -f …).
-- Entire script is wrapped in a transaction and rolled back.
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Fixture: auth user + sales-role profile
-- ---------------------------------------------------------------------------
do $$
declare
  v_user_id uuid := 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff';
begin
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
    'sales-tester@example.com',
    crypt('test-password', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"Sales Tester"}'::jsonb,
    now(),
    now(),
    '',
    '',
    '',
    ''
  )
  on conflict (id) do nothing;

  insert into public.profiles (id, full_name, role)
  values (v_user_id, 'Sales Tester', 'sales')
  on conflict (id) do update
    set role = excluded.role,
        full_name = excluded.full_name;

  perform set_config('request.jwt.claim.sub', v_user_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_user_id)::text, true);
end;
$$;

-- ---------------------------------------------------------------------------
-- Happy path: stock decreases, cost snapshot, journal balances
-- Product: 20 @ avg 6.00; sell 5 @ 12.00; discount 5 → total 55; paid 20 → AR 35
-- COGS = 5 * 6.00 = 30.00
-- Journal: Dr Cash 20 + Dr AR 35 + Dr COGS 30 = 85
--          Cr Revenue 55 + Cr Inventory 30 = 85
-- ---------------------------------------------------------------------------
do $$
declare
  v_customer uuid;
  v_product uuid;
  v_sale uuid;
  v_stock numeric(14, 3);
  v_avg numeric(14, 2);
  v_snap_cost numeric(14, 2);
  v_move_qty numeric(14, 3);
  v_dr numeric(14, 2);
  v_cr numeric(14, 2);
  v_journal uuid;
  v_cash_dr numeric(14, 2);
  v_ar_dr numeric(14, 2);
  v_rev_cr numeric(14, 2);
  v_cogs_dr numeric(14, 2);
  v_inv_cr numeric(14, 2);
begin
  insert into public.parties (kind, name, is_active)
  values ('customer', 'Test Customer Ltd', true)
  returning id into v_customer;

  insert into public.products (
    sku, name, unit, sale_price, avg_cost, stock_qty, reorder_level, is_active
  )
  values (
    'TEST-SALE-001', 'Gadget', 'ea', 12.00, 6.00, 20.000, 2.000, true
  )
  returning id into v_product;

  v_sale := public.create_sale(
    v_customer,
    current_date,
    jsonb_build_array(
      jsonb_build_object(
        'product_id', v_product,
        'qty', 5,
        'unit_price', 12.00
      )
    ),
    5.00,  -- discount → total = 60 - 5 = 55
    20.00  -- paid → AR = 35
  );

  if v_sale is null then
    raise exception 'TEST FAIL: create_sale returned null';
  end if;

  select stock_qty, avg_cost into v_stock, v_avg
  from public.products where id = v_product;

  if v_stock <> 15.000 then
    raise exception 'TEST FAIL: expected stock_qty 15.000, got %', v_stock;
  end if;

  -- avg_cost must not change on sale
  if v_avg <> 6.00 then
    raise exception 'TEST FAIL: avg_cost should stay 6.00, got %', v_avg;
  end if;

  select unit_cost into v_snap_cost
  from public.sale_items
  where sale_id = v_sale and product_id = v_product;

  if v_snap_cost is distinct from 6.00 then
    raise exception 'TEST FAIL: expected unit_cost snapshot 6.00, got %', v_snap_cost;
  end if;

  select qty_delta into v_move_qty
  from public.stock_movements
  where source_type = 'sale'
    and source_id = v_sale
    and product_id = v_product;

  if v_move_qty is distinct from -5.000 then
    raise exception 'TEST FAIL: expected stock_movement -5, got %', v_move_qty;
  end if;

  select id into v_journal
  from public.journal_entries
  where source_type = 'sale' and source_id = v_sale;

  if v_journal is null then
    raise exception 'TEST FAIL: journal entry missing for sale %', v_sale;
  end if;

  select coalesce(sum(debit), 0), coalesce(sum(credit), 0)
  into v_dr, v_cr
  from public.journal_lines
  where journal_entry_id = v_journal;

  if v_dr <> v_cr then
    raise exception 'TEST FAIL: journal unbalanced debit=% credit=%', v_dr, v_cr;
  end if;

  if v_dr <> 85.00 then
    raise exception 'TEST FAIL: expected journal total 85.00, got debit %', v_dr;
  end if;

  select jl.debit into v_cash_dr
  from public.journal_lines jl
  join public.accounts a on a.id = jl.account_id
  where jl.journal_entry_id = v_journal and a.code = '1010';

  select jl.debit into v_ar_dr
  from public.journal_lines jl
  join public.accounts a on a.id = jl.account_id
  where jl.journal_entry_id = v_journal and a.code = '1100';

  select jl.credit into v_rev_cr
  from public.journal_lines jl
  join public.accounts a on a.id = jl.account_id
  where jl.journal_entry_id = v_journal and a.code = '4000';

  select jl.debit into v_cogs_dr
  from public.journal_lines jl
  join public.accounts a on a.id = jl.account_id
  where jl.journal_entry_id = v_journal and a.code = '5000';

  select jl.credit into v_inv_cr
  from public.journal_lines jl
  join public.accounts a on a.id = jl.account_id
  where jl.journal_entry_id = v_journal and a.code = '1200';

  if v_cash_dr is distinct from 20.00 then
    raise exception 'TEST FAIL: Cash debit expected 20.00, got %', v_cash_dr;
  end if;
  if v_ar_dr is distinct from 35.00 then
    raise exception 'TEST FAIL: Receivable debit expected 35.00, got %', v_ar_dr;
  end if;
  if v_rev_cr is distinct from 55.00 then
    raise exception 'TEST FAIL: Revenue credit expected 55.00, got %', v_rev_cr;
  end if;
  if v_cogs_dr is distinct from 30.00 then
    raise exception 'TEST FAIL: COGS debit expected 30.00, got %', v_cogs_dr;
  end if;
  if v_inv_cr is distinct from 30.00 then
    raise exception 'TEST FAIL: Inventory credit expected 30.00, got %', v_inv_cr;
  end if;

  raise notice 'PASS: stock decrease, cost snapshot, and journal OK (sale %)', v_sale;
end;
$$;

-- ---------------------------------------------------------------------------
-- Oversell must fail with a clear insufficient-stock error
-- ---------------------------------------------------------------------------
do $$
declare
  v_customer uuid;
  v_product uuid;
begin
  select id into v_customer from public.parties where name = 'Test Customer Ltd' limit 1;
  select id into v_product from public.products where sku = 'TEST-SALE-001' limit 1;

  -- Remaining stock is 15 after happy-path sale; request 100.
  begin
    perform public.create_sale(
      v_customer,
      current_date,
      jsonb_build_array(
        jsonb_build_object(
          'product_id', v_product,
          'qty', 100,
          'unit_price', 12.00
        )
      ),
      0,
      0
    );
    raise exception 'TEST FAIL: expected insufficient stock error';
  exception
    when others then
      if sqlerrm not like 'insufficient stock for product%' then
        raise exception 'TEST FAIL: unexpected oversell error: %', sqlerrm;
      end if;
      if sqlerrm not like '%available%' or sqlerrm not like '%requested%' then
        raise exception 'TEST FAIL: oversell error missing available/requested: %', sqlerrm;
      end if;
  end;

  -- Stock unchanged after failed oversell
  if (select stock_qty from public.products where id = v_product) <> 15.000 then
    raise exception 'TEST FAIL: stock changed after rejected oversell';
  end if;

  raise notice 'PASS: oversell rejected with clear error; stock unchanged';
end;
$$;

raise notice 'ALL create_sale tests passed';

rollback;
