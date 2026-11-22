-- =============================================================================
-- Integrity fixes: multi-doc payment void, net inv_amount, stock guard
-- =============================================================================

begin;

do $$
declare
  v_user_id uuid := 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeee0010';
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  )
  values (
    '00000000-0000-0000-0000-000000000000',
    v_user_id, 'authenticated', 'authenticated',
    'integrity-admin@example.com',
    crypt('test-password', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"Integrity Admin"}'::jsonb,
    now(), now(), '', '', '', ''
  )
  on conflict (id) do nothing;

  insert into public.profiles (id, full_name, role)
  values (v_user_id, 'Integrity Admin', 'admin')
  on conflict (id) do update
    set role = excluded.role, full_name = excluded.full_name;

  perform set_config('request.jwt.claim.sub', v_user_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_user_id)::text, true);
end;
$$;

-- 1) Discounted purchase: stock value matches Inventory GL
do $$
declare
  v_supplier uuid;
  v_product uuid;
  v_purchase uuid;
  v_stock_value numeric(14, 2);
  v_inv_dr numeric(14, 2);
begin
  insert into public.parties (kind, name) values ('supplier', 'Inv Sup')
  returning id into v_supplier;

  insert into public.products (sku, name, avg_cost, stock_qty, sale_price)
  values ('INV-NET', 'Net Cost Item', 0, 0, 10)
  returning id into v_product;

  v_purchase := public.create_purchase(
    v_supplier,
    current_date,
    jsonb_build_array(
      jsonb_build_object('product_id', v_product, 'qty', 10, 'unit_cost', 7.00)
    ),
    10.00,
    0
  );

  select round(stock_qty * avg_cost, 2) into v_stock_value
  from public.products where id = v_product;

  select jl.debit into v_inv_dr
  from public.journal_lines jl
  join public.journal_entries je on je.id = jl.journal_entry_id
  join public.accounts a on a.id = jl.account_id
  where je.source_type = 'purchase'
    and je.source_id = v_purchase
    and a.code = '1200';

  if v_stock_value is distinct from 60.00 or v_inv_dr is distinct from 60.00 then
    raise exception
      'TEST FAIL: stock value % must equal Inventory Dr % (expected 60)',
      v_stock_value, v_inv_dr;
  end if;

  raise notice 'PASS: discounted purchase stock value matches GL';
end;
$$;

-- 2) Multi-doc FIFO payment: void one sale must not reverse sibling payment GL
do $$
declare
  v_customer uuid;
  v_product uuid;
  v_sale1 uuid;
  v_sale2 uuid;
  v_pay_count integer;
  v_ar_balance numeric(14, 2);
  v_sale2_paid numeric(14, 2);
begin
  insert into public.parties (kind, name) values ('customer', 'Multi Cust')
  returning id into v_customer;

  insert into public.products (sku, name, avg_cost, stock_qty, sale_price)
  values ('MULTI-1', 'Multi Item', 2.00, 100, 10)
  returning id into v_product;

  -- Two open sales, 30 each outstanding (fully on account)
  v_sale1 := public.create_sale(
    v_customer, current_date - 2,
    jsonb_build_array(
      jsonb_build_object('product_id', v_product, 'qty', 3, 'unit_price', 10.00)
    ),
    0, 0
  );

  v_sale2 := public.create_sale(
    v_customer, current_date - 1,
    jsonb_build_array(
      jsonb_build_object('product_id', v_product, 'qty', 3, 'unit_price', 10.00)
    ),
    0, 0
  );

  -- One RPC covers both docs → two payment rows (one per doc)
  perform public.record_payment(v_customer, 60.00, 'receipt', 'cash');

  select count(*) into v_pay_count
  from public.payments
  where party_id = v_customer and status = 'posted' and source_type = 'sale';

  if v_pay_count <> 2 then
    raise exception 'TEST FAIL: expected 2 per-doc payments, got %', v_pay_count;
  end if;

  -- Void older sale only
  perform public.void_sale(v_sale1);

  select amount_paid into v_sale2_paid from public.sales where id = v_sale2;
  if v_sale2_paid is distinct from 30.00 then
    raise exception 'TEST FAIL: sale2 amount_paid should stay 30, got %', v_sale2_paid;
  end if;

  if (select status from public.payments where source_id = v_sale2) <> 'posted' then
    raise exception 'TEST FAIL: sale2 payment must remain posted after voiding sale1';
  end if;

  -- AR GL: sale2 still posted with payment Cr AR 30; sale1 reversed → net AR 0 for these
  select coalesce(sum(jl.debit) - sum(jl.credit), 0)
  into v_ar_balance
  from public.journal_lines jl
  join public.journal_entries je on je.id = jl.journal_entry_id
  join public.accounts a on a.id = jl.account_id
  where a.code = '1100'
    and je.status = 'posted'
    and (
      (je.source_type = 'sale' and je.source_id in (v_sale1, v_sale2))
      or (je.source_type = 'sale_void' and je.source_id = v_sale1)
      or (
        je.source_type = 'payment'
        and je.source_id in (
          select id from public.payments where source_id in (v_sale1, v_sale2)
        )
      )
      or (
        je.source_type = 'payment_void'
        and je.source_id in (
          select id from public.payments where source_id = v_sale1
        )
      )
    );

  -- After void sale1 (+ its payment reverse): remaining should be sale2 Dr 30 + payment Cr 30 = 0
  if v_ar_balance is distinct from 0 then
    raise exception 'TEST FAIL: related AR net expected 0, got %', v_ar_balance;
  end if;

  raise notice 'PASS: multi-doc payment void is per-document';
end;
$$;

-- 3) Direct stock_qty update blocked without RPC GUC
do $$
declare
  v_product uuid;
begin
  insert into public.products (sku, name, avg_cost, stock_qty, sale_price)
  values ('GUARD-1', 'Guarded', 1.00, 5, 2)
  returning id into v_product;

  -- Clear RPC GUC if any prior call left it (new statement — already clear)
  begin
    update public.products set stock_qty = 99 where id = v_product;
    raise exception 'TEST FAIL: expected stock_qty update to be blocked';
  exception
    when others then
      if sqlerrm not like '%RPC-only%' then
        raise exception 'TEST FAIL: unexpected guard error: %', sqlerrm;
      end if;
  end;

  if (select stock_qty from public.products where id = v_product) <> 5 then
    raise exception 'TEST FAIL: stock_qty must remain 5';
  end if;

  raise notice 'PASS: products.stock_qty guarded';
end;
$$;

raise notice 'ALL integrity tests passed';

rollback;
