-- =============================================================================
-- 0011_adjust_stock.sql — manual inventory adjustment RPC (+ GL)
-- Positive qty_delta = stock in (updates moving avg). Negative = stock out at avg.
-- =============================================================================

insert into public.accounts (code, name, account_type)
values ('5100', 'Inventory Adjustments', 'expense')
on conflict (code) do nothing;

create or replace function public.adjust_stock(
  p_product uuid,
  p_qty_delta numeric,
  p_unit_cost numeric default null,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_qty numeric(14, 3);
  v_unit_cost numeric(14, 2);
  v_old_qty numeric(14, 3);
  v_old_avg numeric(14, 2);
  v_new_qty numeric(14, 3);
  v_new_avg numeric(14, 2);
  v_amount numeric(14, 2);
  v_inv_account uuid;
  v_adj_account uuid;
  v_journal_id uuid;
  v_source_id uuid := gen_random_uuid();
  v_note text;
begin
  if not public.has_role(array['admin', 'purchase']::public.app_role[]) then
    raise exception 'permission denied: requires admin or purchase role';
  end if;

  if v_user is null then
    raise exception 'not authenticated';
  end if;

  if p_product is null then
    raise exception 'product is required';
  end if;

  v_qty := round(coalesce(p_qty_delta, 0), 3);
  if v_qty = 0 then
    raise exception 'qty_delta must be non-zero';
  end if;

  perform set_config('app.allow_stock_mutation', '1', true);

  select id into v_inv_account from public.accounts where code = '1200';
  select id into v_adj_account from public.accounts where code = '5100';

  if v_inv_account is null or v_adj_account is null then
    raise exception 'chart of accounts missing 1200/5100';
  end if;

  select stock_qty, avg_cost
  into v_old_qty, v_old_avg
  from public.products
  where id = p_product and is_active
  for update;

  if v_old_qty is null then
    raise exception 'product % not found or inactive', p_product;
  end if;

  v_note := nullif(trim(coalesce(p_note, '')), '');
  if v_note is null then
    v_note := 'Stock adjustment';
  end if;

  if v_qty > 0 then
    v_unit_cost := round(coalesce(p_unit_cost, v_old_avg), 2);
    if v_unit_cost < 0 then
      raise exception 'unit_cost must be >= 0';
    end if;
    if v_old_qty = 0 and (p_unit_cost is null) then
      raise exception 'unit_cost is required when adjusting stock from zero';
    end if;

    v_amount := round(v_qty * v_unit_cost, 2);
    v_new_qty := v_old_qty + v_qty;

    if v_old_qty = 0 then
      v_new_avg := case
        when v_new_qty = 0 then 0
        else round(v_amount / v_new_qty, 2)
      end;
    else
      v_new_avg := round(
        (v_old_qty * v_old_avg + v_amount) / v_new_qty,
        2
      );
    end if;

    update public.products
    set stock_qty = v_new_qty, avg_cost = v_new_avg
    where id = p_product;

    insert into public.stock_movements (
      product_id, kind, qty_delta, source_type, source_id, note, created_by
    )
    values (
      p_product, 'adjustment', v_qty, 'adjustment', v_source_id, v_note, v_user
    );

    if v_amount > 0 then
      insert into public.journal_entries (
        entry_date, status, memo, source_type, source_id, created_by
      )
      values (
        (timezone('utc', now()))::date,
        'posted',
        'Stock adjustment in ' || p_product::text,
        'adjustment',
        v_source_id,
        v_user
      )
      returning id into v_journal_id;

      insert into public.journal_lines (
        journal_entry_id, account_id, debit, credit, created_by
      ) values
        (v_journal_id, v_inv_account, v_amount, 0, v_user),
        (v_journal_id, v_adj_account, 0, v_amount, v_user);
    end if;
  else
    -- Stock out (write-down / count decrease)
    if v_old_qty < abs(v_qty) then
      raise exception
        'insufficient stock for adjustment (available %, requested %)',
        v_old_qty, abs(v_qty);
    end if;

    v_amount := round(abs(v_qty) * v_old_avg, 2);
    v_new_qty := v_old_qty + v_qty; -- v_qty negative

    update public.products
    set stock_qty = v_new_qty
    where id = p_product;

    insert into public.stock_movements (
      product_id, kind, qty_delta, source_type, source_id, note, created_by
    )
    values (
      p_product, 'adjustment', v_qty, 'adjustment', v_source_id, v_note, v_user
    );

    if v_amount > 0 then
      insert into public.journal_entries (
        entry_date, status, memo, source_type, source_id, created_by
      )
      values (
        (timezone('utc', now()))::date,
        'posted',
        'Stock adjustment out ' || p_product::text,
        'adjustment',
        v_source_id,
        v_user
      )
      returning id into v_journal_id;

      insert into public.journal_lines (
        journal_entry_id, account_id, debit, credit, created_by
      ) values
        (v_journal_id, v_adj_account, v_amount, 0, v_user),
        (v_journal_id, v_inv_account, 0, v_amount, v_user);
    end if;
  end if;

  return v_source_id;
end;
$$;

comment on function public.adjust_stock(uuid, numeric, numeric, text) is
  'Manual stock adjustment: updates qty/avg, movement, and Inventory vs 5100 GL.';

revoke all on function public.adjust_stock(uuid, numeric, numeric, text)
  from public, anon;

grant execute on function public.adjust_stock(uuid, numeric, numeric, text)
  to authenticated;
