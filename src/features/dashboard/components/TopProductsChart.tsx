import {
  Bar,
  BarChart,
  CartesianGrid,
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
import type { TopProductRow } from '@/features/dashboard/types'
import { formatMoney } from '@/shared/lib/money'

type TopProductsChartProps = {
  rows: TopProductRow[]
}

export function TopProductsChart({ rows }: TopProductsChartProps) {
  const data = rows.map((r) => ({
    name: r.sku,
    revenue: r.revenue,
    fullName: r.name,
  }))

  return (
    <Card className="min-w-0">
      <CardHeader>
        <CardTitle>Top products</CardTitle>
        <CardDescription>Top 5 by revenue · last 30 days</CardDescription>
      </CardHeader>
      <CardContent className="h-72 min-w-0 pt-2">
        {data.length === 0 ? (
          <p className="flex h-full items-center justify-center text-sm text-muted-foreground">
            No sales in the last 30 days.
          </p>
        ) : (
          <ResponsiveContainer width="100%" height="100%">
            <BarChart
              data={data}
              layout="vertical"
              margin={{ top: 8, right: 16, left: 8, bottom: 0 }}
            >
              <CartesianGrid
                strokeDasharray="3 3"
                className="stroke-border"
                horizontal={false}
              />
              <XAxis
                type="number"
                tick={{ fontSize: 11 }}
                tickLine={false}
                axisLine={false}
              />
              <YAxis
                type="category"
                dataKey="name"
                width={72}
                tick={{ fontSize: 11 }}
                tickLine={false}
                axisLine={false}
              />
              <Tooltip
                formatter={(value) =>
                  typeof value === 'number' ? formatMoney(value) : value
                }
                labelFormatter={(_, payload) => {
                  const row = payload?.[0]?.payload as
                    | { fullName?: string }
                    | undefined
                  return row?.fullName ?? ''
                }}
              />
              <Bar
                dataKey="revenue"
                name="Revenue"
                fill="var(--chart-3)"
                radius={[0, 4, 4, 0]}
              />
            </BarChart>
          </ResponsiveContainer>
        )}
      </CardContent>
    </Card>
  )
}
