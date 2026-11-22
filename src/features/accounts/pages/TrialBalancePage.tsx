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
import { useTrialBalanceQuery } from '@/features/accounts/api'
import { formatMoney } from '@/shared/lib/money'

function todayIso() {
  return new Date().toISOString().slice(0, 10)
}

export function TrialBalancePage() {
  const [asOf, setAsOf] = useState(todayIso)
  const tb = useTrialBalanceQuery(asOf)

  return (
    <div className="space-y-4">
      <div className="max-w-xs space-y-1.5">
        <Label htmlFor="as-of">As of</Label>
        <DatePicker id="as-of" value={asOf} onChange={setAsOf} />
      </div>

      {tb.isLoading ? (
        <p className="text-sm text-muted-foreground">Loading trial balance…</p>
      ) : tb.isError ? (
        <p className="text-sm text-destructive">
          {tb.error instanceof Error ? tb.error.message : 'Failed to load'}
        </p>
      ) : (
        <>
          {tb.data && !tb.data.totals.is_balanced ? (
            <div className="rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive">
              Trial balance is out of balance by{' '}
              {formatMoney(Math.abs(tb.data.totals.difference))} (debits{' '}
              {formatMoney(tb.data.totals.total_debit)} vs credits{' '}
              {formatMoney(tb.data.totals.total_credit)}).
            </div>
          ) : (
            <div className="rounded-md border bg-muted/40 px-3 py-2 text-sm text-muted-foreground">
              Debits equal credits — trial balance is balanced.
            </div>
          )}

          <div className="rounded-lg border">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Code</TableHead>
                  <TableHead>Account</TableHead>
                  <TableHead>Type</TableHead>
                  <TableHead className="text-right">Debit</TableHead>
                  <TableHead className="text-right">Credit</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(tb.data?.rows ?? []).map((row) => (
                  <TableRow key={row.account_id}>
                    <TableCell className="font-medium">{row.code}</TableCell>
                    <TableCell>{row.name}</TableCell>
                    <TableCell className="capitalize">
                      {row.account_type}
                    </TableCell>
                    <TableCell className="text-right">
                      {row.total_debit > 0
                        ? formatMoney(row.total_debit)
                        : '—'}
                    </TableCell>
                    <TableCell className="text-right">
                      {row.total_credit > 0
                        ? formatMoney(row.total_credit)
                        : '—'}
                    </TableCell>
                  </TableRow>
                ))}
                <TableRow className="font-semibold">
                  <TableCell colSpan={3}>Totals</TableCell>
                  <TableCell className="text-right">
                    {formatMoney(tb.data?.totals.total_debit ?? 0)}
                  </TableCell>
                  <TableCell className="text-right">
                    {formatMoney(tb.data?.totals.total_credit ?? 0)}
                  </TableCell>
                </TableRow>
              </TableBody>
            </Table>
          </div>
        </>
      )}
    </div>
  )
}
