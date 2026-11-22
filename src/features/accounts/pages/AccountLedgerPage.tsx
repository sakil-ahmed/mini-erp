import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { Button } from '@/components/ui/button'
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
import {
  useAccountLedgerQuery,
  useChartOfAccountsQuery,
} from '@/features/accounts/api'
import { formatMoney } from '@/shared/lib/money'

export function AccountLedgerPage() {
  const { accountId } = useParams<{ accountId: string }>()
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const chart = useChartOfAccountsQuery()
  const ledger = useAccountLedgerQuery(accountId, from, to)

  const account = chart.data?.find((a) => a.id === accountId)

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-lg font-semibold">
            {account
              ? `${account.code} · ${account.name}`
              : 'Account ledger'}
          </h2>
          <p className="text-sm text-muted-foreground">
            Running balance = cumulative (debit − credit) from SQL.
          </p>
        </div>
        <Button type="button" variant="outline" asChild>
          <Link to="/accounts">Back to chart</Link>
        </Button>
      </div>

      <div className="grid max-w-md gap-3 sm:grid-cols-2">
        <div className="space-y-1.5">
          <Label htmlFor="led-from">From</Label>
          <DatePicker
            id="led-from"
            value={from}
            clearable
            placeholder="Any date"
            onChange={setFrom}
          />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="led-to">To</Label>
          <DatePicker
            id="led-to"
            value={to}
            clearable
            placeholder="Any date"
            onChange={setTo}
          />
        </div>
      </div>

      {ledger.isLoading ? (
        <p className="text-sm text-muted-foreground">Loading ledger…</p>
      ) : ledger.isError ? (
        <p className="text-sm text-destructive">
          {ledger.error instanceof Error
            ? ledger.error.message
            : 'Failed to load'}
        </p>
      ) : (
        <div className="rounded-lg border">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Date</TableHead>
                <TableHead>Memo</TableHead>
                <TableHead className="text-right">Debit</TableHead>
                <TableHead className="text-right">Credit</TableHead>
                <TableHead className="text-right">Balance</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {(ledger.data ?? []).length === 0 ? (
                <TableRow>
                  <TableCell
                    colSpan={5}
                    className="text-center text-muted-foreground"
                  >
                    No posted lines in this range.
                  </TableCell>
                </TableRow>
              ) : (
                (ledger.data ?? []).map((row) => (
                  <TableRow key={row.line_id}>
                    <TableCell>{row.entry_date}</TableCell>
                    <TableCell className="text-sm">
                      {row.memo ?? row.source_type ?? '—'}
                    </TableCell>
                    <TableCell className="text-right">
                      {row.debit > 0 ? formatMoney(row.debit) : '—'}
                    </TableCell>
                    <TableCell className="text-right">
                      {row.credit > 0 ? formatMoney(row.credit) : '—'}
                    </TableCell>
                    <TableCell className="text-right font-medium">
                      {formatMoney(row.running_balance)}
                    </TableCell>
                  </TableRow>
                ))
              )}
            </TableBody>
          </Table>
        </div>
      )}
    </div>
  )
}
