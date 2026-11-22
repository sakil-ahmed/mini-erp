import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import {
  usePayablesQuery,
  useReceivablesQuery,
} from '@/features/accounts/api'
import { formatMoney } from '@/shared/lib/money'

type PartyBalancesPageProps = {
  kind: 'receivables' | 'payables'
}

export function PartyBalancesPage({ kind }: PartyBalancesPageProps) {
  const receivables = useReceivablesQuery()
  const payables = usePayablesQuery()
  const query = kind === 'receivables' ? receivables : payables
  const title = kind === 'receivables' ? 'Receivables' : 'Payables'
  const partyLabel = kind === 'receivables' ? 'Customer' : 'Supplier'

  if (query.isLoading) {
    return (
      <p className="text-sm text-muted-foreground">Loading {title.toLowerCase()}…</p>
    )
  }
  if (query.isError) {
    return (
      <p className="text-sm text-destructive">
        {query.error instanceof Error ? query.error.message : 'Failed to load'}
      </p>
    )
  }

  const rows = query.data ?? []

  return (
    <div className="space-y-3">
      <p className="text-sm text-muted-foreground">
        Open {kind === 'receivables' ? 'sales' : 'purchases'} balances from SQL
        view <code className="text-xs">v_party_{kind}</code>.
      </p>
      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{partyLabel}</TableHead>
              <TableHead>Email</TableHead>
              <TableHead className="text-right">Open docs</TableHead>
              <TableHead className="text-right">Balance</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow>
                <TableCell
                  colSpan={4}
                  className="text-center text-muted-foreground"
                >
                  No open balances.
                </TableCell>
              </TableRow>
            ) : (
              rows.map((row) => (
                <TableRow key={row.party_id}>
                  <TableCell className="font-medium">
                    {row.party_name}
                  </TableCell>
                  <TableCell>{row.email ?? '—'}</TableCell>
                  <TableCell className="text-right">{row.open_docs}</TableCell>
                  <TableCell className="text-right">
                    {formatMoney(row.balance)}
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  )
}
