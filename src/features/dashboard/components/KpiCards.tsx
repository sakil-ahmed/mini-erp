import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import type { DashboardKpis, KpiKey } from '@/features/dashboard/types'
import { formatMoney } from '@/shared/lib/money'

const KPI_META: Record<
  KpiKey,
  { label: string; format: 'money' | 'count' }
> = {
  today_sales: { label: 'Today sales', format: 'money' },
  month_sales: { label: 'Month sales', format: 'money' },
  month_purchases: { label: 'Month purchases', format: 'money' },
  stock_value: { label: 'Stock value', format: 'money' },
  receivable: { label: 'Receivable', format: 'money' },
  payable: { label: 'Payable', format: 'money' },
  low_stock_count: { label: 'Low-stock items', format: 'count' },
}

type KpiCardsProps = {
  kpis: DashboardKpis
  visible: readonly KpiKey[]
}

export function KpiCards({ kpis, visible }: KpiCardsProps) {
  if (visible.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">No KPIs for this role.</p>
    )
  }

  return (
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
      {visible.map((key) => {
        const meta = KPI_META[key]
        const raw = kpis[key]
        const value =
          meta.format === 'money' ? formatMoney(raw) : String(raw)
        return (
          <Card key={key} size="sm" className="min-w-0">
            <CardHeader className="gap-1">
              <CardDescription className="truncate">
                {meta.label}
              </CardDescription>
              <CardTitle className="text-xl tabular-nums tracking-tight">
                {value}
              </CardTitle>
            </CardHeader>
          </Card>
        )
      })}
    </div>
  )
}
