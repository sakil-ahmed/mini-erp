import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import {
  PAGE_SIZE,
  useMovementsQuery,
  useProductSummaryQuery,
} from '@/features/inventory/api'
import { MovementTable } from '@/features/inventory/components/MovementTable'
import type { StockMoveKind } from '@/features/inventory/types'
import { PaginationBar } from '@/shared/components/PaginationBar'
import { formatMoney, formatQty } from '@/shared/lib/money'

const KIND_OPTIONS: Array<{ value: '' | StockMoveKind; label: string }> = [
  { value: '', label: 'All types' },
  { value: 'purchase', label: 'Purchase' },
  { value: 'sale', label: 'Sale' },
  { value: 'adjustment', label: 'Adjustment' },
  { value: 'void_reversal', label: 'Void reversal' },
]

export function ProductMovementsPage() {
  const { productId } = useParams<{ productId: string }>()
  const [page, setPage] = useState(1)
  const [kind, setKind] = useState<'' | StockMoveKind>('')

  const product = useProductSummaryQuery(productId)
  const movements = useMovementsQuery(productId, page, kind)

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">
            Movement history
          </h1>
          {product.data ? (
            <p className="text-sm text-muted-foreground">
              {product.data.sku} · {product.data.name} · on hand{' '}
              {formatQty(product.data.stock_qty)} · avg{' '}
              {formatMoney(product.data.avg_cost)}
            </p>
          ) : product.isLoading ? (
            <p className="text-sm text-muted-foreground">Loading product…</p>
          ) : (
            <p className="text-sm text-destructive">Product not found</p>
          )}
        </div>
        <Button type="button" variant="outline" asChild>
          <Link to="/inventory">Back to stock</Link>
        </Button>
      </div>

      <div className="max-w-xs space-y-1.5">
        <Label htmlFor="move-kind">Movement type</Label>
        <select
          id="move-kind"
          className="border-input bg-background h-8 w-full rounded-lg border px-2.5 text-sm"
          value={kind}
          onChange={(e) => {
            setKind(e.target.value as '' | StockMoveKind)
            setPage(1)
          }}
        >
          {KIND_OPTIONS.map((opt) => (
            <option key={opt.value || 'all'} value={opt.value}>
              {opt.label}
            </option>
          ))}
        </select>
      </div>

      {movements.isLoading ? (
        <p className="text-sm text-muted-foreground">Loading movements…</p>
      ) : movements.isError ? (
        <p className="text-sm text-destructive">
          {movements.error instanceof Error
            ? movements.error.message
            : 'Failed to load movements'}
        </p>
      ) : (
        <MovementTable rows={movements.data?.rows ?? []} />
      )}

      <PaginationBar
        page={page}
        total={movements.data?.total ?? 0}
        pageSize={PAGE_SIZE}
        onPageChange={setPage}
      />
    </div>
  )
}
