import type { AppRole } from '@/features/auth'
import type { KpiKey } from '@/features/dashboard/types'

/** Which KPI cards each role may see. Sales is intentionally sales-only. */
const KPI_BY_ROLE: Record<AppRole, readonly KpiKey[]> = {
  admin: [
    'today_sales',
    'month_sales',
    'month_purchases',
    'stock_value',
    'receivable',
    'payable',
    'low_stock_count',
  ],
  sales: ['today_sales', 'month_sales'],
  purchase: ['month_purchases', 'stock_value', 'low_stock_count'],
  accountant: [
    'today_sales',
    'month_sales',
    'month_purchases',
    'stock_value',
    'receivable',
    'payable',
    'low_stock_count',
  ],
}

export function visibleKpis(role: AppRole | null): readonly KpiKey[] {
  if (!role) return []
  return KPI_BY_ROLE[role]
}

export function canSeeSalesChart(role: AppRole | null): boolean {
  return role === 'admin' || role === 'sales' || role === 'accountant'
}

export function canSeePurchaseChart(role: AppRole | null): boolean {
  return role === 'admin' || role === 'purchase' || role === 'accountant'
}

export function canSeeTopProducts(role: AppRole | null): boolean {
  return role === 'admin' || role === 'sales' || role === 'accountant'
}
