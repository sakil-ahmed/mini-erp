-- Mini ERP full bootstrap (migrations 0001-0010 including seed)
-- Paste into Supabase Dashboard → SQL Editor → Run
-- Regenerated 2026-11-22T13:59Z — profiles before has_role


-- ############################################################################
-- FILE: supabase/migrations/0001_schema.sql
-- ############################################################################

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


-- ############################################################################
-- FILE: supabase/migrations/0002_purchase.sql
-- ############################################################################

-- =============================================================================
-- 0002_purchase.sql — create_purchase RPC
-- Posts a purchase in one transaction: lines, stock in, moving avg, balanced GL.
-- Clients never touch stock_movements / journal_*; this SECURITY DEFINER RPC does.
-- =============================================================================

-- Persist discount / cash paid on the header (inputs are not only GL-side).
alter table public.purchases
  add column if not exists discount numeric(14, 2) not null default 0
    check (discount >= 0),
  add column if not exists amount_paid numeric(14, 2) not null default 0
    check (amount_paid >= 0);

alter table public.purchases
  drop constraint if exists purchases_paid_lte_total;

alter table public.purchases
  add constraint purchases_paid_lte_total
  check (amount_paid <= total);

-- Overload: allow has_role(array['admin','purchase']) style checks.
create or replace function public.has_role(required public.app_role[])
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
      and p.role = any (required)
  );
$$;

comment on function public.has_role(public.app_role[]) is
  'True if current user role is any of the given roles.';

-- ---------------------------------------------------------------------------
-- create_purchase
-- p_items JSON: [{"product_id":"<uuid>","qty":1,"unit_cost":10.00}, ...]
-- ---------------------------------------------------------------------------
create or replace function public.create_purchase(
  p_supplier uuid,
  p_date date,
  p_items jsonb,
  p_discount numeric,
  p_paid numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_purchase_id uuid;
  v_journal_id uuid;
  v_subtotal numeric(14, 2) := 0;
  v_total numeric(14, 2);
  v_discount numeric(14, 2);
  v_paid numeric(14, 2);
  v_payable numeric(14, 2);
  v_item jsonb;
  v_product_id uuid;
  v_qty numeric(14, 3);
  v_unit_cost numeric(14, 2);
  v_line_total numeric(14, 2);
  v_old_qty numeric(14, 3);
  v_old_avg numeric(14, 2);
  v_new_qty numeric(14, 3);
  v_new_avg numeric(14, 2);
  v_inv_account uuid;
  v_cash_account uuid;
  v_payable_account uuid;
  v_supplier_ok boolean;
begin
  -- Role gate first (fail closed before any writes).
  if not public.has_role(array['admin', 'purchase']::public.app_role[]) then
    raise exception 'permission denied: requires admin or purchase role';
  end if;

  if v_user is null then
    raise exception 'not authenticated';
  end if;

  if p_supplier is null then
    raise exception 'supplier is required';
  end if;

  if p_date is null then
    raise exception 'purchase date is required';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'p_items must be a non-empty JSON array';
  end if;

  v_discount := coalesce(p_discount, 0);
  v_paid := coalesce(p_paid, 0);

  if v_discount < 0 then
    raise exception 'discount must be >= 0 (got %)', v_discount;
  end if;

  if v_paid < 0 then
    raise exception 'paid amount must be >= 0 (got %)', v_paid;
  end if;

  select exists (
    select 1
    from public.parties
    where id = p_supplier
      and kind = 'supplier'
      and is_active
  ) into v_supplier_ok;

  if not v_supplier_ok then
    raise exception 'supplier % not found or not an active supplier', p_supplier;
  end if;

  select id into v_inv_account from public.accounts where code = '1200';
  select id into v_cash_account from public.accounts where code = '1010';
  select id into v_payable_account from public.accounts where code = '2100';

  if v_inv_account is null or v_cash_account is null or v_payable_account is null then
    raise exception 'chart of accounts missing 1200/1010/2100 — run 0001_schema seed';
  end if;

  -- First pass: validate lines and compute subtotal (no mutations yet).
  for v_item in select value from jsonb_array_elements(p_items)
  loop
    if v_item ->> 'product_id' is null then
      raise exception 'each item requires product_id';
    end if;

    v_product_id := (v_item ->> 'product_id')::uuid;
    v_qty := (v_item ->> 'qty')::numeric(14, 3);
    v_unit_cost := (v_item ->> 'unit_cost')::numeric(14, 2);

    if v_qty is null or v_qty <= 0 then
      raise exception 'item qty must be > 0 (product %, qty %)', v_product_id, v_qty;
    end if;

    if v_unit_cost is null or v_unit_cost < 0 then
      raise exception 'item unit_cost must be >= 0 (product %, cost %)', v_product_id, v_unit_cost;
    end if;

    if not exists (
      select 1 from public.products where id = v_product_id and is_active
    ) then
      raise exception 'product % not found or inactive', v_product_id;
    end if;

    v_line_total := round(v_qty * v_unit_cost, 2);
    v_subtotal := v_subtotal + v_line_total;
  end loop;

  if v_discount > v_subtotal then
    raise exception 'discount (%) cannot exceed subtotal (%)', v_discount, v_subtotal;
  end if;

  v_total := round(v_subtotal - v_discount, 2);

  if v_total <= 0 then
    raise exception 'purchase total must be > 0 after discount (subtotal %, discount %)',
      v_subtotal, v_discount;
  end if;

  if v_paid > v_total then
    raise exception 'paid (%) cannot exceed total (%)', v_paid, v_total;
  end if;

  v_payable := round(v_total - v_paid, 2);

  -- Header
  insert into public.purchases (
    supplier_id,
    doc_date,
    subtotal,
    discount,
    total,
    amount_paid,
    status,
    created_by
  )
  values (
    p_supplier,
    p_date,
    v_subtotal,
    v_discount,
    v_total,
    v_paid,
    'posted',
    v_user
  )
  returning id into v_purchase_id;

  -- Lines + stock + moving average (row lock per product).
  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item ->> 'product_id')::uuid;
    v_qty := (v_item ->> 'qty')::numeric(14, 3);
    v_unit_cost := (v_item ->> 'unit_cost')::numeric(14, 2);
    v_line_total := round(v_qty * v_unit_cost, 2);

    insert into public.purchase_items (
      purchase_id,
      product_id,
      qty,
      unit_cost,
      line_total,
      created_by
    )
    values (
      v_purchase_id,
      v_product_id,
      v_qty,
      v_unit_cost,
      v_line_total,
      v_user
    );

    select stock_qty, avg_cost
    into v_old_qty, v_old_avg
    from public.products
    where id = v_product_id
    for update;

    v_new_qty := v_old_qty + v_qty;

    -- Moving average: (old_qty*old_avg + qty*unit_cost) / (old_qty+qty).
    if v_old_qty = 0 then
      v_new_avg := round(v_unit_cost, 2);
    else
      v_new_avg := round(
        (v_old_qty * v_old_avg + v_qty * v_unit_cost) / v_new_qty,
        2
      );
    end if;

    update public.products
    set
      stock_qty = v_new_qty,
      avg_cost = v_new_avg
    where id = v_product_id;

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
      v_product_id,
      'purchase',
      v_qty, -- positive = stock in
      'purchase',
      v_purchase_id,
      'Purchase receipt',
      v_user
    );
  end loop;

  -- Balanced journal: Dr Inventory total; Cr Cash paid; Cr Payable remainder.
  insert into public.journal_entries (
    entry_date,
    status,
    memo,
    source_type,
    source_id,
    created_by
  )
  values (
    p_date,
    'posted',
    'Purchase ' || v_purchase_id::text,
    'purchase',
    v_purchase_id,
    v_user
  )
  returning id into v_journal_id;

  insert into public.journal_lines (
    journal_entry_id,
    account_id,
    debit,
    credit,
    created_by
  )
  values (
    v_journal_id,
    v_inv_account,
    v_total,
    0,
    v_user
  );

  if v_paid > 0 then
    insert into public.journal_lines (
      journal_entry_id,
      account_id,
      debit,
      credit,
      created_by
    )
    values (
      v_journal_id,
      v_cash_account,
      0,
      v_paid,
      v_user
    );
  end if;

  if v_payable > 0 then
    insert into public.journal_lines (
      journal_entry_id,
      account_id,
      debit,
      credit,
      created_by
    )
    values (
      v_journal_id,
      v_payable_account,
      0,
      v_payable,
      v_user
    );
  end if;

  -- Optional cash payment row when money left the till (same tx).
  if v_paid > 0 then
    insert into public.payments (
      kind,
      party_id,
      account_id,
      amount,
      status,
      payment_date,
      source_type,
      source_id,
      created_by
    )
    values (
      'disbursement',
      p_supplier,
      v_cash_account,
      v_paid,
      'posted',
      p_date,
      'purchase',
      v_purchase_id,
      v_user
    );
  end if;

  return v_purchase_id;
end;
$$;

comment on function public.create_purchase(uuid, date, jsonb, numeric, numeric) is
  'Post a purchase: items, stock in, moving avg_cost, Dr Inventory / Cr Cash+Payable.';

revoke all on function public.create_purchase(uuid, date, jsonb, numeric, numeric)
  from public, anon;

grant execute on function public.create_purchase(uuid, date, jsonb, numeric, numeric)
  to authenticated;


-- ############################################################################
-- FILE: supabase/migrations/0003_sale.sql
-- ############################################################################

-- =============================================================================
-- 0003_sale.sql — create_sale RPC
-- Posts a sale in one transaction: lines (cost snapshot), stock out, balanced GL.
-- Clients never touch stock_movements / journal_*; this SECURITY DEFINER RPC does.
-- =============================================================================

-- Persist discount / cash received on the header (mirrors purchases).
alter table public.sales
  add column if not exists discount numeric(14, 2) not null default 0
    check (discount >= 0),
  add column if not exists amount_paid numeric(14, 2) not null default 0
    check (amount_paid >= 0);

alter table public.sales
  drop constraint if exists sales_paid_lte_total;

alter table public.sales
  add constraint sales_paid_lte_total
  check (amount_paid <= total);

-- ---------------------------------------------------------------------------
-- create_sale
-- p_items JSON: [{"product_id":"<uuid>","qty":1,"unit_price":12.00}, ...]
-- unit_cost is NOT accepted from the client — snapshotted from products.avg_cost.
-- ---------------------------------------------------------------------------
create or replace function public.create_sale(
  p_customer uuid,
  p_date date,
  p_items jsonb,
  p_discount numeric,
  p_paid numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_sale_id uuid;
  v_journal_id uuid;
  v_subtotal numeric(14, 2) := 0;
  v_total numeric(14, 2);
  v_discount numeric(14, 2);
  v_paid numeric(14, 2);
  v_receivable numeric(14, 2);
  v_cogs_total numeric(14, 2) := 0;
  v_item jsonb;
  v_product_id uuid;
  v_qty numeric(14, 3);
  v_unit_price numeric(14, 2);
  v_unit_cost numeric(14, 2);
  v_line_total numeric(14, 2);
  v_line_cogs numeric(14, 2);
  v_old_qty numeric(14, 3);
  v_old_avg numeric(14, 2);
  v_new_qty numeric(14, 3);
  v_cash_account uuid;
  v_ar_account uuid;
  v_revenue_account uuid;
  v_cogs_account uuid;
  v_inv_account uuid;
  v_customer_ok boolean;
begin
  if not public.has_role(array['admin', 'sales']::public.app_role[]) then
    raise exception 'permission denied: requires admin or sales role';
  end if;

  if v_user is null then
    raise exception 'not authenticated';
  end if;

  if p_customer is null then
    raise exception 'customer is required';
  end if;

  if p_date is null then
    raise exception 'sale date is required';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'p_items must be a non-empty JSON array';
  end if;

  v_discount := coalesce(p_discount, 0);
  v_paid := coalesce(p_paid, 0);

  if v_discount < 0 then
    raise exception 'discount must be >= 0 (got %)', v_discount;
  end if;

  if v_paid < 0 then
    raise exception 'paid amount must be >= 0 (got %)', v_paid;
  end if;

  select exists (
    select 1
    from public.parties
    where id = p_customer
      and kind = 'customer'
      and is_active
  ) into v_customer_ok;

  if not v_customer_ok then
    raise exception 'customer % not found or not an active customer', p_customer;
  end if;

  select id into v_cash_account from public.accounts where code = '1010';
  select id into v_ar_account from public.accounts where code = '1100';
  select id into v_revenue_account from public.accounts where code = '4000';
  select id into v_cogs_account from public.accounts where code = '5000';
  select id into v_inv_account from public.accounts where code = '1200';

  if v_cash_account is null
     or v_ar_account is null
     or v_revenue_account is null
     or v_cogs_account is null
     or v_inv_account is null then
    raise exception 'chart of accounts missing 1010/1100/4000/5000/1200 — run 0001_schema seed';
  end if;

  -- Validate lines + prices (stock checked under row lock below).
  for v_item in select value from jsonb_array_elements(p_items)
  loop
    if v_item ->> 'product_id' is null then
      raise exception 'each item requires product_id';
    end if;

    v_product_id := (v_item ->> 'product_id')::uuid;
    v_qty := (v_item ->> 'qty')::numeric(14, 3);
    v_unit_price := (v_item ->> 'unit_price')::numeric(14, 2);

    if v_qty is null or v_qty <= 0 then
      raise exception 'item qty must be > 0 (product %, qty %)', v_product_id, v_qty;
    end if;

    if v_unit_price is null or v_unit_price < 0 then
      raise exception 'item unit_price must be >= 0 (product %, price %)',
        v_product_id, v_unit_price;
    end if;

    if not exists (
      select 1 from public.products where id = v_product_id and is_active
    ) then
      raise exception 'product % not found or inactive', v_product_id;
    end if;

    v_line_total := round(v_qty * v_unit_price, 2);
    v_subtotal := v_subtotal + v_line_total;
  end loop;

  if v_discount > v_subtotal then
    raise exception 'discount (%) cannot exceed subtotal (%)', v_discount, v_subtotal;
  end if;

  v_total := round(v_subtotal - v_discount, 2);

  if v_total <= 0 then
    raise exception 'sale total must be > 0 after discount (subtotal %, discount %)',
      v_subtotal, v_discount;
  end if;

  if v_paid > v_total then
    raise exception 'paid (%) cannot exceed total (%)', v_paid, v_total;
  end if;

  v_receivable := round(v_total - v_paid, 2);

  insert into public.sales (
    customer_id,
    doc_date,
    subtotal,
    discount,
    total,
    amount_paid,
    status,
    created_by
  )
  values (
    p_customer,
    p_date,
    v_subtotal,
    v_discount,
    v_total,
    v_paid,
    'posted',
    v_user
  )
  returning id into v_sale_id;

  -- Lock → reject oversell → snapshot cost → stock out.
  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item ->> 'product_id')::uuid;
    v_qty := (v_item ->> 'qty')::numeric(14, 3);
    v_unit_price := (v_item ->> 'unit_price')::numeric(14, 2);
    v_line_total := round(v_qty * v_unit_price, 2);

    select stock_qty, avg_cost
    into v_old_qty, v_old_avg
    from public.products
    where id = v_product_id
    for update;

    if v_old_qty < v_qty then
      raise exception
        'insufficient stock for product % (available %, requested %)',
        v_product_id, v_old_qty, v_qty;
    end if;

    -- Snapshot avg_cost at post time (COGS basis; product avg_cost unchanged).
    v_unit_cost := v_old_avg;
    v_line_cogs := round(v_qty * v_unit_cost, 2);
    v_cogs_total := v_cogs_total + v_line_cogs;
    v_new_qty := v_old_qty - v_qty;

    insert into public.sale_items (
      sale_id,
      product_id,
      qty,
      unit_price,
      unit_cost,
      line_total,
      created_by
    )
    values (
      v_sale_id,
      v_product_id,
      v_qty,
      v_unit_price,
      v_unit_cost,
      v_line_total,
      v_user
    );

    update public.products
    set stock_qty = v_new_qty
    where id = v_product_id;

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
      v_product_id,
      'sale',
      -v_qty, -- negative = stock out
      'sale',
      v_sale_id,
      'Sale issue',
      v_user
    );
  end loop;

  -- Single balanced journal:
  --   Dr Cash (paid) + Dr Receivable (due) + Dr COGS
  --   Cr Sales Revenue (total) + Cr Inventory (COGS)
  insert into public.journal_entries (
    entry_date,
    status,
    memo,
    source_type,
    source_id,
    created_by
  )
  values (
    p_date,
    'posted',
    'Sale ' || v_sale_id::text,
    'sale',
    v_sale_id,
    v_user
  )
  returning id into v_journal_id;

  if v_paid > 0 then
    insert into public.journal_lines (
      journal_entry_id, account_id, debit, credit, created_by
    )
    values (v_journal_id, v_cash_account, v_paid, 0, v_user);
  end if;

  if v_receivable > 0 then
    insert into public.journal_lines (
      journal_entry_id, account_id, debit, credit, created_by
    )
    values (v_journal_id, v_ar_account, v_receivable, 0, v_user);
  end if;

  insert into public.journal_lines (
    journal_entry_id, account_id, debit, credit, created_by
  )
  values (v_journal_id, v_revenue_account, 0, v_total, v_user);

  -- COGS leg (skip if zero-cost inventory — XOR forbids 0/0 lines).
  if v_cogs_total > 0 then
    insert into public.journal_lines (
      journal_entry_id, account_id, debit, credit, created_by
    )
    values (v_journal_id, v_cogs_account, v_cogs_total, 0, v_user);

    insert into public.journal_lines (
      journal_entry_id, account_id, debit, credit, created_by
    )
    values (v_journal_id, v_inv_account, 0, v_cogs_total, v_user);
  end if;

  if v_paid > 0 then
    insert into public.payments (
      kind,
      party_id,
      account_id,
      amount,
      status,
      payment_date,
      source_type,
      source_id,
      created_by
    )
    values (
      'receipt',
      p_customer,
      v_cash_account,
      v_paid,
      'posted',
      p_date,
      'sale',
      v_sale_id,
      v_user
    );
  end if;

  return v_sale_id;
end;
$$;

comment on function public.create_sale(uuid, date, jsonb, numeric, numeric) is
  'Post a sale: cost snapshot, stock out, Dr Cash+AR+COGS / Cr Revenue+Inventory.';

revoke all on function public.create_sale(uuid, date, jsonb, numeric, numeric)
  from public, anon;

grant execute on function public.create_sale(uuid, date, jsonb, numeric, numeric)
  to authenticated;


-- ############################################################################
-- FILE: supabase/migrations/0004_void_payments.sql
-- ############################################################################

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


-- ############################################################################
-- FILE: supabase/migrations/0005_rls.sql
-- ############################################################################

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


-- ############################################################################
-- FILE: supabase/migrations/0006_seed.sql
-- ############################################################################

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


-- ############################################################################
-- FILE: supabase/migrations/0007_inventory_read.sql
-- ############################################################################

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


-- ############################################################################
-- FILE: supabase/migrations/0008_accounts_reports.sql
-- ############################################################################

-- =============================================================================
-- 0008_accounts_reports.sql — accounting views / RPCs for the Accounts module
-- Reports run in SQL (not heavy client aggregation). Invoker rights → RLS applies.
-- Only posted journal_entries are included (void originals excluded; reversals net out).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Trial Balance as-of date
-- ---------------------------------------------------------------------------
create or replace function public.get_trial_balance(p_as_of date default (timezone('utc', now()))::date)
returns table (
  account_id uuid,
  code text,
  name text,
  account_type public.account_type,
  total_debit numeric(14, 2),
  total_credit numeric(14, 2),
  balance numeric(14, 2)
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    a.id as account_id,
    a.code,
    a.name,
    a.account_type,
    coalesce(sum(x.debit), 0)::numeric(14, 2) as total_debit,
    coalesce(sum(x.credit), 0)::numeric(14, 2) as total_credit,
    (coalesce(sum(x.debit), 0) - coalesce(sum(x.credit), 0))::numeric(14, 2) as balance
  from public.accounts a
  left join (
    select jl.account_id, jl.debit, jl.credit
    from public.journal_lines jl
    join public.journal_entries je on je.id = jl.journal_entry_id
    where je.status = 'posted'
      and je.entry_date <= p_as_of
  ) x on x.account_id = a.id
  where a.is_active
  group by a.id, a.code, a.name, a.account_type
  having coalesce(sum(x.debit), 0) <> 0 or coalesce(sum(x.credit), 0) <> 0
  order by a.code;
$$;

create or replace function public.get_trial_balance_totals(
  p_as_of date default (timezone('utc', now()))::date
)
returns table (
  total_debit numeric(14, 2),
  total_credit numeric(14, 2),
  difference numeric(14, 2),
  is_balanced boolean
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    coalesce(sum(tb.total_debit), 0)::numeric(14, 2),
    coalesce(sum(tb.total_credit), 0)::numeric(14, 2),
    (coalesce(sum(tb.total_debit), 0) - coalesce(sum(tb.total_credit), 0))::numeric(14, 2),
    coalesce(sum(tb.total_debit), 0) = coalesce(sum(tb.total_credit), 0)
  from public.get_trial_balance(p_as_of) tb;
$$;

-- ---------------------------------------------------------------------------
-- Account ledger with running balance (debit − credit cumulative)
-- ---------------------------------------------------------------------------
create or replace function public.get_account_ledger(
  p_account_id uuid,
  p_from date default null,
  p_to date default null
)
returns table (
  line_id uuid,
  entry_id uuid,
  entry_date date,
  memo text,
  source_type text,
  source_id uuid,
  debit numeric(14, 2),
  credit numeric(14, 2),
  running_balance numeric(14, 2)
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    jl.id as line_id,
    je.id as entry_id,
    je.entry_date,
    coalesce(jl.memo, je.memo) as memo,
    je.source_type,
    je.source_id,
    jl.debit,
    jl.credit,
    sum(jl.debit - jl.credit) over (
      order by je.entry_date, je.created_at, jl.created_at, jl.id
      rows between unbounded preceding and current row
    )::numeric(14, 2) as running_balance
  from public.journal_lines jl
  join public.journal_entries je on je.id = jl.journal_entry_id
  where jl.account_id = p_account_id
    and je.status = 'posted'
    and (p_from is null or je.entry_date >= p_from)
    and (p_to is null or je.entry_date <= p_to)
  order by je.entry_date, je.created_at, jl.created_at, jl.id;
$$;

-- ---------------------------------------------------------------------------
-- Profit & Loss for a date range
-- ---------------------------------------------------------------------------
create or replace function public.get_profit_and_loss(
  p_from date default date_trunc('year', timezone('utc', now()))::date,
  p_to date default (timezone('utc', now()))::date
)
returns table (
  section text,
  account_id uuid,
  code text,
  name text,
  amount numeric(14, 2)
)
language sql
stable
security invoker
set search_path = public
as $$
  with posted as (
    select
      a.id as account_id,
      a.code,
      a.name,
      a.account_type,
      coalesce(sum(jl.debit), 0) as debits,
      coalesce(sum(jl.credit), 0) as credits
    from public.accounts a
    join public.journal_lines jl on jl.account_id = a.id
    join public.journal_entries je on je.id = jl.journal_entry_id
    where je.status = 'posted'
      and je.entry_date >= p_from
      and je.entry_date <= p_to
      and a.account_type in ('revenue', 'expense')
    group by a.id, a.code, a.name, a.account_type
  )
  select
    'revenue'::text as section,
    p.account_id,
    p.code,
    p.name,
    (p.credits - p.debits)::numeric(14, 2) as amount
  from posted p
  where p.account_type = 'revenue'
    and (p.credits - p.debits) <> 0

  union all

  select
    'expense'::text,
    p.account_id,
    p.code,
    p.name,
    (p.debits - p.credits)::numeric(14, 2) as amount
  from posted p
  where p.account_type = 'expense'
    and (p.debits - p.credits) <> 0

  order by 1, 3;
$$;

create or replace function public.get_profit_and_loss_summary(
  p_from date default date_trunc('year', timezone('utc', now()))::date,
  p_to date default (timezone('utc', now()))::date
)
returns table (
  total_revenue numeric(14, 2),
  total_expense numeric(14, 2),
  net_profit numeric(14, 2)
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    coalesce(sum(case when section = 'revenue' then amount else 0 end), 0)::numeric(14, 2),
    coalesce(sum(case when section = 'expense' then amount else 0 end), 0)::numeric(14, 2),
    (
      coalesce(sum(case when section = 'revenue' then amount else 0 end), 0)
      - coalesce(sum(case when section = 'expense' then amount else 0 end), 0)
    )::numeric(14, 2)
  from public.get_profit_and_loss(p_from, p_to);
$$;

-- ---------------------------------------------------------------------------
-- Receivables / Payables by party (from open operational docs)
-- ---------------------------------------------------------------------------
create or replace view public.v_party_receivables
with (security_invoker = true)
as
select
  p.id as party_id,
  p.name as party_name,
  p.email,
  count(*)::integer as open_docs,
  sum(s.total - s.amount_paid)::numeric(14, 2) as balance
from public.sales s
join public.parties p on p.id = s.customer_id
where s.status = 'posted'
  and s.amount_paid < s.total
group by p.id, p.name, p.email;

create or replace view public.v_party_payables
with (security_invoker = true)
as
select
  p.id as party_id,
  p.name as party_name,
  p.email,
  count(*)::integer as open_docs,
  sum(pu.total - pu.amount_paid)::numeric(14, 2) as balance
from public.purchases pu
join public.parties p on p.id = pu.supplier_id
where pu.status = 'posted'
  and pu.amount_paid < pu.total
group by p.id, p.name, p.email;

grant select on public.v_party_receivables to authenticated;
grant select on public.v_party_payables to authenticated;

grant execute on function public.get_trial_balance(date) to authenticated;
grant execute on function public.get_trial_balance_totals(date) to authenticated;
grant execute on function public.get_account_ledger(uuid, date, date) to authenticated;
grant execute on function public.get_profit_and_loss(date, date) to authenticated;
grant execute on function public.get_profit_and_loss_summary(date, date) to authenticated;


-- ############################################################################
-- FILE: supabase/migrations/0009_dashboard.sql
-- ############################################################################

-- =============================================================================
-- 0009_dashboard.sql — KPI + chart views for the dashboard
-- security_invoker so underlying RLS shapes what each role can aggregate.
-- =============================================================================

create or replace view public.v_dashboard_kpis
with (security_invoker = true)
as
select
  (
    select coalesce(sum(s.total), 0)::numeric(14, 2)
    from public.sales s
    where s.status = 'posted'
      and s.doc_date = (timezone('utc', now()))::date
  ) as today_sales,
  (
    select coalesce(sum(s.total), 0)::numeric(14, 2)
    from public.sales s
    where s.status = 'posted'
      and s.doc_date >= date_trunc('month', timezone('utc', now()))::date
  ) as month_sales,
  (
    select coalesce(sum(p.total), 0)::numeric(14, 2)
    from public.purchases p
    where p.status = 'posted'
      and p.doc_date >= date_trunc('month', timezone('utc', now()))::date
  ) as month_purchases,
  (
    select coalesce(sum(pr.stock_qty * pr.avg_cost), 0)::numeric(14, 2)
    from public.products pr
    where pr.is_active
  ) as stock_value,
  (
    select coalesce(sum(r.balance), 0)::numeric(14, 2)
    from public.v_party_receivables r
  ) as receivable,
  (
    select coalesce(sum(pay.balance), 0)::numeric(14, 2)
    from public.v_party_payables pay
  ) as payable,
  (
    select count(*)::integer
    from public.products pr
    where pr.is_active
      and pr.is_low
  ) as low_stock_count;

create or replace view public.v_dashboard_daily_30d
with (security_invoker = true)
as
with days as (
  select generate_series(
    (timezone('utc', now()))::date - 29,
    (timezone('utc', now()))::date,
    interval '1 day'
  )::date as day
),
sales_by_day as (
  select s.doc_date as day, sum(s.total)::numeric(14, 2) as sales_total
  from public.sales s
  where s.status = 'posted'
    and s.doc_date >= (timezone('utc', now()))::date - 29
  group by s.doc_date
),
purchases_by_day as (
  select p.doc_date as day, sum(p.total)::numeric(14, 2) as purchase_total
  from public.purchases p
  where p.status = 'posted'
    and p.doc_date >= (timezone('utc', now()))::date - 29
  group by p.doc_date
)
select
  d.day,
  coalesce(s.sales_total, 0)::numeric(14, 2) as sales_total,
  coalesce(p.purchase_total, 0)::numeric(14, 2) as purchase_total
from days d
left join sales_by_day s on s.day = d.day
left join purchases_by_day p on p.day = d.day
order by d.day;

create or replace view public.v_dashboard_top_products
with (security_invoker = true)
as
select
  pr.id as product_id,
  pr.sku,
  pr.name,
  coalesce(sum(si.qty), 0)::numeric(14, 3) as qty_sold,
  coalesce(sum(si.line_total), 0)::numeric(14, 2) as revenue
from public.sale_items si
join public.sales s on s.id = si.sale_id
join public.products pr on pr.id = si.product_id
where s.status = 'posted'
  and s.doc_date >= (timezone('utc', now()))::date - 29
group by pr.id, pr.sku, pr.name
order by revenue desc
limit 5;

grant select on public.v_dashboard_kpis to authenticated;
grant select on public.v_dashboard_daily_30d to authenticated;
grant select on public.v_dashboard_top_products to authenticated;


-- ############################################################################
-- FILE: supabase/migrations/0010_integrity_fixes.sql
-- ############################################################################

-- =============================================================================
-- 0010_integrity_fixes.sql
-- Top integrity fixes from CTO review:
--   1) record_payment: one payment+journal per doc (void-safe); lock before sum
--   2) create_purchase: net inv_amount so avg_cost matches Inventory GL
--   3) Guard products.stock_qty/avg_cost; lock products in uuid order
-- =============================================================================

-- ---------------------------------------------------------------------------
-- purchase_items.inv_amount — inventory valuation credited to the line (net
-- of header discount). unit_cost/line_total stay commercial (gross).
-- ---------------------------------------------------------------------------
alter table public.purchase_items
  add column if not exists inv_amount numeric(14, 2);

update public.purchase_items pi
set inv_amount = case
  when p.subtotal = 0 then 0
  else round(pi.line_total * (p.total / p.subtotal), 2)
end
from public.purchases p
where p.id = pi.purchase_id
  and pi.inv_amount is null;

-- Penny-fix: push remainder of (total − sum(inv_amount)) onto the last line.
with sums as (
  select
    pi.purchase_id,
    p.total,
    sum(pi.inv_amount) as inv_sum,
    (
      select pi2.id
      from public.purchase_items pi2
      where pi2.purchase_id = pi.purchase_id
      order by pi2.product_id desc, pi2.id desc
      limit 1
    ) as last_id
  from public.purchase_items pi
  join public.purchases p on p.id = pi.purchase_id
  group by pi.purchase_id, p.total
)
update public.purchase_items pi
set inv_amount = pi.inv_amount + (s.total - s.inv_sum)
from sums s
where pi.id = s.last_id
  and s.total <> s.inv_sum;

alter table public.purchase_items
  alter column inv_amount set not null;

alter table public.purchase_items
  drop constraint if exists purchase_items_inv_amount_nonneg;

alter table public.purchase_items
  add constraint purchase_items_inv_amount_nonneg check (inv_amount >= 0);

-- ---------------------------------------------------------------------------
-- Block client/admin REST updates to stock_qty / avg_cost (RPC-only via GUC).
-- ---------------------------------------------------------------------------
create or replace function public.protect_product_valuation()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE'
     and (
       new.stock_qty is distinct from old.stock_qty
       or new.avg_cost is distinct from old.avg_cost
     )
     and coalesce(current_setting('app.allow_stock_mutation', true), '') <> '1'
  then
    raise exception
      'products.stock_qty/avg_cost are RPC-only; use create_purchase/create_sale/void_*';
  end if;
  return new;
end;
$$;

drop trigger if exists products_protect_valuation on public.products;
create trigger products_protect_valuation
  before update on public.products
  for each row
  execute function public.protect_product_valuation();

-- ---------------------------------------------------------------------------
-- create_purchase — ordered locks + net inv_amount into moving average
-- ---------------------------------------------------------------------------
create or replace function public.create_purchase(
  p_supplier uuid,
  p_date date,
  p_items jsonb,
  p_discount numeric,
  p_paid numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_purchase_id uuid;
  v_journal_id uuid;
  v_subtotal numeric(14, 2) := 0;
  v_total numeric(14, 2);
  v_discount numeric(14, 2);
  v_paid numeric(14, 2);
  v_payable numeric(14, 2);
  v_item jsonb;
  v_product_id uuid;
  v_qty numeric(14, 3);
  v_unit_cost numeric(14, 2);
  v_line_total numeric(14, 2);
  v_inv_amount numeric(14, 2);
  v_old_qty numeric(14, 3);
  v_old_avg numeric(14, 2);
  v_new_qty numeric(14, 3);
  v_new_avg numeric(14, 2);
  v_inv_account uuid;
  v_cash_account uuid;
  v_payable_account uuid;
  v_supplier_ok boolean;
  v_line_count integer := 0;
  v_line_idx integer := 0;
  v_discount_allocated numeric(14, 2) := 0;
  v_share numeric(14, 2);
begin
  if not public.has_role(array['admin', 'purchase']::public.app_role[]) then
    raise exception 'permission denied: requires admin or purchase role';
  end if;

  if v_user is null then
    raise exception 'not authenticated';
  end if;

  if p_supplier is null then
    raise exception 'supplier is required';
  end if;

  if p_date is null then
    raise exception 'purchase date is required';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'p_items must be a non-empty JSON array';
  end if;

  perform set_config('app.allow_stock_mutation', '1', true);

  v_discount := round(coalesce(p_discount, 0), 2);
  v_paid := round(coalesce(p_paid, 0), 2);

  if v_discount < 0 then
    raise exception 'discount must be >= 0 (got %)', v_discount;
  end if;

  if v_paid < 0 then
    raise exception 'paid amount must be >= 0 (got %)', v_paid;
  end if;

  select exists (
    select 1
    from public.parties
    where id = p_supplier
      and kind = 'supplier'
      and is_active
  ) into v_supplier_ok;

  if not v_supplier_ok then
    raise exception 'supplier % not found or not an active supplier', p_supplier;
  end if;

  select id into v_inv_account from public.accounts where code = '1200';
  select id into v_cash_account from public.accounts where code = '1010';
  select id into v_payable_account from public.accounts where code = '2100';

  if v_inv_account is null or v_cash_account is null or v_payable_account is null then
    raise exception 'chart of accounts missing 1200/1010/2100 — run 0001_schema seed';
  end if;

  for v_item in
    select value
    from jsonb_array_elements(p_items) as t(value)
    order by (t.value ->> 'product_id')::uuid
  loop
    if v_item ->> 'product_id' is null then
      raise exception 'each item requires product_id';
    end if;

    v_product_id := (v_item ->> 'product_id')::uuid;
    v_qty := (v_item ->> 'qty')::numeric(14, 3);
    v_unit_cost := (v_item ->> 'unit_cost')::numeric(14, 2);

    if v_qty is null or v_qty <= 0 then
      raise exception 'item qty must be > 0 (product %, qty %)', v_product_id, v_qty;
    end if;

    if v_unit_cost is null or v_unit_cost < 0 then
      raise exception 'item unit_cost must be >= 0 (product %, cost %)', v_product_id, v_unit_cost;
    end if;

    if not exists (
      select 1 from public.products where id = v_product_id and is_active
    ) then
      raise exception 'product % not found or inactive', v_product_id;
    end if;

    v_line_total := round(v_qty * v_unit_cost, 2);
    v_subtotal := v_subtotal + v_line_total;
    v_line_count := v_line_count + 1;
  end loop;

  if v_discount > v_subtotal then
    raise exception 'discount (%) cannot exceed subtotal (%)', v_discount, v_subtotal;
  end if;

  v_total := round(v_subtotal - v_discount, 2);

  if v_total <= 0 then
    raise exception 'purchase total must be > 0 after discount (subtotal %, discount %)',
      v_subtotal, v_discount;
  end if;

  if v_paid > v_total then
    raise exception 'paid (%) cannot exceed total (%)', v_paid, v_total;
  end if;

  v_payable := round(v_total - v_paid, 2);

  insert into public.purchases (
    supplier_id, doc_date, subtotal, discount, total, amount_paid, status, created_by
  )
  values (
    p_supplier, p_date, v_subtotal, v_discount, v_total, v_paid, 'posted', v_user
  )
  returning id into v_purchase_id;

  for v_item in
    select value
    from jsonb_array_elements(p_items) as t(value)
    order by (t.value ->> 'product_id')::uuid
  loop
    v_line_idx := v_line_idx + 1;
    v_product_id := (v_item ->> 'product_id')::uuid;
    v_qty := (v_item ->> 'qty')::numeric(14, 3);
    v_unit_cost := (v_item ->> 'unit_cost')::numeric(14, 2);
    v_line_total := round(v_qty * v_unit_cost, 2);

    -- Net inventory amount: proportional discount; last line takes remainder.
    if v_line_idx = v_line_count then
      v_inv_amount := round(v_line_total - (v_discount - v_discount_allocated), 2);
    else
      if v_subtotal = 0 then
        v_share := 0;
      else
        v_share := round(v_line_total * v_discount / v_subtotal, 2);
      end if;
      v_discount_allocated := v_discount_allocated + v_share;
      v_inv_amount := round(v_line_total - v_share, 2);
    end if;

    insert into public.purchase_items (
      purchase_id, product_id, qty, unit_cost, line_total, inv_amount, created_by
    )
    values (
      v_purchase_id, v_product_id, v_qty, v_unit_cost, v_line_total, v_inv_amount, v_user
    );

    select stock_qty, avg_cost
    into v_old_qty, v_old_avg
    from public.products
    where id = v_product_id
    for update;

    v_new_qty := v_old_qty + v_qty;

    if v_old_qty = 0 then
      v_new_avg := case
        when v_new_qty = 0 then 0
        else round(v_inv_amount / v_new_qty, 2)
      end;
    else
      v_new_avg := round(
        (v_old_qty * v_old_avg + v_inv_amount) / v_new_qty,
        2
      );
    end if;

    update public.products
    set
      stock_qty = v_new_qty,
      avg_cost = v_new_avg
    where id = v_product_id;

    insert into public.stock_movements (
      product_id, kind, qty_delta, source_type, source_id, note, created_by
    )
    values (
      v_product_id, 'purchase', v_qty, 'purchase', v_purchase_id, 'Purchase receipt', v_user
    );
  end loop;

  insert into public.journal_entries (
    entry_date, status, memo, source_type, source_id, created_by
  )
  values (
    p_date, 'posted', 'Purchase ' || v_purchase_id::text, 'purchase', v_purchase_id, v_user
  )
  returning id into v_journal_id;

  insert into public.journal_lines (
    journal_entry_id, account_id, debit, credit, created_by
  )
  values (v_journal_id, v_inv_account, v_total, 0, v_user);

  if v_paid > 0 then
    insert into public.journal_lines (
      journal_entry_id, account_id, debit, credit, created_by
    )
    values (v_journal_id, v_cash_account, 0, v_paid, v_user);
  end if;

  if v_payable > 0 then
    insert into public.journal_lines (
      journal_entry_id, account_id, debit, credit, created_by
    )
    values (v_journal_id, v_payable_account, 0, v_payable, v_user);
  end if;

  if v_paid > 0 then
    insert into public.payments (
      kind, party_id, account_id, amount, status, payment_date,
      source_type, source_id, created_by
    )
    values (
      'disbursement', p_supplier, v_cash_account, v_paid, 'posted', p_date,
      'purchase', v_purchase_id, v_user
    );
  end if;

  return v_purchase_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- create_sale — ordered product locks + money round + stock GUC
-- ---------------------------------------------------------------------------
create or replace function public.create_sale(
  p_customer uuid,
  p_date date,
  p_items jsonb,
  p_discount numeric,
  p_paid numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_sale_id uuid;
  v_journal_id uuid;
  v_subtotal numeric(14, 2) := 0;
  v_total numeric(14, 2);
  v_discount numeric(14, 2);
  v_paid numeric(14, 2);
  v_receivable numeric(14, 2);
  v_cogs_total numeric(14, 2) := 0;
  v_item jsonb;
  v_product_id uuid;
  v_qty numeric(14, 3);
  v_unit_price numeric(14, 2);
  v_unit_cost numeric(14, 2);
  v_line_total numeric(14, 2);
  v_line_cogs numeric(14, 2);
  v_old_qty numeric(14, 3);
  v_old_avg numeric(14, 2);
  v_new_qty numeric(14, 3);
  v_cash_account uuid;
  v_ar_account uuid;
  v_revenue_account uuid;
  v_cogs_account uuid;
  v_inv_account uuid;
  v_customer_ok boolean;
begin
  if not public.has_role(array['admin', 'sales']::public.app_role[]) then
    raise exception 'permission denied: requires admin or sales role';
  end if;

  if v_user is null then
    raise exception 'not authenticated';
  end if;

  if p_customer is null then
    raise exception 'customer is required';
  end if;

  if p_date is null then
    raise exception 'sale date is required';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'p_items must be a non-empty JSON array';
  end if;

  perform set_config('app.allow_stock_mutation', '1', true);

  v_discount := round(coalesce(p_discount, 0), 2);
  v_paid := round(coalesce(p_paid, 0), 2);

  if v_discount < 0 then
    raise exception 'discount must be >= 0 (got %)', v_discount;
  end if;

  if v_paid < 0 then
    raise exception 'paid amount must be >= 0 (got %)', v_paid;
  end if;

  select exists (
    select 1
    from public.parties
    where id = p_customer
      and kind = 'customer'
      and is_active
  ) into v_customer_ok;

  if not v_customer_ok then
    raise exception 'customer % not found or not an active customer', p_customer;
  end if;

  select id into v_cash_account from public.accounts where code = '1010';
  select id into v_ar_account from public.accounts where code = '1100';
  select id into v_revenue_account from public.accounts where code = '4000';
  select id into v_cogs_account from public.accounts where code = '5000';
  select id into v_inv_account from public.accounts where code = '1200';

  if v_cash_account is null
     or v_ar_account is null
     or v_revenue_account is null
     or v_cogs_account is null
     or v_inv_account is null then
    raise exception 'chart of accounts missing 1010/1100/4000/5000/1200 — run 0001_schema seed';
  end if;

  for v_item in
    select value
    from jsonb_array_elements(p_items) as t(value)
    order by (t.value ->> 'product_id')::uuid
  loop
    if v_item ->> 'product_id' is null then
      raise exception 'each item requires product_id';
    end if;

    v_product_id := (v_item ->> 'product_id')::uuid;
    v_qty := (v_item ->> 'qty')::numeric(14, 3);
    v_unit_price := (v_item ->> 'unit_price')::numeric(14, 2);

    if v_qty is null or v_qty <= 0 then
      raise exception 'item qty must be > 0 (product %, qty %)', v_product_id, v_qty;
    end if;

    if v_unit_price is null or v_unit_price < 0 then
      raise exception 'item unit_price must be >= 0 (product %, price %)',
        v_product_id, v_unit_price;
    end if;

    if not exists (
      select 1 from public.products where id = v_product_id and is_active
    ) then
      raise exception 'product % not found or inactive', v_product_id;
    end if;

    v_line_total := round(v_qty * v_unit_price, 2);
    v_subtotal := v_subtotal + v_line_total;
  end loop;

  if v_discount > v_subtotal then
    raise exception 'discount (%) cannot exceed subtotal (%)', v_discount, v_subtotal;
  end if;

  v_total := round(v_subtotal - v_discount, 2);

  if v_total <= 0 then
    raise exception 'sale total must be > 0 after discount (subtotal %, discount %)',
      v_subtotal, v_discount;
  end if;

  if v_paid > v_total then
    raise exception 'paid (%) cannot exceed total (%)', v_paid, v_total;
  end if;

  v_receivable := round(v_total - v_paid, 2);

  insert into public.sales (
    customer_id, doc_date, subtotal, discount, total, amount_paid, status, created_by
  )
  values (
    p_customer, p_date, v_subtotal, v_discount, v_total, v_paid, 'posted', v_user
  )
  returning id into v_sale_id;

  for v_item in
    select value
    from jsonb_array_elements(p_items) as t(value)
    order by (t.value ->> 'product_id')::uuid
  loop
    v_product_id := (v_item ->> 'product_id')::uuid;
    v_qty := (v_item ->> 'qty')::numeric(14, 3);
    v_unit_price := (v_item ->> 'unit_price')::numeric(14, 2);
    v_line_total := round(v_qty * v_unit_price, 2);

    select stock_qty, avg_cost
    into v_old_qty, v_old_avg
    from public.products
    where id = v_product_id
    for update;

    if v_old_qty < v_qty then
      raise exception
        'insufficient stock for product % (available %, requested %)',
        v_product_id, v_old_qty, v_qty;
    end if;

    v_unit_cost := v_old_avg;
    v_line_cogs := round(v_qty * v_unit_cost, 2);
    v_cogs_total := v_cogs_total + v_line_cogs;
    v_new_qty := v_old_qty - v_qty;

    insert into public.sale_items (
      sale_id, product_id, qty, unit_price, unit_cost, line_total, created_by
    )
    values (
      v_sale_id, v_product_id, v_qty, v_unit_price, v_unit_cost, v_line_total, v_user
    );

    update public.products
    set stock_qty = v_new_qty
    where id = v_product_id;

    insert into public.stock_movements (
      product_id, kind, qty_delta, source_type, source_id, note, created_by
    )
    values (
      v_product_id, 'sale', -v_qty, 'sale', v_sale_id, 'Sale issue', v_user
    );
  end loop;

  insert into public.journal_entries (
    entry_date, status, memo, source_type, source_id, created_by
  )
  values (
    p_date, 'posted', 'Sale ' || v_sale_id::text, 'sale', v_sale_id, v_user
  )
  returning id into v_journal_id;

  if v_paid > 0 then
    insert into public.journal_lines (
      journal_entry_id, account_id, debit, credit, created_by
    )
    values (v_journal_id, v_cash_account, v_paid, 0, v_user);
  end if;

  if v_receivable > 0 then
    insert into public.journal_lines (
      journal_entry_id, account_id, debit, credit, created_by
    )
    values (v_journal_id, v_ar_account, v_receivable, 0, v_user);
  end if;

  insert into public.journal_lines (
    journal_entry_id, account_id, debit, credit, created_by
  )
  values (v_journal_id, v_revenue_account, 0, v_total, v_user);

  if v_cogs_total > 0 then
    insert into public.journal_lines (
      journal_entry_id, account_id, debit, credit, created_by
    )
    values (v_journal_id, v_cogs_account, v_cogs_total, 0, v_user);

    insert into public.journal_lines (
      journal_entry_id, account_id, debit, credit, created_by
    )
    values (v_journal_id, v_inv_account, 0, v_cogs_total, v_user);
  end if;

  if v_paid > 0 then
    insert into public.payments (
      kind, party_id, account_id, amount, status, payment_date,
      source_type, source_id, created_by
    )
    values (
      'receipt', p_customer, v_cash_account, v_paid, 'posted', p_date,
      'sale', v_sale_id, v_user
    );
  end if;

  return v_sale_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- void_purchase — reverse using inv_amount; set stock GUC
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

  perform set_config('app.allow_stock_mutation', '1', true);

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

  for v_item in
    select product_id, qty, inv_amount
    from public.purchase_items
    where purchase_id = p_id
    order by product_id, id
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

    if v_new_qty = 0 then
      v_new_avg := 0;
    else
      v_new_avg := round(
        (v_old_qty * v_old_avg - v_item.inv_amount) / v_new_qty,
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
      product_id, kind, qty_delta, source_type, source_id, note, created_by
    )
    values (
      v_item.product_id, 'void_reversal', -v_item.qty, 'purchase', p_id,
      'Void purchase reversal', v_user
    );
  end loop;

  perform public.reverse_journals_for_source(
    'purchase', p_id, 'Void purchase ' || p_id::text, v_user
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
      'payment', v_pay.id, 'Void purchase payment ' || v_pay.id::text, v_user
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

-- ---------------------------------------------------------------------------
-- void_sale — stock GUC (ordered locks already present)
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

  perform set_config('app.allow_stock_mutation', '1', true);

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

  for v_item in
    select product_id, qty
    from public.sale_items
    where sale_id = p_id
    order by product_id, id
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
      product_id, kind, qty_delta, source_type, source_id, note, created_by
    )
    values (
      v_item.product_id, 'void_reversal', v_item.qty, 'sale', p_id,
      'Void sale reversal', v_user
    );
  end loop;

  perform public.reverse_journals_for_source(
    'sale', p_id, 'Void sale ' || p_id::text, v_user
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
      'payment', v_pay.id, 'Void sale payment ' || v_pay.id::text, v_user
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

-- ---------------------------------------------------------------------------
-- record_payment — lock docs before outstanding; one payment+journal per doc
-- (void of a single doc no longer reverses sibling allocations).
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
  v_first_payment_id uuid;
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

  -- Lock every open doc first, then sum outstanding (closes TOCTOU race).
  if v_kind = 'receipt' then
    perform 1
    from public.sales
    where customer_id = p_party
      and status = 'posted'
      and amount_paid < total
    order by doc_date asc, created_at asc, id asc
    for update;

    select coalesce(sum(total - amount_paid), 0)
    into v_outstanding
    from public.sales
    where customer_id = p_party
      and status = 'posted'
      and amount_paid < total;
  else
    perform 1
    from public.purchases
    where supplier_id = p_party
      and status = 'posted'
      and amount_paid < total
    order by doc_date asc, created_at asc, id asc
    for update;

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

  v_remaining := v_amount;

  if v_kind = 'receipt' then
    for v_doc in
      select id, total, amount_paid
      from public.sales
      where customer_id = p_party
        and status = 'posted'
        and amount_paid < total
      order by doc_date asc, created_at asc, id asc
    loop
      exit when v_remaining <= 0;
      v_apply := least(v_remaining, round(v_doc.total - v_doc.amount_paid, 2));

      update public.sales
      set amount_paid = amount_paid + v_apply
      where id = v_doc.id;

      insert into public.payments (
        kind, party_id, account_id, amount, status, payment_date,
        reference, source_type, source_id, created_by
      )
      values (
        v_kind, p_party, v_account, v_apply, 'posted',
        (timezone('utc', now()))::date, v_method, 'sale', v_doc.id, v_user
      )
      returning id into v_payment_id;

      if v_first_payment_id is null then
        v_first_payment_id := v_payment_id;
      end if;

      insert into public.journal_entries (
        entry_date, status, memo, source_type, source_id, created_by
      )
      values (
        (timezone('utc', now()))::date, 'posted',
        'Payment ' || v_payment_id::text, 'payment', v_payment_id, v_user
      )
      returning id into v_journal_id;

      insert into public.journal_lines (
        journal_entry_id, account_id, debit, credit, created_by
      ) values
        (v_journal_id, v_account, v_apply, 0, v_user),
        (v_journal_id, v_ar_account, 0, v_apply, v_user);

      v_remaining := round(v_remaining - v_apply, 2);
    end loop;
  else
    for v_doc in
      select id, total, amount_paid
      from public.purchases
      where supplier_id = p_party
        and status = 'posted'
        and amount_paid < total
      order by doc_date asc, created_at asc, id asc
    loop
      exit when v_remaining <= 0;
      v_apply := least(v_remaining, round(v_doc.total - v_doc.amount_paid, 2));

      update public.purchases
      set amount_paid = amount_paid + v_apply
      where id = v_doc.id;

      insert into public.payments (
        kind, party_id, account_id, amount, status, payment_date,
        reference, source_type, source_id, created_by
      )
      values (
        v_kind, p_party, v_account, v_apply, 'posted',
        (timezone('utc', now()))::date, v_method, 'purchase', v_doc.id, v_user
      )
      returning id into v_payment_id;

      if v_first_payment_id is null then
        v_first_payment_id := v_payment_id;
      end if;

      insert into public.journal_entries (
        entry_date, status, memo, source_type, source_id, created_by
      )
      values (
        (timezone('utc', now()))::date, 'posted',
        'Payment ' || v_payment_id::text, 'payment', v_payment_id, v_user
      )
      returning id into v_journal_id;

      insert into public.journal_lines (
        journal_entry_id, account_id, debit, credit, created_by
      ) values
        (v_journal_id, v_ap_account, v_apply, 0, v_user),
        (v_journal_id, v_account, 0, v_apply, v_user);

      v_remaining := round(v_remaining - v_apply, 2);
    end loop;
  end if;

  if v_remaining <> 0 then
    raise exception 'payment allocation incomplete; remaining %', v_remaining;
  end if;

  if v_first_payment_id is null then
    raise exception 'payment allocation produced no documents';
  end if;

  return v_first_payment_id;
end;
$$;

comment on function public.create_purchase(uuid, date, jsonb, numeric, numeric) is
  'Post purchase with net inv_amount (discounted) into moving avg; ordered locks.';

comment on function public.record_payment(uuid, numeric, text, text) is
  'FIFO payment: locks open docs first; one payment+journal per document applied.';


-- ############################################################################
-- FILE: supabase/migrations/0011_adjust_stock.sql
-- ############################################################################

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

