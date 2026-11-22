-- =============================================================================
-- 0001_schema.sql — Mini ERP core schema
-- Design: all money numeric(14,2), all qty numeric(14,3); posted docs are voided
-- (never deleted); stock/journal mutations belong in SECURITY DEFINER RPCs later.
-- =============================================================================

create extension if not exists "pgcrypto"; -- gen_random_uuid()

-- ---------------------------------------------------------------------------
-- Enums (closed vocabularies beat free-text for role/status filters & RLS)
-- ---------------------------------------------------------------------------
create type public.app_role as enum ('admin', 'sales', 'purchase', 'accountant');
create type public.party_kind as enum ('customer', 'supplier');
create type public.doc_status as enum ('posted', 'void');
-- Signed qty on movements: + in, − out; type explains why (audit trail).
create type public.stock_move_kind as enum (
  'purchase',
  'sale',
  'adjustment',
  'void_reversal'
);
create type public.account_type as enum (
  'asset',
  'liability',
  'equity',
  'revenue',
  'expense'
);
-- Receipt = money in (AR); disbursement = money out (AP).
create type public.payment_kind as enum ('receipt', 'disbursement');

-- ---------------------------------------------------------------------------
-- Doc number sequences (human-readable PO/SO numbers; UUID remains the PK)
-- ---------------------------------------------------------------------------
create sequence public.purchase_doc_seq start 1;
create sequence public.sale_doc_seq start 1;

-- ---------------------------------------------------------------------------
-- profiles — must exist before has_role() (LANGUAGE sql resolves tables at
-- CREATE time). 1:1 with auth.users; app roles live here, not JWT claims.
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  role public.app_role not null default 'sales',
  created_at timestamptz not null default now(),
  -- Self-insert on signup may leave created_by null; later admin edits set it.
  created_by uuid references public.profiles (id)
);

create index profiles_role_idx on public.profiles (role);

-- Auto-create profile when a user signs up (role defaults to sales).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.email),
    'sales'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Role helper — SECURITY DEFINER so RLS policies can check roles without
-- recursive policy evaluation on profiles. (Defined after profiles table.)
-- ---------------------------------------------------------------------------
create or replace function public.has_role(required public.app_role)
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
      and (p.role = required or p.role = 'admin'::public.app_role)
  );
$$;

comment on function public.has_role(public.app_role) is
  'True if current user has the given role (admin implies all).';
-- ---------------------------------------------------------------------------
-- products — stock_qty is denormalized cache; truth is stock_movements (RPC).
-- ---------------------------------------------------------------------------
create table public.products (
  id uuid primary key default gen_random_uuid(),
  sku text not null,
  name text not null,
  unit text not null default 'ea',
  sale_price numeric(14, 2) not null default 0 check (sale_price >= 0),
  avg_cost numeric(14, 2) not null default 0 check (avg_cost >= 0),
  stock_qty numeric(14, 3) not null default 0 check (stock_qty >= 0),
  reorder_level numeric(14, 3) not null default 0 check (reorder_level >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id),
  constraint products_sku_unique unique (sku)
);

create index products_is_active_idx on public.products (is_active);

-- ---------------------------------------------------------------------------
-- parties — customers and suppliers share one table (AP/AR party master).
-- ---------------------------------------------------------------------------
create table public.parties (
  id uuid primary key default gen_random_uuid(),
  kind public.party_kind not null,
  name text not null,
  email text,
  phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id)
);

create index parties_kind_idx on public.parties (kind);
create index parties_name_idx on public.parties (name);

-- ---------------------------------------------------------------------------
-- purchases / purchase_items
-- Header holds status + doc_number; lines hold qty/cost. Totals stored for
-- list queries; RPC must keep them consistent with sum(line_total).
-- ---------------------------------------------------------------------------
create table public.purchases (
  id uuid primary key default gen_random_uuid(),
  -- PO-000001 style; sequence is the source of uniqueness, format is display.
  doc_number text not null default (
    'PO-' || lpad(nextval('public.purchase_doc_seq')::text, 6, '0')
  ),
  supplier_id uuid not null references public.parties (id),
  status public.doc_status not null default 'posted',
  doc_date date not null default (timezone('utc', now()))::date,
  subtotal numeric(14, 2) not null default 0 check (subtotal >= 0),
  total numeric(14, 2) not null default 0 check (total >= 0),
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id),
  constraint purchases_doc_number_unique unique (doc_number)
);

create index purchases_supplier_id_idx on public.purchases (supplier_id);
create index purchases_status_idx on public.purchases (status);
create index purchases_doc_date_idx on public.purchases (doc_date);

create table public.purchase_items (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references public.purchases (id),
  product_id uuid not null references public.products (id),
  qty numeric(14, 3) not null check (qty > 0),
  unit_cost numeric(14, 2) not null check (unit_cost >= 0),
  -- Stored (not generated) so historical lines survive product price changes.
  line_total numeric(14, 2) not null check (line_total >= 0),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id),
  constraint purchase_items_line_total_matches
    check (line_total = round(qty * unit_cost, 2))
);

create index purchase_items_purchase_id_idx on public.purchase_items (purchase_id);
create index purchase_items_product_id_idx on public.purchase_items (product_id);

-- ---------------------------------------------------------------------------
-- sales / sale_items — unit_cost is a snapshot at post time for COGS (avg_cost
-- on the product will move; the sale line must not).
-- ---------------------------------------------------------------------------
create table public.sales (
  id uuid primary key default gen_random_uuid(),
  doc_number text not null default (
    'SO-' || lpad(nextval('public.sale_doc_seq')::text, 6, '0')
  ),
  customer_id uuid not null references public.parties (id),
  status public.doc_status not null default 'posted',
  doc_date date not null default (timezone('utc', now()))::date,
  subtotal numeric(14, 2) not null default 0 check (subtotal >= 0),
  total numeric(14, 2) not null default 0 check (total >= 0),
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id),
  constraint sales_doc_number_unique unique (doc_number)
);

create index sales_customer_id_idx on public.sales (customer_id);
create index sales_status_idx on public.sales (status);
create index sales_doc_date_idx on public.sales (doc_date);

create table public.sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales (id),
  product_id uuid not null references public.products (id),
  qty numeric(14, 3) not null check (qty > 0),
  unit_price numeric(14, 2) not null check (unit_price >= 0),
  -- Snapshot of product.avg_cost when the sale was posted (COGS basis).
  unit_cost numeric(14, 2) not null check (unit_cost >= 0),
  line_total numeric(14, 2) not null check (line_total >= 0),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id),
  constraint sale_items_line_total_matches
    check (line_total = round(qty * unit_price, 2))
);

create index sale_items_sale_id_idx on public.sale_items (sale_id);
create index sale_items_product_id_idx on public.sale_items (product_id);

-- ---------------------------------------------------------------------------
-- stock_movements — append-only ledger; qty_delta signed (+ receipt, − issue).
-- Client must never write this table (RLS + revoke); only posting RPCs.
-- ---------------------------------------------------------------------------
create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id),
  kind public.stock_move_kind not null,
  qty_delta numeric(14, 3) not null check (qty_delta <> 0),
  -- Polymorphic source (purchase/sale/adjustment id) for audit drill-down.
  source_type text not null,
  source_id uuid not null,
  note text,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id)
);

create index stock_movements_product_id_idx on public.stock_movements (product_id);
create index stock_movements_source_idx on public.stock_movements (source_type, source_id);
create index stock_movements_created_at_idx on public.stock_movements (created_at);

-- Block UPDATE/DELETE so history cannot be rewritten even by table owners via SQL.
create or replace function public.reject_stock_movement_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'stock_movements is append-only';
end;
$$;

create trigger stock_movements_no_update
  before update on public.stock_movements
  for each row execute function public.reject_stock_movement_mutation();

create trigger stock_movements_no_delete
  before delete on public.stock_movements
  for each row execute function public.reject_stock_movement_mutation();

-- ---------------------------------------------------------------------------
-- accounts — chart of accounts; code is the stable natural key for seeds/RPCs.
-- ---------------------------------------------------------------------------
create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  name text not null,
  account_type public.account_type not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id),
  constraint accounts_code_unique unique (code)
);

create index accounts_account_type_idx on public.accounts (account_type);

-- ---------------------------------------------------------------------------
-- journal_entries / journal_lines — double-entry; void via reversing entry,
-- never by editing posted lines in place.
-- ---------------------------------------------------------------------------
create table public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  entry_date date not null default (timezone('utc', now()))::date,
  status public.doc_status not null default 'posted',
  memo text,
  -- Optional link back to the operational document that produced this entry.
  source_type text,
  source_id uuid,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id)
);

create index journal_entries_status_idx on public.journal_entries (status);
create index journal_entries_entry_date_idx on public.journal_entries (entry_date);
create index journal_entries_source_idx on public.journal_entries (source_type, source_id);

create table public.journal_lines (
  id uuid primary key default gen_random_uuid(),
  journal_entry_id uuid not null references public.journal_entries (id),
  account_id uuid not null references public.accounts (id),
  debit numeric(14, 2) not null default 0 check (debit >= 0),
  credit numeric(14, 2) not null default 0 check (credit >= 0),
  memo text,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id),
  -- Debit XOR credit: exactly one side non-zero (classic GL line shape).
  constraint journal_lines_debit_xor_credit check (
    (debit > 0 and credit = 0) or (credit > 0 and debit = 0)
  )
);

create index journal_lines_journal_entry_id_idx on public.journal_lines (journal_entry_id);
create index journal_lines_account_id_idx on public.journal_lines (account_id);

-- Deferred so multi-line inserts in one transaction can unbalance mid-way;
-- balance is enforced at COMMIT.
create or replace function public.enforce_journal_balanced()
returns trigger
language plpgsql
as $$
declare
  entry_id uuid;
  imbalance numeric(14, 2);
begin
  entry_id := coalesce(new.journal_entry_id, old.journal_entry_id);

  select coalesce(sum(debit), 0) - coalesce(sum(credit), 0)
  into imbalance
  from public.journal_lines
  where journal_entry_id = entry_id;

  if imbalance <> 0 then
    raise exception
      'journal entry % is unbalanced (debit − credit = %)',
      entry_id, imbalance;
  end if;

  return null;
end;
$$;

create constraint trigger journal_lines_balanced
  after insert or update or delete on public.journal_lines
  deferrable initially deferred
  for each row
  execute function public.enforce_journal_balanced();

-- ---------------------------------------------------------------------------
-- payments — cash/bank movements linked to a party; GL posting via RPC later.
-- ---------------------------------------------------------------------------
create table public.payments (
  id uuid primary key default gen_random_uuid(),
  kind public.payment_kind not null,
  party_id uuid not null references public.parties (id),
  -- Which cash/bank COA account received or paid the money.
  account_id uuid not null references public.accounts (id),
  amount numeric(14, 2) not null check (amount > 0),
  status public.doc_status not null default 'posted',
  payment_date date not null default (timezone('utc', now()))::date,
  -- Optional link to a sale (receipt) or purchase (disbursement).
  source_type text,
  source_id uuid,
  reference text,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles (id)
);

create index payments_party_id_idx on public.payments (party_id);
create index payments_account_id_idx on public.payments (account_id);
create index payments_status_idx on public.payments (status);
create index payments_payment_date_idx on public.payments (payment_date);
create index payments_source_idx on public.payments (source_type, source_id);

-- ---------------------------------------------------------------------------
-- Seed chart of accounts (stable codes used by posting RPCs)
-- ---------------------------------------------------------------------------
insert into public.accounts (code, name, account_type) values
  ('1010', 'Cash', 'asset'),
  ('1020', 'Bank', 'asset'),
  ('1100', 'Receivable', 'asset'),
  ('1200', 'Inventory', 'asset'),
  ('2100', 'Payable', 'liability'),
  ('3000', 'Equity', 'equity'),
  ('4000', 'Sales Revenue', 'revenue'),
  ('5000', 'COGS', 'expense');

-- ---------------------------------------------------------------------------
-- RLS — every table; clients never write stock/journal (SECURITY DEFINER RPCs).
-- Admin bypasses via has_role('admin') inside has_role() for each required role.
-- ---------------------------------------------------------------------------
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

-- profiles: users read own row; admins manage all
create policy profiles_select_own_or_admin on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.has_role('admin'));

create policy profiles_update_admin on public.profiles
  for update to authenticated
  using (public.has_role('admin'))
  with check (public.has_role('admin'));

-- Master data: authenticated read; role-gated insert/update (no DELETE — deactivate).
create policy products_select on public.products
  for select to authenticated using (true);
create policy products_insert on public.products
  for insert to authenticated
  with check (public.has_role('purchase'));
create policy products_update on public.products
  for update to authenticated
  using (public.has_role('purchase'))
  with check (public.has_role('purchase'));

create policy parties_select on public.parties
  for select to authenticated using (true);
create policy parties_insert on public.parties
  for insert to authenticated
  with check (
    public.has_role('sales')
    or public.has_role('purchase')
    or public.has_role('accountant')
  );
create policy parties_update on public.parties
  for update to authenticated
  using (
    public.has_role('sales')
    or public.has_role('purchase')
    or public.has_role('accountant')
  )
  with check (
    public.has_role('sales')
    or public.has_role('purchase')
    or public.has_role('accountant')
  );

create policy accounts_select on public.accounts
  for select to authenticated using (true);
create policy accounts_insert on public.accounts
  for insert to authenticated
  with check (public.has_role('admin'));
create policy accounts_update on public.accounts
  for update to authenticated
  using (public.has_role('admin'))
  with check (public.has_role('admin'));


-- Operational docs: read for authenticated; insert/update by module role.
-- No DELETE policies — void instead of delete for posted documents.
create policy purchases_select on public.purchases
  for select to authenticated using (true);
create policy purchases_insert on public.purchases
  for insert to authenticated
  with check (public.has_role('purchase'));
create policy purchases_update on public.purchases
  for update to authenticated
  using (public.has_role('purchase'))
  with check (public.has_role('purchase'));

create policy purchase_items_select on public.purchase_items
  for select to authenticated using (true);
create policy purchase_items_insert on public.purchase_items
  for insert to authenticated
  with check (public.has_role('purchase'));
create policy purchase_items_update on public.purchase_items
  for update to authenticated
  using (public.has_role('purchase'))
  with check (public.has_role('purchase'));

create policy sales_select on public.sales
  for select to authenticated using (true);
create policy sales_insert on public.sales
  for insert to authenticated
  with check (public.has_role('sales'));
create policy sales_update on public.sales
  for update to authenticated
  using (public.has_role('sales'))
  with check (public.has_role('sales'));

create policy sale_items_select on public.sale_items
  for select to authenticated using (true);
create policy sale_items_insert on public.sale_items
  for insert to authenticated
  with check (public.has_role('sales'));
create policy sale_items_update on public.sale_items
  for update to authenticated
  using (public.has_role('sales'))
  with check (public.has_role('sales'));

create policy payments_select on public.payments
  for select to authenticated using (true);
create policy payments_insert on public.payments
  for insert to authenticated
  with check (public.has_role('accountant'));
create policy payments_update on public.payments
  for update to authenticated
  using (public.has_role('accountant'))
  with check (public.has_role('accountant'));

-- Ledger tables: SELECT only for clients; writers are RPCs (service/definer).
create policy stock_movements_select on public.stock_movements
  for select to authenticated using (true);

create policy journal_entries_select on public.journal_entries
  for select to authenticated using (true);

create policy journal_lines_select on public.journal_lines
  for select to authenticated using (true);

-- Harden append-only / RPC-only tables at the privilege layer too.
revoke insert, update, delete on public.stock_movements from authenticated, anon;
revoke insert, update, delete on public.journal_entries from authenticated, anon;
revoke insert, update, delete on public.journal_lines from authenticated, anon;
