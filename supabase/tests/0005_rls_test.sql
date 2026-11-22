-- =============================================================================
-- SQL tests for 0005_rls role matrix
-- Run after 0001–0005. Rolls back at the end.
-- =============================================================================

begin;

-- Seed users + shared fixtures as table owner (bypasses RLS)
do $$
declare
  v_uid uuid;
  v_customer uuid;
  v_supplier uuid;
  v_product uuid;
  v_purchase_id uuid;
  v_sale_id uuid;
begin
  foreach v_uid in array array[
    'a0000000-0000-4000-8000-000000000001'::uuid,
    'a0000000-0000-4000-8000-000000000002'::uuid,
    'a0000000-0000-4000-8000-000000000003'::uuid,
    'a0000000-0000-4000-8000-000000000004'::uuid
  ]
  loop
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change
    )
    values (
      '00000000-0000-0000-0000-000000000000',
      v_uid,
      'authenticated', 'authenticated',
      v_uid::text || '@example.com',
      crypt('test', gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
      now(), now(), '', '', '', ''
    )
    on conflict (id) do nothing;
  end loop;

  insert into public.profiles (id, full_name, role) values
    ('a0000000-0000-4000-8000-000000000001', 'Admin', 'admin'),
    ('a0000000-0000-4000-8000-000000000002', 'Sales', 'sales'),
    ('a0000000-0000-4000-8000-000000000003', 'Purchase', 'purchase'),
    ('a0000000-0000-4000-8000-000000000004', 'Accountant', 'accountant')
  on conflict (id) do update set role = excluded.role;

  insert into public.parties (kind, name) values ('customer', 'RLS Customer')
  returning id into v_customer;
  insert into public.parties (kind, name) values ('supplier', 'RLS Supplier')
  returning id into v_supplier;

  insert into public.products (sku, name, avg_cost, stock_qty, sale_price)
  values ('RLS-SKU', 'RLS Product', 5.00, 100, 12.00)
  returning id into v_product;

  -- Act as admin to post docs via RPCs (need JWT)
  perform set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000001', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', 'a0000000-0000-4000-8000-000000000001')::text,
    true
  );

  v_purchase_id := public.create_purchase(
    v_supplier,
    current_date,
    jsonb_build_array(
      jsonb_build_object('product_id', v_product, 'qty', 2, 'unit_cost', 5.00)
    ),
    0,
    0
  );

  v_sale_id := public.create_sale(
    v_customer,
    current_date,
    jsonb_build_array(
      jsonb_build_object('product_id', v_product, 'qty', 1, 'unit_price', 12.00)
    ),
    0,
    0
  );

  -- Stash ids in a temp table for later asserts
  create temporary table rls_fixture (
    customer_id uuid,
    supplier_id uuid,
    product_id uuid,
    purchase_id uuid,
    sale_id uuid
  ) on commit drop;

  insert into rls_fixture values (v_customer, v_supplier, v_product, v_purchase_id, v_sale_id);
end;
$$;

-- Helper: switch JWT identity (still need SET ROLE authenticated for privilege checks)
create or replace function pg_temp.as_user(p_uid uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_uid)::text,
    true
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- SALES role
-- ---------------------------------------------------------------------------
do $$
declare
  v_uid uuid := 'a0000000-0000-4000-8000-000000000002';
  v_n int;
  v_customer uuid;
  v_supplier uuid;
  v_product uuid;
  v_purchase uuid;
  v_sale uuid;
begin
  select customer_id, supplier_id, product_id, purchase_id, sale_id
  into v_customer, v_supplier, v_product, v_purchase, v_sale
  from rls_fixture;

  perform pg_temp.as_user(v_uid);
  execute 'set local role authenticated';

  -- can read products
  select count(*) into v_n from public.products where id = v_product;
  if v_n <> 1 then
    raise exception 'TEST FAIL sales: should read products';
  end if;

  -- can read customers only
  select count(*) into v_n from public.parties where id = v_customer;
  if v_n <> 1 then
    raise exception 'TEST FAIL sales: should read customers';
  end if;
  select count(*) into v_n from public.parties where id = v_supplier;
  if v_n <> 0 then
    raise exception 'TEST FAIL sales: must not read suppliers';
  end if;

  -- can read sales / sale_items
  select count(*) into v_n from public.sales where id = v_sale;
  if v_n <> 1 then
    raise exception 'TEST FAIL sales: should read sales';
  end if;
  select count(*) into v_n from public.sale_items where sale_id = v_sale;
  if v_n < 1 then
    raise exception 'TEST FAIL sales: should read sale_items';
  end if;

  -- cannot read purchases / journals / payments / accounts
  select count(*) into v_n from public.purchases where id = v_purchase;
  if v_n <> 0 then
    raise exception 'TEST FAIL sales: must not read purchases';
  end if;
  select count(*) into v_n from public.accounts;
  if v_n <> 0 then
    raise exception 'TEST FAIL sales: must not read accounts';
  end if;
  select count(*) into v_n from public.journal_entries;
  if v_n <> 0 then
    raise exception 'TEST FAIL sales: must not read journal_entries';
  end if;
  select count(*) into v_n from public.payments;
  if v_n <> 0 then
    raise exception 'TEST FAIL sales: must not read payments';
  end if;
  select count(*) into v_n from public.stock_movements;
  if v_n <> 0 then
    raise exception 'TEST FAIL sales: must not read stock_movements';
  end if;

  -- no direct writes to sales (privilege revoke)
  begin
    insert into public.sales (customer_id, total, subtotal)
    values (v_customer, 1, 1);
    raise exception 'TEST FAIL sales: direct insert into sales should fail';
  exception
    when insufficient_privilege then
      null;
    when others then
      if sqlstate = '42501' then
        null;
      else
        raise exception 'TEST FAIL sales: unexpected write error: %', sqlerrm;
      end if;
  end;

  execute 'reset role';
  raise notice 'PASS: sales role allow/deny matrix';
end;
$$;

-- ---------------------------------------------------------------------------
-- PURCHASE role
-- ---------------------------------------------------------------------------
do $$
declare
  v_uid uuid := 'a0000000-0000-4000-8000-000000000003';
  v_n int;
  v_customer uuid;
  v_supplier uuid;
  v_product uuid;
  v_purchase uuid;
  v_sale uuid;
begin
  select customer_id, supplier_id, product_id, purchase_id, sale_id
  into v_customer, v_supplier, v_product, v_purchase, v_sale
  from rls_fixture;

  perform pg_temp.as_user(v_uid);
  execute 'set local role authenticated';

  select count(*) into v_n from public.products where id = v_product;
  if v_n <> 1 then
    raise exception 'TEST FAIL purchase: should read products';
  end if;

  select count(*) into v_n from public.parties where id = v_supplier;
  if v_n <> 1 then
    raise exception 'TEST FAIL purchase: should read suppliers';
  end if;
  select count(*) into v_n from public.parties where id = v_customer;
  if v_n <> 0 then
    raise exception 'TEST FAIL purchase: must not read customers';
  end if;

  select count(*) into v_n from public.purchases where id = v_purchase;
  if v_n <> 1 then
    raise exception 'TEST FAIL purchase: should read purchases';
  end if;
  select count(*) into v_n from public.purchase_items where purchase_id = v_purchase;
  if v_n < 1 then
    raise exception 'TEST FAIL purchase: should read purchase_items';
  end if;

  select count(*) into v_n from public.sales where id = v_sale;
  if v_n <> 0 then
    raise exception 'TEST FAIL purchase: must not read sales';
  end if;
  select count(*) into v_n from public.journal_entries;
  if v_n <> 0 then
    raise exception 'TEST FAIL purchase: must not read journals';
  end if;

  begin
    insert into public.purchases (supplier_id, total, subtotal)
    values (v_supplier, 1, 1);
    raise exception 'TEST FAIL purchase: direct insert into purchases should fail';
  exception
    when insufficient_privilege then
      null;
    when others then
      if sqlstate = '42501' then
        null;
      else
        raise exception 'TEST FAIL purchase: unexpected write error: %', sqlerrm;
      end if;
  end;

  execute 'reset role';
  raise notice 'PASS: purchase role allow/deny matrix';
end;
$$;

-- ---------------------------------------------------------------------------
-- ACCOUNTANT role — read everything; no direct ledger writes
-- ---------------------------------------------------------------------------
do $$
declare
  v_uid uuid := 'a0000000-0000-4000-8000-000000000004';
  v_n int;
  v_customer uuid;
  v_supplier uuid;
  v_product uuid;
  v_purchase uuid;
  v_sale uuid;
begin
  select customer_id, supplier_id, product_id, purchase_id, sale_id
  into v_customer, v_supplier, v_product, v_purchase, v_sale
  from rls_fixture;

  perform pg_temp.as_user(v_uid);
  execute 'set local role authenticated';

  select count(*) into v_n from public.products where id = v_product;
  if v_n <> 1 then raise exception 'TEST FAIL accountant: products'; end if;

  select count(*) into v_n from public.parties where id in (v_customer, v_supplier);
  if v_n <> 2 then raise exception 'TEST FAIL accountant: parties'; end if;

  select count(*) into v_n from public.purchases where id = v_purchase;
  if v_n <> 1 then raise exception 'TEST FAIL accountant: purchases'; end if;

  select count(*) into v_n from public.sales where id = v_sale;
  if v_n <> 1 then raise exception 'TEST FAIL accountant: sales'; end if;

  select count(*) into v_n from public.accounts where code = '1010';
  if v_n <> 1 then raise exception 'TEST FAIL accountant: accounts'; end if;

  select count(*) into v_n from public.journal_entries
  where source_id in (v_purchase, v_sale);
  if v_n < 1 then raise exception 'TEST FAIL accountant: journal_entries'; end if;

  select count(*) into v_n from public.journal_lines;
  if v_n < 1 then raise exception 'TEST FAIL accountant: journal_lines'; end if;

  select count(*) into v_n from public.stock_movements;
  if v_n < 1 then raise exception 'TEST FAIL accountant: stock_movements'; end if;

  begin
    insert into public.journal_entries (memo) values ('hack');
    raise exception 'TEST FAIL accountant: direct journal insert should fail';
  exception
    when insufficient_privilege then
      null;
    when others then
      if sqlstate = '42501' then
        null;
      else
        raise exception 'TEST FAIL accountant: unexpected write error: %', sqlerrm;
      end if;
  end;

  begin
    insert into public.payments (
      kind, party_id, account_id, amount
    )
    values (
      'receipt',
      v_customer,
      (select id from public.accounts where code = '1010'),
      1.00
    );
    raise exception 'TEST FAIL accountant: direct payments insert should fail';
  exception
    when insufficient_privilege then
      null;
    when others then
      if sqlstate = '42501' then
        null;
      else
        raise exception 'TEST FAIL accountant: unexpected payment write: %', sqlerrm;
      end if;
  end;

  execute 'reset role';
  raise notice 'PASS: accountant role allow/deny matrix';
end;
$$;

-- ---------------------------------------------------------------------------
-- ADMIN role — full read; still no privilege for RPC-only table DML
-- ---------------------------------------------------------------------------
do $$
declare
  v_uid uuid := 'a0000000-0000-4000-8000-000000000001';
  v_n int;
  v_product uuid;
begin
  select product_id into v_product from rls_fixture;

  perform pg_temp.as_user(v_uid);
  execute 'set local role authenticated';

  select count(*) into v_n from public.products where id = v_product;
  if v_n <> 1 then raise exception 'TEST FAIL admin: products'; end if;
  select count(*) into v_n from public.parties;
  if v_n < 2 then raise exception 'TEST FAIL admin: parties'; end if;
  select count(*) into v_n from public.purchases;
  if v_n < 1 then raise exception 'TEST FAIL admin: purchases'; end if;
  select count(*) into v_n from public.sales;
  if v_n < 1 then raise exception 'TEST FAIL admin: sales'; end if;
  select count(*) into v_n from public.accounts;
  if v_n < 1 then raise exception 'TEST FAIL admin: accounts'; end if;
  select count(*) into v_n from public.journal_entries;
  if v_n < 1 then raise exception 'TEST FAIL admin: journals'; end if;

  -- admin may update master data (products)
  update public.products set name = name where id = v_product;

  -- admin still cannot direct-write RPC tables (revoke wins)
  begin
    insert into public.stock_movements (
      product_id, kind, qty_delta, source_type, source_id
    )
    values (v_product, 'adjustment', 1, 'test', gen_random_uuid());
    raise exception 'TEST FAIL admin: direct stock_movements insert should fail';
  exception
    when insufficient_privilege then
      null;
    when others then
      if sqlstate = '42501' then
        null;
      else
        raise exception 'TEST FAIL admin: unexpected stock write: %', sqlerrm;
      end if;
  end;

  execute 'reset role';
  raise notice 'PASS: admin role allow/deny matrix';
end;
$$;

-- has_role(text[]) sanity
do $$
begin
  perform pg_temp.as_user('a0000000-0000-4000-8000-000000000002');
  if not public.has_role(array['sales']) then
    raise exception 'TEST FAIL: has_role(text[]) false for sales';
  end if;
  if public.has_role(array['admin']) then
    raise exception 'TEST FAIL: sales must not has_role admin';
  end if;
  raise notice 'PASS: has_role(text[])';
end;
$$;

raise notice 'ALL RLS role tests passed';

rollback;
