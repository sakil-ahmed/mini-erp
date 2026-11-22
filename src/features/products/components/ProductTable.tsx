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
import type { Product } from '@/features/products/types'

type ProductTableProps = {
  rows: Product[]
  canWrite: boolean
  busyId?: string | null
  onEdit: (product: Product) => void
  onToggleActive: (product: Product) => void
}

export function ProductTable({
  rows,
  canWrite,
  busyId,
  onEdit,
  onToggleActive,
}: ProductTableProps) {
  if (rows.length === 0) {
    return (
      <p className="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
        No products found.
      </p>
    )
  }

  return (
    <div className="rounded-lg border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>SKU</TableHead>
            <TableHead>Name</TableHead>
            <TableHead>Unit</TableHead>
            <TableHead className="text-right">Sale</TableHead>
            <TableHead className="text-right">Avg cost</TableHead>
            <TableHead className="text-right">Stock</TableHead>
            <TableHead>Status</TableHead>
            {canWrite ? <TableHead className="text-right">Actions</TableHead> : null}
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((p) => (
            <TableRow key={p.id} className={!p.is_active ? 'opacity-60' : undefined}>
              <TableCell className="font-medium">{p.sku}</TableCell>
              <TableCell>{p.name}</TableCell>
              <TableCell>{p.unit}</TableCell>
              <TableCell className="text-right">{formatMoney(p.sale_price)}</TableCell>
              <TableCell className="text-right">{formatMoney(p.avg_cost)}</TableCell>
              <TableCell className="text-right">
                {formatQty(p.stock_qty)}
                {p.stock_qty <= p.reorder_level ? (
                  <span className="ml-1 text-xs text-destructive">low</span>
                ) : null}
              </TableCell>
              <TableCell>
                <Badge variant={p.is_active ? 'default' : 'secondary'}>
                  {p.is_active ? 'Active' : 'Inactive'}
                </Badge>
              </TableCell>
              {canWrite ? (
                <TableCell className="space-x-2 text-right">
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    disabled={busyId === p.id}
                    onClick={() => onEdit(p)}
                  >
                    Edit
                  </Button>
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    disabled={busyId === p.id}
                    onClick={() => onToggleActive(p)}
                  >
                    {p.is_active ? 'Deactivate' : 'Activate'}
                  </Button>
                </TableCell>
              ) : null}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  )
}
