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
import { formatMoney } from '@/shared/lib/money'
import type { SaleListItem } from '@/features/sales/types'

type SaleTableProps = {
  rows: SaleListItem[]
}

export function SaleTable({ rows }: SaleTableProps) {
  if (rows.length === 0) {
    return (
      <p className="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
        No sales found.
      </p>
    )
  }

  return (
    <div className="rounded-lg border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Doc #</TableHead>
            <TableHead>Date</TableHead>
            <TableHead>Customer</TableHead>
            <TableHead>Status</TableHead>
            <TableHead className="text-right">Total</TableHead>
            <TableHead className="text-right">Paid</TableHead>
            <TableHead className="text-right">Due</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((row) => {
            const due = Math.max(0, row.total - row.amount_paid)
            return (
              <TableRow key={row.id}>
                <TableCell>
                  <Link
                    to={`/sales/${row.id}`}
                    className="font-medium text-primary underline-offset-2 hover:underline"
                  >
                    {row.doc_number}
                  </Link>
                </TableCell>
                <TableCell>{row.doc_date}</TableCell>
                <TableCell>{row.customer_name}</TableCell>
                <TableCell>
                  <Badge
                    variant={row.status === 'posted' ? 'default' : 'secondary'}
                  >
                    {row.status}
                  </Badge>
                </TableCell>
                <TableCell className="text-right">
                  {formatMoney(row.total)}
                </TableCell>
                <TableCell className="text-right">
                  {formatMoney(row.amount_paid)}
                </TableCell>
                <TableCell className="text-right">{formatMoney(due)}</TableCell>
              </TableRow>
            )
          })}
        </TableBody>
      </Table>
    </div>
  )
}
