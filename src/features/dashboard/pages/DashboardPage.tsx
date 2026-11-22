import { useRole } from '@/features/auth'
import {
  useDailyFlowQuery,
  useDashboardKpisQuery,
  useTopProductsQuery,
} from '@/features/dashboard/api'
import { KpiCards } from '@/features/dashboard/components/KpiCards'
import { SalesPurchaseChart } from '@/features/dashboard/components/SalesPurchaseChart'
import { TopProductsChart } from '@/features/dashboard/components/TopProductsChart'
import {
  canSeePurchaseChart,
  canSeeSalesChart,
  canSeeTopProducts,
  visibleKpis,
} from '@/features/dashboard/lib/visibility'

export function DashboardPage() {
  const { role, isLoading: roleLoading } = useRole()
  const kpis = useDashboardKpisQuery()
  const daily = useDailyFlowQuery()
  const showTop = canSeeTopProducts(role)
  const top = useTopProductsQuery(showTop)

  const showSales = canSeeSalesChart(role)
  const showPurchases = canSeePurchaseChart(role)
  const showFlowChart = showSales || showPurchases
  const kpiKeys = visibleKpis(role)

  if (roleLoading || kpis.isLoading) {
    return (
      <div className="space-y-6">
        <div className="space-y-1">
          <div className="bg-muted h-7 w-40 animate-pulse rounded" />
          <div className="bg-muted h-4 w-64 animate-pulse rounded" />
        </div>
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <div
              key={i}
              className="bg-muted h-20 animate-pulse rounded-xl"
            />
          ))}
        </div>
      </div>
    )
  }

  if (kpis.isError) {
    return (
      <div className="rounded-lg border border-destructive/30 bg-destructive/5 px-4 py-3 text-sm text-destructive">
        {kpis.error instanceof Error ? kpis.error.message : 'Failed to load KPIs'}
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Dashboard</h1>
          <p className="text-sm text-muted-foreground">
            Live KPIs from SQL views
            {role ? ` · ${role}` : ''}.
          </p>
        </div>
      </div>

      <KpiCards kpis={kpis.data!} visible={kpiKeys} />

      {(showFlowChart || showTop) && (
        <div className="grid gap-4 xl:grid-cols-2">
          {showFlowChart ? (
            daily.isLoading ? (
              <div className="bg-muted h-80 animate-pulse rounded-xl" />
            ) : daily.isError ? (
              <div className="rounded-lg border border-destructive/30 bg-destructive/5 px-4 py-3 text-sm text-destructive">
                {daily.error instanceof Error
                  ? daily.error.message
                  : 'Chart failed'}
              </div>
            ) : (
              <SalesPurchaseChart
                rows={daily.data ?? []}
                showSales={showSales}
                showPurchases={showPurchases}
              />
            )
          ) : null}

          {showTop ? (
            top.isLoading ? (
              <div className="bg-muted h-80 animate-pulse rounded-xl" />
            ) : top.isError ? (
              <div className="rounded-lg border border-destructive/30 bg-destructive/5 px-4 py-3 text-sm text-destructive">
                {top.error instanceof Error ? top.error.message : 'Chart failed'}
              </div>
            ) : (
              <TopProductsChart rows={top.data ?? []} />
            )
          ) : null}
        </div>
      )}
    </div>
  )
}
