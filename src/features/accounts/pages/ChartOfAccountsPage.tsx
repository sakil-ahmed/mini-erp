import { Link } from 'react-router-dom'
import { Badge } from '@/components/ui/badge'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { useChartOfAccountsQuery } from '@/features/accounts/api'

export function ChartOfAccountsPage() {
  const chart = useChartOfAccountsQuery()

  if (chart.isLoading) {
    return <p className="text-sm text-muted-foreground">Loading chart…</p>
  }
  if (chart.isError) {
    return (
      <p className="text-sm text-destructive">
        {chart.error instanceof Error ? chart.error.message : 'Failed to load'}
      </p>
    )
  }

  return (
    <div className="rounded-lg border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Code</TableHead>
            <TableHead>Name</TableHead>
            <TableHead>Type</TableHead>
            <TableHead>Status</TableHead>
            <TableHead className="text-right">Ledger</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {(chart.data ?? []).map((a) => (
            <TableRow key={a.id}>
              <TableCell className="font-medium">{a.code}</TableCell>
              <TableCell>{a.name}</TableCell>
              <TableCell className="capitalize">{a.account_type}</TableCell>
              <TableCell>
                <Badge variant={a.is_active ? 'default' : 'secondary'}>
                  {a.is_active ? 'Active' : 'Inactive'}
                </Badge>
              </TableCell>
              <TableCell className="text-right">
                <Link
                  to={`/accounts/ledger/${a.id}`}
                  className="text-sm text-primary underline-offset-2 hover:underline"
                >
                  Open
                </Link>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  )
}
