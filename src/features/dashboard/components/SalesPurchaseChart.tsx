import {
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import type { DailyFlowRow } from '@/features/dashboard/types'
import { formatMoney } from '@/shared/lib/money'

type SalesPurchaseChartProps = {
  rows: DailyFlowRow[]
  showSales: boolean
  showPurchases: boolean
}

export function SalesPurchaseChart({
  rows,
  showSales,
  showPurchases,
}: SalesPurchaseChartProps) {
  const data = rows.map((r) => ({
    ...r,
    label: r.day.slice(5),
  }))

  return (
    <Card className="min-w-0">
      <CardHeader>
        <CardTitle>Sales vs purchases</CardTitle>
        <CardDescription>Last 30 days (posted docs)</CardDescription>
      </CardHeader>
      <CardContent className="h-72 min-w-0 pt-2">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
            <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
            <XAxis
              dataKey="label"
              tick={{ fontSize: 11 }}
              tickLine={false}
              axisLine={false}
            />
            <YAxis
              tick={{ fontSize: 11 }}
              width={56}
              tickLine={false}
              axisLine={false}
              tickFormatter={(v) =>
                typeof v === 'number' && v >= 1000
                  ? `${(v / 1000).toFixed(0)}k`
                  : String(v)
              }
            />
            <Tooltip
              formatter={(value) =>
                typeof value === 'number' ? formatMoney(value) : value
              }
            />
            <Legend />
            {showSales ? (
              <Line
                type="monotone"
                dataKey="sales_total"
                name="Sales"
                stroke="var(--chart-3)"
                strokeWidth={2}
                dot={false}
                activeDot={{ r: 4 }}
              />
            ) : null}
            {showPurchases ? (
              <Line
                type="monotone"
                dataKey="purchase_total"
                name="Purchases"
                stroke="var(--chart-2)"
                strokeWidth={2}
                dot={false}
                activeDot={{ r: 4 }}
              />
            ) : null}
          </LineChart>
        </ResponsiveContainer>
      </CardContent>
    </Card>
  )
}
