import { useState } from 'react'
import { DatePicker } from '@/components/ui/date-picker'
import { Label } from '@/components/ui/label'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { useProfitAndLossQuery } from '@/features/accounts/api'
import { formatMoney } from '@/shared/lib/money'

function yearStartIso() {
  const d = new Date()
  return `${d.getFullYear()}-01-01`
}

function todayIso() {
  return new Date().toISOString().slice(0, 10)
}

export function ProfitLossPage() {
  const [from, setFrom] = useState(yearStartIso)
  const [to, setTo] = useState(todayIso)
  const pnl = useProfitAndLossQuery(from, to)

  const revenue = (pnl.data?.rows ?? []).filter((r) => r.section === 'revenue')
  const expense = (pnl.data?.rows ?? []).filter((r) => r.section === 'expense')

  return (
    <div className="space-y-4">
      <div className="grid max-w-md gap-3 sm:grid-cols-2">
        <div className="space-y-1.5">
          <Label htmlFor="pnl-from">From</Label>
          <DatePicker id="pnl-from" value={from} onChange={setFrom} />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="pnl-to">To</Label>
          <DatePicker id="pnl-to" value={to} onChange={setTo} />
        </div>
      </div>

      {pnl.isLoading ? (
        <p className="text-sm text-muted-foreground">Loading P&L…</p>
      ) : pnl.isError ? (
        <p className="text-sm text-destructive">
          {pnl.error instanceof Error ? pnl.error.message : 'Failed to load'}
        </p>
      ) : (
        <div className="grid gap-4 lg:grid-cols-2">
          <div className="rounded-lg border">
            <div className="border-b px-3 py-2 text-sm font-medium">Revenue</div>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Account</TableHead>
                  <TableHead className="text-right">Amount</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {revenue.length === 0 ? (
                  <TableRow>
                    <TableCell
                      colSpan={2}
                      className="text-center text-muted-foreground"
                    >
                      No revenue in range.
                    </TableCell>
                  </TableRow>
                ) : (
                  revenue.map((row) => (
                    <TableRow key={row.account_id}>
                      <TableCell>
                        {row.code} · {row.name}
                      </TableCell>
                      <TableCell className="text-right">
                        {formatMoney(row.amount)}
                      </TableCell>
                    </TableRow>
                  ))
                )}
                <TableRow className="font-semibold">
                  <TableCell>Total revenue</TableCell>
                  <TableCell className="text-right">
                    {formatMoney(pnl.data?.summary.total_revenue ?? 0)}
                  </TableCell>
                </TableRow>
              </TableBody>
            </Table>
          </div>

          <div className="rounded-lg border">
            <div className="border-b px-3 py-2 text-sm font-medium">
              Expenses
            </div>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Account</TableHead>
                  <TableHead className="text-right">Amount</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {expense.length === 0 ? (
                  <TableRow>
                    <TableCell
                      colSpan={2}
                      className="text-center text-muted-foreground"
                    >
                      No expenses in range.
                    </TableCell>
                  </TableRow>
                ) : (
                  expense.map((row) => (
                    <TableRow key={row.account_id}>
                      <TableCell>
                        {row.code} · {row.name}
                      </TableCell>
                      <TableCell className="text-right">
                        {formatMoney(row.amount)}
                      </TableCell>
                    </TableRow>
                  ))
                )}
                <TableRow className="font-semibold">
                  <TableCell>Total expense</TableCell>
                  <TableCell className="text-right">
                    {formatMoney(pnl.data?.summary.total_expense ?? 0)}
                  </TableCell>
                </TableRow>
              </TableBody>
            </Table>
          </div>

          <div className="rounded-lg border p-4 lg:col-span-2">
            <div className="flex items-center justify-between text-base font-semibold">
              <span>Net profit</span>
              <span>{formatMoney(pnl.data?.summary.net_profit ?? 0)}</span>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
