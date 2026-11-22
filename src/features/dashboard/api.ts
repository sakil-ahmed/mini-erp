import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { queryKeys } from '@/shared/lib/query-keys'
import { friendlyRpcError } from '@/shared/lib/rpc-error'
import type {
  DailyFlowRow,
  DashboardKpis,
  TopProductRow,
} from '@/features/dashboard/types'

export const dashboardKeys = {
  all: queryKeys.dashboard,
  kpis: [...queryKeys.dashboard, 'kpis'] as const,
  daily: [...queryKeys.dashboard, 'daily-30d'] as const,
  topProducts: [...queryKeys.dashboard, 'top-products'] as const,
}

function num(v: unknown) {
  return Number(v ?? 0)
}

export async function fetchDashboardKpis(): Promise<DashboardKpis> {
  const { data, error } = await supabase
    .from('v_dashboard_kpis')
    .select('*')
    .limit(1)
    .maybeSingle()

  if (error) throw new Error(friendlyRpcError(error))

  const r = (data ?? {}) as Record<string, unknown>
  return {
    today_sales: num(r.today_sales),
    month_sales: num(r.month_sales),
    month_purchases: num(r.month_purchases),
    stock_value: num(r.stock_value),
    receivable: num(r.receivable),
    payable: num(r.payable),
    low_stock_count: num(r.low_stock_count),
  }
}

export async function fetchDailyFlow(): Promise<DailyFlowRow[]> {
  const { data, error } = await supabase
    .from('v_dashboard_daily_30d')
    .select('day, sales_total, purchase_total')
    .order('day', { ascending: true })

  if (error) throw new Error(friendlyRpcError(error))

  return ((data ?? []) as Record<string, unknown>[]).map((r) => ({
    day: String(r.day),
    sales_total: num(r.sales_total),
    purchase_total: num(r.purchase_total),
  }))
}

export async function fetchTopProducts(): Promise<TopProductRow[]> {
  const { data, error } = await supabase
    .from('v_dashboard_top_products')
    .select('product_id, sku, name, qty_sold, revenue')

  if (error) throw new Error(friendlyRpcError(error))

  return ((data ?? []) as Record<string, unknown>[]).map((r) => ({
    product_id: String(r.product_id),
    sku: String(r.sku),
    name: String(r.name),
    qty_sold: num(r.qty_sold),
    revenue: num(r.revenue),
  }))
}

export function useDashboardKpisQuery() {
  return useQuery({
    queryKey: dashboardKeys.kpis,
    queryFn: fetchDashboardKpis,
  })
}

export function useDailyFlowQuery() {
  return useQuery({
    queryKey: dashboardKeys.daily,
    queryFn: fetchDailyFlow,
  })
}

export function useTopProductsQuery(enabled: boolean) {
  return useQuery({
    queryKey: dashboardKeys.topProducts,
    queryFn: fetchTopProducts,
    enabled,
  })
}
