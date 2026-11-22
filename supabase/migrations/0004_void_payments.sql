-- =============================================================================
-- 0004_void_payments.sql — void_purchase, void_sale, record_payment
-- Void = reversal movements + reversing journals (never delete posted rows).
-- Payments allocate FIFO to open docs and refuse overpayment.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Reverse every posted journal tied to a source (swap debit/credit).
-- Marks originals void; inserts a new posted reversing entry.
-- ---------------------------------------------------------------------------
create or replace function public.reverse_journals_for_source(
  p_source_type text,
  p_source_id uuid,
  p_memo text,
  p_user uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entry record;
  v_rev_id uuid;
  v_line record;
begin
  for v_entry in
    select *
    from public.journal_entries
    where source_type = p_source_type
      and source_id = p_source_id
      and status = 'posted'
    for update
  loop
    insert into public.journal_entries (
      entry_date,
      status,
      memo,
      source_type,
      source_id,
      created_by
    )
    values (
      (timezone('utc', now()))::date,
      'posted',
      p_memo,
      p_source_type || '_void',
      p_source_id,
      p_user
    )
    returning id into v_rev_id;

    for v_line in
      select * from public.journal_lines where journal_entry_id = v_entry.id
    loop
      -- Swap sides to reverse the original posting.
      insert into public.journal_lines (
        journal_entry_id,
        account_id,
        debit,
        credit,
        memo,
        created_by
      )
      values (
        v_rev_id,
        v_line.account_id,
        v_line.credit,
        v_line.debit,
        coalesce(v_line.memo, 'reversal'),
        p_user
      );
    end loop;

    update public.journal_entries
    set status = 'void'
    where id = v_entry.id;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- void_purchase — admin only
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

  -- Reverse stock: purchase added qty, void subtracts it (reject if oversold later).
  for v_item in
    select product_id, qty, unit_cost
    from public.purchase_items
    where purchase_id = p_id
    order by product_id
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

    -- Inverse of moving-average intake using the original line unit_cost.
    if v_new_qty = 0 then
      v_new_avg := 0;
    else
      v_new_avg := round(
        (v_old_qty * v_old_avg - v_item.qty * v_item.unit_cost) / v_new_qty,
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
      product_id,
      kind,
      qty_delta,
      source_type,
      source_id,
      note,
      created_by
    )
    values (
      v_item.product_id,
      'void_reversal',
      -v_item.qty,
      'purchase',
      p_id,
      'Void purchase reversal',
      v_user
    );
  end loop;

  -- Reverse original purchase journal + any later payment journals for this doc.
  perform public.reverse_journals_for_source(
    'purchase',
    p_id,
    'Void purchase ' || p_id::text,
    v_user
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
      'payment',
      v_pay.id,
      'Void purchase payment ' || v_pay.id::text,
      v_user
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

comment on function public.void_purchase(uuid) is
  'Admin void: reverse stock/GL for a posted purchase; rejects double void and negative stock.';

-- ---------------------------------------------------------------------------
-- void_sale — admin only
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

  -- Sale removed stock; void puts it back (avg_cost unchanged — sale never moved it).
  for v_item in
    select product_id, qty
    from public.sale_items
    where sale_id = p_id
    order by product_id
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
      product_id,
      kind,
      qty_delta,
      source_type,
      source_id,
      note,
      created_by
    )
    values (
      v_item.product_id,
      'void_reversal',
      v_item.qty,
      'sale',
      p_id,
      'Void sale reversal',
      v_user
    );
  end loop;

  perform public.reverse_journals_for_source(
    'sale',
    p_id,
    'Void sale ' || p_id::text,
    v_user
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
      'payment',
      v_pay.id,
      'Void sale payment ' || v_pay.id::text,
      v_user
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

comment on function public.void_sale(uuid) is
  'Admin void: reverse stock/GL for a posted sale; rejects double void.';

-- ---------------------------------------------------------------------------
-- record_payment — allocate FIFO to open docs; refuse overpayment
-- p_direction: receipt|in|customer  → Dr Cash/Bank Cr Receivable
--              disbursement|out|supplier → Dr Payable Cr Cash/Bank
-- p_method: cash → 1010, bank → 1020
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

  -- Outstanding balance across posted open documents for this party.
  if v_kind = 'receipt' then
    select coalesce(sum(total - amount_paid), 0)
    into v_outstanding
    from public.sales
    where customer_id = p_party
      and status = 'posted'
      and amount_paid < total;
  else
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

  insert into public.payments (
    kind,
    party_id,
    account_id,
    amount,
    status,
    payment_date,
    reference,
    created_by
  )
  values (
    v_kind,
    p_party,
    v_account,
    v_amount,
    'posted',
    (timezone('utc', now()))::date,
    v_method,
    v_user
  )
  returning id into v_payment_id;

  -- FIFO allocate to oldest open docs; stamp source on payment to first doc applied.
  v_remaining := v_amount;

  if v_kind = 'receipt' then
    for v_doc in
      select id, total, amount_paid
      from public.sales
      where customer_id = p_party
        and status = 'posted'
        and amount_paid < total
      order by doc_date asc, created_at asc
      for update
    loop
      exit when v_remaining <= 0;
      v_apply := least(v_remaining, round(v_doc.total - v_doc.amount_paid, 2));

      update public.sales
      set amount_paid = amount_paid + v_apply
      where id = v_doc.id;

      if not exists (
        select 1 from public.payments where id = v_payment_id and source_id is not null
      ) then
        update public.payments
        set source_type = 'sale', source_id = v_doc.id
        where id = v_payment_id;
      end if;

      v_remaining := round(v_remaining - v_apply, 2);
    end loop;
  else
    for v_doc in
      select id, total, amount_paid
      from public.purchases
      where supplier_id = p_party
        and status = 'posted'
        and amount_paid < total
      order by doc_date asc, created_at asc
      for update
    loop
      exit when v_remaining <= 0;
      v_apply := least(v_remaining, round(v_doc.total - v_doc.amount_paid, 2));

      update public.purchases
      set amount_paid = amount_paid + v_apply
      where id = v_doc.id;

      if not exists (
        select 1 from public.payments where id = v_payment_id and source_id is not null
      ) then
        update public.payments
        set source_type = 'purchase', source_id = v_doc.id
        where id = v_payment_id;
      end if;

      v_remaining := round(v_remaining - v_apply, 2);
    end loop;
  end if;

  if v_remaining <> 0 then
    raise exception 'payment allocation incomplete; remaining %', v_remaining;
  end if;

  -- GL: customer receipt or supplier disbursement.
  insert into public.journal_entries (
    entry_date,
    status,
    memo,
    source_type,
    source_id,
    created_by
  )
  values (
    (timezone('utc', now()))::date,
    'posted',
    'Payment ' || v_payment_id::text,
    'payment',
    v_payment_id,
    v_user
  )
  returning id into v_journal_id;

  if v_kind = 'receipt' then
    -- Dr Cash/Bank, Cr Receivable
    insert into public.journal_lines (
      journal_entry_id, account_id, debit, credit, created_by
    ) values
      (v_journal_id, v_account, v_amount, 0, v_user),
      (v_journal_id, v_ar_account, 0, v_amount, v_user);
  else
    -- Dr Payable, Cr Cash/Bank
    insert into public.journal_lines (
      journal_entry_id, account_id, debit, credit, created_by
    ) values
      (v_journal_id, v_ap_account, v_amount, 0, v_user),
      (v_journal_id, v_account, 0, v_amount, v_user);
  end if;

  return v_payment_id;
end;
$$;

comment on function public.record_payment(uuid, numeric, text, text) is
  'Post party payment to Cash/Bank vs AR/AP; FIFO-updates doc amount_paid; blocks overpay.';

revoke all on function public.void_purchase(uuid) from public, anon;
revoke all on function public.void_sale(uuid) from public, anon;
revoke all on function public.record_payment(uuid, numeric, text, text) from public, anon;
revoke all on function public.reverse_journals_for_source(text, uuid, text, uuid)
  from public, anon, authenticated;

grant execute on function public.void_purchase(uuid) to authenticated;
grant execute on function public.void_sale(uuid) to authenticated;
grant execute on function public.record_payment(uuid, numeric, text, text) to authenticated;
