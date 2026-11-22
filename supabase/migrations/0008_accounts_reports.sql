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
