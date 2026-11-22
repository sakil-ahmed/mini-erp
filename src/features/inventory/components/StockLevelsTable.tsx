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
import { formatMoney, formatQty } from '@/shared/lib/money'
import type { StockLevelRow } from '@/features/inventory/types'

type StockLevelsTableProps = {
  rows: StockLevelRow[]
}

export function StockLevelsTable({ rows }: StockLevelsTableProps) {
  if (rows.length === 0) {
    return (
      <p className="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
        No stock rows found.
      </p>
    )
  }

  return (
    <div className="rounded-lg border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>SKU</TableHead>
            <TableHead>Product</TableHead>
            <TableHead className="text-right">Qty</TableHead>
            <TableHead className="text-right">Avg cost</TableHead>
            <TableHead className="text-right">Stock value</TableHead>
            <TableHead>Status</TableHead>
            <TableHead className="text-right">History</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((row) => (
            <TableRow
              key={row.id}
              className={!row.is_active ? 'opacity-60' : undefined}
            >
              <TableCell className="font-medium">{row.sku}</TableCell>
              <TableCell>
                {row.name}
                <span className="ml-1 text-xs text-muted-foreground">
                  / {row.unit}
                </span>
              </TableCell>
              <TableCell className="text-right">
                {formatQty(row.stock_qty)}
              </TableCell>
              <TableCell className="text-right">
                {formatMoney(row.avg_cost)}
              </TableCell>
              <TableCell className="text-right">
                {formatMoney(row.stock_value)}
              </TableCell>
              <TableCell>
                <div className="flex flex-wrap gap-1">
                  {row.is_low ? (
                    <Badge variant="destructive">Low stock</Badge>
                  ) : (
                    <Badge variant="secondary">OK</Badge>
                  )}
                  {!row.is_active ? (
                    <Badge variant="outline">Inactive</Badge>
                  ) : null}
                </div>
              </TableCell>
              <TableCell className="text-right">
                <Link
                  to={`/inventory/${row.id}/movements`}
                  className="text-sm text-primary underline-offset-2 hover:underline"
                >
                  Movements
                </Link>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  )
}
