-- Inventory reads: movement ledger for module roles + low-stock helper column.

drop policy if exists stock_movements_select on public.stock_movements;

create policy stock_movements_select on public.stock_movements
  for select to authenticated
  using (
    public.has_role(array['admin', 'accountant', 'sales', 'purchase'])
  );

-- Enables efficient "low stock only" filters in the inventory UI.
do $$
begin
  alter table public.products
    add column is_low boolean
      generated always as (stock_qty <= reorder_level) stored;
exception
  when duplicate_column then
    null;
end;
$$;

create index if not exists products_is_low_idx on public.products (is_low);
