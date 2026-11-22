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
import { formatQty } from '@/shared/lib/money'
import type { StockMovementRow } from '@/features/inventory/types'

type MovementTableProps = {
  rows: StockMovementRow[]
}

function kindVariant(kind: StockMovementRow['kind']) {
  if (kind === 'purchase') return 'default' as const
  if (kind === 'sale') return 'secondary' as const
  if (kind === 'void_reversal') return 'outline' as const
  return 'secondary' as const
}

function sourceHref(sourceType: string, sourceId: string) {
  if (sourceType === 'purchase' || sourceType === 'purchase_void') {
    return `/purchases/${sourceId}`
  }
  if (sourceType === 'sale' || sourceType === 'sale_void') {
    return `/sales/${sourceId}`
  }
  return null
}

export function MovementTable({ rows }: MovementTableProps) {
  if (rows.length === 0) {
    return (
      <p className="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
        No movements for this filter.
      </p>
    )
  }

  return (
    <div className="rounded-lg border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>When</TableHead>
            <TableHead>Type</TableHead>
            <TableHead className="text-right">Qty Δ</TableHead>
            <TableHead>Source</TableHead>
            <TableHead>Note</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((row) => {
            const href = sourceHref(row.source_type, row.source_id)
            const when = new Date(row.created_at).toLocaleString()
            return (
              <TableRow key={row.id}>
                <TableCell className="whitespace-nowrap text-sm">
                  {when}
                </TableCell>
                <TableCell>
                  <Badge variant={kindVariant(row.kind)}>{row.kind}</Badge>
                </TableCell>
                <TableCell
                  className={
                    row.qty_delta < 0
                      ? 'text-right text-destructive'
                      : 'text-right text-emerald-700'
                  }
                >
                  {row.qty_delta > 0 ? '+' : ''}
                  {formatQty(row.qty_delta)}
                </TableCell>
                <TableCell className="text-sm">
                  {href ? (
                    <Link
                      to={href}
                      className="text-primary underline-offset-2 hover:underline"
                    >
                      {row.source_type}
                    </Link>
                  ) : (
                    <span>{row.source_type}</span>
                  )}
                </TableCell>
                <TableCell className="text-sm text-muted-foreground">
                  {row.note ?? '—'}
                </TableCell>
              </TableRow>
            )
          })}
        </TableBody>
      </Table>
    </div>
  )
}
