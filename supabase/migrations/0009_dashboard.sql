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
