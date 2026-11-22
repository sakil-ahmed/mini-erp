-- =============================================================================
-- 0006_seed.sql — demo master data + sample postings for the dashboard
-- Demo user UUIDs match supabase/seed-users.md (password: password123).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Demo auth users (idempotent). Trigger creates profiles as 'sales'; we fix roles.
-- ---------------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select *
    from (
      values
        (
          '11111111-1111-4111-8111-111111111111'::uuid,
          'admin@mini-erp.local',
          'Demo Admin',
          'admin'::public.app_role
        ),
        (
          '22222222-2222-4222-8222-222222222222'::uuid,
          'sales@mini-erp.local',
          'Demo Sales',
          'sales'::public.app_role
        ),
        (
          '33333333-3333-4333-8333-333333333333'::uuid,
          'purchase@mini-erp.local',
          'Demo Purchase',
          'purchase'::public.app_role
        ),
        (
          '44444444-4444-4444-8444-444444444444'::uuid,
          'accountant@mini-erp.local',
          'Demo Accountant',
          'accountant'::public.app_role
        )
    ) as t(id, email, full_name, role)
  loop
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
      r.id,
      'authenticated',
      'authenticated',
      r.email,
      crypt('password123', gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('full_name', r.full_name),
      now(),
      now(),
      '',
      '',
      '',
      ''
    )
    on conflict (id) do update
      set email = excluded.email,
          encrypted_password = excluded.encrypted_password,
          raw_user_meta_data = excluded.raw_user_meta_data;

    insert into public.profiles (id, full_name, role)
    values (r.id, r.full_name, r.role)
    on conflict (id) do update
      set full_name = excluded.full_name,
          role = excluded.role;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Parties: 3 suppliers, 4 customers
-- ---------------------------------------------------------------------------
insert into public.parties (id, kind, name, email, phone, is_active)
values
  ('b1000000-0000-4000-8000-000000000001', 'supplier', 'Dhaka Traders', 'po@dhakatraders.example', '01710000001', true),
  ('b1000000-0000-4000-8000-000000000002', 'supplier', 'Chittagong Supply Co', 'orders@ctgsupply.example', '01810000002', true),
  ('b1000000-0000-4000-8000-000000000003', 'supplier', 'Rajshahi Wholesale', 'sales@rajwholesale.example', '01910000003', true),
  ('b2000000-0000-4000-8000-000000000001', 'customer', 'City Mart', 'buy@citymart.example', '01620000001', true),
  ('b2000000-0000-4000-8000-000000000002', 'customer', 'Green Grocery', 'orders@greengrocery.example', '01620000002', true),
  ('b2000000-0000-4000-8000-000000000003', 'customer', 'Tech Corner', 'procure@techcorner.example', '01620000003', true),
  ('b2000000-0000-4000-8000-000000000004', 'customer', 'Office Plus', 'ap@officeplus.example', '01620000004', true)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Products: 10 SKUs (SKU-010 is intentionally low-stock after seed sales)
-- ---------------------------------------------------------------------------
insert into public.products (
  id, sku, name, unit, sale_price, avg_cost, stock_qty, reorder_level, is_active
)
values
  ('c1000000-0000-4000-8000-000000000001', 'SKU-001', 'A4 Paper Ream', 'ream', 450.00, 0, 0, 20, true),
  ('c1000000-0000-4000-8000-000000000002', 'SKU-002', 'Ballpoint Pen Blue', 'box', 120.00, 0, 0, 30, true),
  ('c1000000-0000-4000-8000-000000000003', 'SKU-003', 'Stapler Heavy Duty', 'ea', 350.00, 0, 0, 10, true),
  ('c1000000-0000-4000-8000-000000000004', 'SKU-004', 'Notebook A5', 'ea', 80.00, 0, 0, 40, true),
  ('c1000000-0000-4000-8000-000000000005', 'SKU-005', 'USB Flash 32GB', 'ea', 650.00, 0, 0, 15, true),
  ('c1000000-0000-4000-8000-000000000006', 'SKU-006', 'Whiteboard Marker', 'pack', 200.00, 0, 0, 25, true),
  ('c1000000-0000-4000-8000-000000000007', 'SKU-007', 'File Folder', 'pack', 180.00, 0, 0, 20, true),
  ('c1000000-0000-4000-8000-000000000008', 'SKU-008', 'Printer Ink Black', 'ea', 900.00, 0, 0, 12, true),
  ('c1000000-0000-4000-8000-000000000009', 'SKU-009', 'Desk Organizer', 'ea', 550.00, 0, 0, 8, true),
  -- Low-stock candidate: high reorder_level; we buy little and sell most of it
  ('c1000000-0000-4000-8000-000000000010', 'SKU-010', 'Thermal Paper Roll', 'roll', 95.00, 0, 0, 50, true)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Sample transactions as admin (JWT claim → auth.uid / has_role)
-- ---------------------------------------------------------------------------
do $$
declare
  v_admin uuid := '11111111-1111-4111-8111-111111111111';
  v_po1 uuid;
  v_po2 uuid;
  v_po3 uuid;
  v_so1 uuid;
  v_so2 uuid;
  v_so3 uuid;
begin
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text,
    true
  );

  -- Purchase 1: Dhaka Traders — bulk stationery (partial cash)
  v_po1 := public.create_purchase(
    'b1000000-0000-4000-8000-000000000001',
    current_date - 14,
    jsonb_build_array(
      jsonb_build_object(
        'product_id', 'c1000000-0000-4000-8000-000000000001',
        'qty', 40,
        'unit_cost', 320.00
      ),
      jsonb_build_object(
        'product_id', 'c1000000-0000-4000-8000-000000000002',
        'qty', 50,
        'unit_cost', 70.00
      ),
      jsonb_build_object(
        'product_id', 'c1000000-0000-4000-8000-000000000004',
        'qty', 60,
        'unit_cost', 45.00
      )
    ),
    0,        -- no header discount (keeps avg_cost aligned with Inventory GL)
    10000.00  -- paid
  );

  -- Purchase 2: Chittagong — electronics & ink
  v_po2 := public.create_purchase(
    'b1000000-0000-4000-8000-000000000002',
    current_date - 10,
    jsonb_build_array(
      jsonb_build_object(
        'product_id', 'c1000000-0000-4000-8000-000000000005',
        'qty', 25,
        'unit_cost', 480.00
      ),
      jsonb_build_object(
        'product_id', 'c1000000-0000-4000-8000-000000000008',
        'qty', 20,
        'unit_cost', 700.00
      ),
      jsonb_build_object(
        'product_id', 'c1000000-0000-4000-8000-000000000003',
        'qty', 15,
        'unit_cost', 220.00
      )
    ),
    0,
    5000.00
  );

  -- Purchase 3: Rajshahi — markers, folders, organizer + small thermal stock
  v_po3 := public.create_purchase(
    'b1000000-0000-4000-8000-000000000003',
    current_date - 7,
    jsonb_build_array(
      jsonb_build_object(
        'product_id', 'c1000000-0000-4000-8000-000000000006',
        'qty', 30,
        'unit_cost', 110.00
      ),
      jsonb_build_object(
        'product_id', 'c1000000-0000-4000-8000-000000000007',
        'qty', 25,
        'unit_cost', 95.00
      ),
      jsonb_build_object(
        'product_id', 'c1000000-0000-4000-8000-000000000009',
        'qty', 12,
        'unit_cost', 340.00
      ),
      -- Only 8 rolls vs reorder_level 50 → low stock after sales below
      jsonb_build_object(
        'product_id', 'c1000000-0000-4000-8000-000000000010',
        'qty', 8,
        'unit_cost', 55.00
      )
    ),
    0,
    0
  );

  -- Sale 1: City Mart — partial payment
  v_so1 := public.create_sale(
    'b2000000-0000-4000-8000-000000000001',
    current_date - 5,
    jsonb_build_array(
      jsonb_build_object(
        'product_id', 'c1000000-0000-4000-8000-000000000001',
        'qty', 10,
        'unit_price', 450.00
      ),
      jsonb_build_object(
        'product_id', 'c1000000-0000-4000-8000-000000000002',
        'qty', 12,
        'unit_price', 120.00
      )
    ),
    100.00,
    2000.00
  );

  -- Sale 2: Tech Corner
  v_so2 := public.create_sale(
    'b2000000-0000-4000-8000-000000000003',
    current_date - 3,
    jsonb_build_array(
      jsonb_build_object(
        'product_id', 'c1000000-0000-4000-8000-000000000005',
        'qty', 6,
        'unit_price', 650.00
      ),
      jsonb_build_object(
        'product_id', 'c1000000-0000-4000-8000-000000000008',
        'qty', 4,
        'unit_price', 900.00
      )
    ),
    0,
    1500.00
  );

  -- Sale 3: Office Plus — burns most thermal rolls (leaves stock below reorder)
  v_so3 := public.create_sale(
    'b2000000-0000-4000-8000-000000000004',
    current_date - 1,
    jsonb_build_array(
      jsonb_build_object(
        'product_id', 'c1000000-0000-4000-8000-000000000010',
        'qty', 6,
        'unit_price', 95.00
      ),
      jsonb_build_object(
        'product_id', 'c1000000-0000-4000-8000-000000000004',
        'qty', 15,
        'unit_price', 80.00
      ),
      jsonb_build_object(
        'product_id', 'c1000000-0000-4000-8000-000000000006',
        'qty', 8,
        'unit_price', 200.00
      )
    ),
    50.00,
    0
  );

  -- Follow-up payments (accountant/admin): clear some AR/AP
  perform set_config('request.jwt.claim.sub', '44444444-4444-4444-8444-444444444444', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', '44444444-4444-4444-8444-444444444444',
      'role', 'authenticated'
    )::text,
    true
  );

  -- City Mart AR remainder (FIFO on open sales)
  perform public.record_payment(
    'b2000000-0000-4000-8000-000000000001',
    2000.00,
    'receipt',
    'bank'
  );

  -- Green Grocery: small cash sale then full receipt via payment path
  -- (create as admin first)
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text,
    true
  );

  perform public.create_sale(
    'b2000000-0000-4000-8000-000000000002',
    current_date,
    jsonb_build_array(
      jsonb_build_object(
        'product_id', 'c1000000-0000-4000-8000-000000000007',
        'qty', 5,
        'unit_price', 180.00
      ),
      jsonb_build_object(
        'product_id', 'c1000000-0000-4000-8000-000000000009',
        'qty', 2,
        'unit_price', 550.00
      )
    ),
    0,
    0
  );

  perform set_config('request.jwt.claim.sub', '44444444-4444-4444-8444-444444444444', true);
  perform set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', '44444444-4444-4444-8444-444444444444',
      'role', 'authenticated'
    )::text,
    true
  );

  perform public.record_payment(
    'b2000000-0000-4000-8000-000000000002',
    500.00,
    'receipt',
    'cash'
  );

  -- Pay down Rajshahi payable
  perform public.record_payment(
    'b1000000-0000-4000-8000-000000000003',
    3000.00,
    'disbursement',
    'bank'
  );

  -- Pay down Dhaka Traders payable a bit more
  perform public.record_payment(
    'b1000000-0000-4000-8000-000000000001',
    2500.00,
    'disbursement',
    'cash'
  );

  raise notice 'Seed complete: PO %, %, %; SO %, %, %; SKU-010 should be low stock',
    v_po1, v_po2, v_po3, v_so1, v_so2, v_so3;
end;
$$;
