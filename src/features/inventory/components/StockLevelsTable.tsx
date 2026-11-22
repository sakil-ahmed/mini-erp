import { Link } from 'react-router-dom'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
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
  canAdjust?: boolean
  onAdjust?: (row: StockLevelRow) => void
}

export function StockLevelsTable({
  rows,
  canAdjust,
  onAdjust,
}: StockLevelsTableProps) {
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
            <TableHead className="text-right">Actions</TableHead>
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
                <div className="flex items-center justify-end gap-2">
                  {canAdjust && row.is_active ? (
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      onClick={() => onAdjust?.(row)}
                    >
                      Adjust
                    </Button>
                  ) : null}
                  <Link
                    to={`/inventory/${row.id}/movements`}
                    className="text-sm text-primary underline-offset-2 hover:underline"
                  >
                    Movements
                  </Link>
                </div>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  )
}
