-- =============================================================================
-- SQL tests for void_purchase, void_sale, record_payment
-- Run after 0001–0004. Entire script rolls back.
-- =============================================================================

begin;

-- Admin fixture (can create docs + void + record payments)
do $$
declare
  v_user_id uuid := 'cccccccc-dddd-eeee-ffff-000000000001';
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  )
  values (
    '00000000-0000-0000-0000-000000000000',
    v_user_id,
    'authenticated', 'authenticated',
    'admin-void@example.com',
    crypt('test-password', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"Admin Void"}'::jsonb,
    now(), now(), '', '', '', ''
  )
  on conflict (id) do nothing;

  insert into public.profiles (id, full_name, role)
  values (v_user_id, 'Admin Void', 'admin')
  on conflict (id) do update set role = 'admin';

  perform set_config('request.jwt.claim.sub', v_user_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_user_id)::text, true);
end;
$$;

-- ---------------------------------------------------------------------------
-- 1) void_purchase: stock reversed, status void, journals balance, double-void fails
-- ---------------------------------------------------------------------------
do $$
declare
  v_supplier uuid;
  v_product uuid;
  v_purchase uuid;
  v_stock numeric(14, 3);
  v_dr numeric(14, 2);
  v_cr numeric(14, 2);
  v_rev_count int;
begin
  insert into public.parties (kind, name) values ('supplier', 'Void Sup')
  returning id into v_supplier;

  insert into public.products (sku, name, avg_cost, stock_qty, sale_price)
  values ('VOID-P-1', 'Bolt', 0, 0, 10)
  returning id into v_product;

  v_purchase := public.create_purchase(
    v_supplier,
    current_date,
    jsonb_build_array(
      jsonb_build_object('product_id', v_product, 'qty', 10, 'unit_cost', 4.00)
    ),
    0,
    0
  );

  perform public.void_purchase(v_purchase);

  select stock_qty into v_stock from public.products where id = v_product;
  if v_stock <> 0 then
    raise exception 'TEST FAIL: expected stock 0 after void purchase, got %', v_stock;
  end if;

  if (select status from public.purchases where id = v_purchase) <> 'void' then
    raise exception 'TEST FAIL: purchase status not void';
  end if;

  select count(*) into v_rev_count
  from public.stock_movements
  where source_type = 'purchase' and source_id = v_purchase and kind = 'void_reversal';

  if v_rev_count <> 1 then
    raise exception 'TEST FAIL: expected 1 void_reversal movement, got %', v_rev_count;
  end if;

  -- Every journal for this purchase (original voided + reversal) must balance internally
  for v_dr, v_cr in
    select coalesce(sum(jl.debit), 0), coalesce(sum(jl.credit), 0)
    from public.journal_entries je
    join public.journal_lines jl on jl.journal_entry_id = je.id
    where je.source_id = v_purchase
      and je.source_type in ('purchase', 'purchase_void')
    group by je.id
  loop
    if v_dr <> v_cr then
      raise exception 'TEST FAIL: unbalanced journal debit=% credit=%', v_dr, v_cr;
    end if;
  end loop;

  begin
    perform public.void_purchase(v_purchase);
    raise exception 'TEST FAIL: expected double-void error';
  exception
    when others then
      if sqlerrm not like '%already void%' then
        raise exception 'TEST FAIL: unexpected double-void error: %', sqlerrm;
      end if;
  end;

  raise notice 'PASS: void_purchase stock/journal/double-void';
end;
$$;

-- ---------------------------------------------------------------------------
-- 2) void_purchase rejected when stock would go negative
-- ---------------------------------------------------------------------------
do $$
declare
  v_supplier uuid;
  v_customer uuid;
  v_product uuid;
  v_purchase uuid;
begin
  insert into public.parties (kind, name) values ('supplier', 'Neg Sup')
  returning id into v_supplier;
  insert into public.parties (kind, name) values ('customer', 'Neg Cust')
  returning id into v_customer;

  insert into public.products (sku, name, avg_cost, stock_qty, sale_price)
  values ('VOID-P-NEG', 'Nut', 0, 0, 10)
  returning id into v_product;

  v_purchase := public.create_purchase(
    v_supplier,
    current_date,
    jsonb_build_array(
      jsonb_build_object('product_id', v_product, 'qty', 5, 'unit_cost', 2.00)
    ),
    0,
    0
  );

  -- Sell all 5 so voiding the purchase would require stock we no longer have
  perform public.create_sale(
    v_customer,
    current_date,
    jsonb_build_array(
      jsonb_build_object('product_id', v_product, 'qty', 5, 'unit_price', 8.00)
    ),
    0,
    0
  );

  begin
    perform public.void_purchase(v_purchase);
    raise exception 'TEST FAIL: expected negative-stock void rejection';
  exception
    when others then
      if sqlerrm not like '%stock would go negative%' then
        raise exception 'TEST FAIL: unexpected void-neg error: %', sqlerrm;
      end if;
  end;

  if (select status from public.purchases where id = v_purchase) <> 'posted' then
    raise exception 'TEST FAIL: purchase should remain posted after rejected void';
  end if;

  raise notice 'PASS: void_purchase rejects negative stock outcome';
end;
$$;

-- ---------------------------------------------------------------------------
-- 3) void_sale restores stock; double void fails
-- ---------------------------------------------------------------------------
do $$
declare
  v_supplier uuid;
  v_customer uuid;
  v_product uuid;
  v_sale uuid;
  v_stock numeric(14, 3);
begin
  insert into public.parties (kind, name) values ('supplier', 'SaleVoid Sup')
  returning id into v_supplier;
  insert into public.parties (kind, name) values ('customer', 'SaleVoid Cust')
  returning id into v_customer;

  insert into public.products (sku, name, avg_cost, stock_qty, sale_price)
  values ('VOID-S-1', 'Washer', 0, 0, 15)
  returning id into v_product;

  perform public.create_purchase(
    v_supplier,
    current_date,
    jsonb_build_array(
      jsonb_build_object('product_id', v_product, 'qty', 8, 'unit_cost', 3.00)
    ),
    0,
    0
  );

  v_sale := public.create_sale(
    v_customer,
    current_date,
    jsonb_build_array(
      jsonb_build_object('product_id', v_product, 'qty', 3, 'unit_price', 9.00)
    ),
    0,
    0
  );

  perform public.void_sale(v_sale);

  select stock_qty into v_stock from public.products where id = v_product;
  if v_stock <> 8.000 then
    raise exception 'TEST FAIL: expected stock restored to 8, got %', v_stock;
  end if;

  if (select status from public.sales where id = v_sale) <> 'void' then
    raise exception 'TEST FAIL: sale status not void';
  end if;

  begin
    perform public.void_sale(v_sale);
    raise exception 'TEST FAIL: expected double void_sale error';
  exception
    when others then
      if sqlerrm not like '%already void%' then
        raise exception 'TEST FAIL: unexpected void_sale double error: %', sqlerrm;
      end if;
  end;

  raise notice 'PASS: void_sale restores stock / rejects double void';
end;
$$;

-- ---------------------------------------------------------------------------
-- 4) record_payment: AR receipt + AP disbursement, journal balance, overpay fails
-- ---------------------------------------------------------------------------
do $$
declare
  v_supplier uuid;
  v_customer uuid;
  v_product uuid;
  v_sale uuid;
  v_purchase uuid;
  v_pay uuid;
  v_paid numeric(14, 2);
  v_dr numeric(14, 2);
  v_cr numeric(14, 2);
  v_journal uuid;
begin
  insert into public.parties (kind, name) values ('supplier', 'Pay Sup')
  returning id into v_supplier;
  insert into public.parties (kind, name) values ('customer', 'Pay Cust')
  returning id into v_customer;

  insert into public.products (sku, name, avg_cost, stock_qty, sale_price)
  values ('PAY-1', 'Screw', 0, 0, 20)
  returning id into v_product;

  v_purchase := public.create_purchase(
    v_supplier,
    current_date,
    jsonb_build_array(
      jsonb_build_object('product_id', v_product, 'qty', 10, 'unit_cost', 5.00)
    ),
    0,
    10.00 -- paid 10 of 50 → outstanding 40
  );

  v_sale := public.create_sale(
    v_customer,
    current_date,
    jsonb_build_array(
      jsonb_build_object('product_id', v_product, 'qty', 4, 'unit_price', 20.00)
    ),
    0,
    30.00 -- paid 30 of 80 → outstanding 50
  );

  -- Customer receipt 50 → fully pays sale
  v_pay := public.record_payment(v_customer, 50.00, 'receipt', 'cash');

  select amount_paid into v_paid from public.sales where id = v_sale;
  if v_paid <> 80.00 then
    raise exception 'TEST FAIL: sale amount_paid expected 80, got %', v_paid;
  end if;

  select id into v_journal
  from public.journal_entries
  where source_type = 'payment' and source_id = v_pay;

  select coalesce(sum(debit), 0), coalesce(sum(credit), 0)
  into v_dr, v_cr
  from public.journal_lines
  where journal_entry_id = v_journal;

  if v_dr <> v_cr or v_dr <> 50.00 then
    raise exception 'TEST FAIL: receipt journal expected 50/50, got %/%', v_dr, v_cr;
  end if;

  -- Supplier disbursement 40 → fully pays purchase remainder
  v_pay := public.record_payment(v_supplier, 40.00, 'disbursement', 'bank');

  select amount_paid into v_paid from public.purchases where id = v_purchase;
  if v_paid <> 50.00 then
    raise exception 'TEST FAIL: purchase amount_paid expected 50, got %', v_paid;
  end if;

  select id into v_journal
  from public.journal_entries
  where source_type = 'payment' and source_id = v_pay;

  select coalesce(sum(debit), 0), coalesce(sum(credit), 0)
  into v_dr, v_cr
  from public.journal_lines
  where journal_entry_id = v_journal;

  if v_dr <> v_cr or v_dr <> 40.00 then
    raise exception 'TEST FAIL: disbursement journal expected 40/40, got %/%', v_dr, v_cr;
  end if;

  -- Overpayment must fail
  begin
    perform public.record_payment(v_customer, 1.00, 'receipt', 'cash');
    raise exception 'TEST FAIL: expected overpayment error';
  exception
    when others then
      if sqlerrm not like 'overpayment%' then
        raise exception 'TEST FAIL: unexpected overpay error: %', sqlerrm;
      end if;
  end;

  raise notice 'PASS: record_payment allocation, journals, overpayment guard';
end;
$$;

raise notice 'ALL void/payment tests passed';

rollback;
