-- =============================================================================
-- 0005_rls.sql — role-based RLS (replace 0001 scaffolding policies)
-- Visibility by role; document/ledger writes are RPC-only (privilege revoke).
-- =============================================================================

-- text[] overload for policy expressions: has_role(array['sales','admin'])
create or replace function public.has_role(required text[])
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
      and p.role::text = any (required)
  );
$$;

comment on function public.has_role(text[]) is
  'True if auth.uid() profile.role is any of the given role names.';

-- Keep enum overloads in sync (admin is an explicit list member, not a bypass).
create or replace function public.has_role(required public.app_role)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_role(array[required::text]);
$$;

create or replace function public.has_role(required public.app_role[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_role(required::text[]);
$$;

-- ---------------------------------------------------------------------------
-- Drop legacy policies from 0001_schema
-- ---------------------------------------------------------------------------
drop policy if exists profiles_select_own_or_admin on public.profiles;
drop policy if exists profiles_update_admin on public.profiles;

drop policy if exists products_select on public.products;
drop policy if exists products_insert on public.products;
drop policy if exists products_update on public.products;

drop policy if exists parties_select on public.parties;
drop policy if exists parties_insert on public.parties;
drop policy if exists parties_update on public.parties;

drop policy if exists accounts_select on public.accounts;
drop policy if exists accounts_insert on public.accounts;
drop policy if exists accounts_update on public.accounts;

drop policy if exists purchases_select on public.purchases;
drop policy if exists purchases_insert on public.purchases;
drop policy if exists purchases_update on public.purchases;

drop policy if exists purchase_items_select on public.purchase_items;
drop policy if exists purchase_items_insert on public.purchase_items;
drop policy if exists purchase_items_update on public.purchase_items;

drop policy if exists sales_select on public.sales;
drop policy if exists sales_insert on public.sales;
drop policy if exists sales_update on public.sales;

drop policy if exists sale_items_select on public.sale_items;
drop policy if exists sale_items_insert on public.sale_items;
drop policy if exists sale_items_update on public.sale_items;

drop policy if exists payments_select on public.payments;
drop policy if exists payments_insert on public.payments;
drop policy if exists payments_update on public.payments;

drop policy if exists stock_movements_select on public.stock_movements;
drop policy if exists journal_entries_select on public.journal_entries;
drop policy if exists journal_lines_select on public.journal_lines;

-- Ensure RLS is on (idempotent with 0001)
alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.parties enable row level security;
alter table public.purchases enable row level security;
alter table public.purchase_items enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.stock_movements enable row level security;
alter table public.accounts enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;
alter table public.payments enable row level security;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = auth.uid()
    or public.has_role(array['admin', 'accountant'])
  );

create policy profiles_admin_all on public.profiles
  for all to authenticated
  using (public.has_role(array['admin']))
  with check (public.has_role(array['admin']));

-- ---------------------------------------------------------------------------
-- products — sales + purchase + accountant read; admin full
-- ---------------------------------------------------------------------------
create policy products_select on public.products
  for select to authenticated
  using (public.has_role(array['admin', 'sales', 'purchase', 'accountant']));

create policy products_admin_write on public.products
  for all to authenticated
  using (public.has_role(array['admin']))
  with check (public.has_role(array['admin']));

-- ---------------------------------------------------------------------------
-- parties — sales→customers, purchase→suppliers, accountant/admin→all
-- ---------------------------------------------------------------------------
create policy parties_select on public.parties
  for select to authenticated
  using (
    public.has_role(array['admin', 'accountant'])
    or (public.has_role(array['sales']) and kind = 'customer')
    or (public.has_role(array['purchase']) and kind = 'supplier')
  );

create policy parties_admin_write on public.parties
  for all to authenticated
  using (public.has_role(array['admin']))
  with check (public.has_role(array['admin']));

-- ---------------------------------------------------------------------------
-- purchases / purchase_items — purchase + accountant + admin read; no client writes
-- ---------------------------------------------------------------------------
create policy purchases_select on public.purchases
  for select to authenticated
  using (public.has_role(array['admin', 'purchase', 'accountant']));

create policy purchase_items_select on public.purchase_items
  for select to authenticated
  using (public.has_role(array['admin', 'purchase', 'accountant']));

-- ---------------------------------------------------------------------------
-- sales / sale_items — sales + accountant + admin read; no client writes
-- ---------------------------------------------------------------------------
create policy sales_select on public.sales
  for select to authenticated
  using (public.has_role(array['admin', 'sales', 'accountant']));

create policy sale_items_select on public.sale_items
  for select to authenticated
  using (public.has_role(array['admin', 'sales', 'accountant']));

-- ---------------------------------------------------------------------------
-- accounting tables — accountant + admin read; no client writes
-- ---------------------------------------------------------------------------
create policy accounts_select on public.accounts
  for select to authenticated
  using (public.has_role(array['admin', 'accountant']));

create policy accounts_admin_write on public.accounts
  for all to authenticated
  using (public.has_role(array['admin']))
  with check (public.has_role(array['admin']));

create policy stock_movements_select on public.stock_movements
  for select to authenticated
  using (public.has_role(array['admin', 'accountant']));

create policy journal_entries_select on public.journal_entries
  for select to authenticated
  using (public.has_role(array['admin', 'accountant']));

create policy journal_lines_select on public.journal_lines
  for select to authenticated
  using (public.has_role(array['admin', 'accountant']));

create policy payments_select on public.payments
  for select to authenticated
  using (public.has_role(array['admin', 'accountant']));

-- ---------------------------------------------------------------------------
-- Privilege layer: RPC-only tables — no direct DML from authenticated/anon
-- (SECURITY DEFINER RPCs still write as table owner.)
-- ---------------------------------------------------------------------------
revoke insert, update, delete on public.purchases from authenticated, anon;
revoke insert, update, delete on public.purchase_items from authenticated, anon;
revoke insert, update, delete on public.sales from authenticated, anon;
revoke insert, update, delete on public.sale_items from authenticated, anon;
revoke insert, update, delete on public.stock_movements from authenticated, anon;
revoke insert, update, delete on public.journal_entries from authenticated, anon;
revoke insert, update, delete on public.journal_lines from authenticated, anon;
revoke insert, update, delete on public.payments from authenticated, anon;

-- SELECT remains available so RLS can filter rows.
grant select on public.profiles to authenticated;
grant select on public.products to authenticated;
grant select on public.parties to authenticated;
grant select on public.purchases to authenticated;
grant select on public.purchase_items to authenticated;
grant select on public.sales to authenticated;
grant select on public.sale_items to authenticated;
grant select on public.stock_movements to authenticated;
grant select on public.accounts to authenticated;
grant select on public.journal_entries to authenticated;
grant select on public.journal_lines to authenticated;
grant select on public.payments to authenticated;

grant insert, update, delete on public.profiles to authenticated;
grant insert, update, delete on public.products to authenticated;
grant insert, update, delete on public.parties to authenticated;
grant insert, update, delete on public.accounts to authenticated;
