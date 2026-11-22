import { useState } from 'react'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { useRole } from '@/features/auth'
import {
  PAGE_SIZE,
  useAdjustStockMutation,
  useStockLevelsQuery,
} from '@/features/inventory/api'
import { AdjustStockDialog } from '@/features/inventory/components/AdjustStockDialog'
import { StockLevelsTable } from '@/features/inventory/components/StockLevelsTable'
import type { StockAdjustValues } from '@/features/inventory/schemas'
import type { StockLevelRow } from '@/features/inventory/types'
import { PaginationBar } from '@/shared/components/PaginationBar'
import { SearchField } from '@/shared/components/SearchField'
import { useDebouncedValue } from '@/shared/hooks/useDebouncedValue'

export function InventoryPage() {
  const { isAdmin, hasRole } = useRole()
  const canAdjust = isAdmin || hasRole('purchase')

  const [page, setPage] = useState(1)
  const [search, setSearch] = useState('')
  const [lowOnly, setLowOnly] = useState(false)
  const debouncedSearch = useDebouncedValue(search)
  const list = useStockLevelsQuery(page, debouncedSearch, lowOnly)
  const adjust = useAdjustStockMutation()

  const [selected, setSelected] = useState<StockLevelRow | null>(null)
  const [open, setOpen] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const onSubmit = async (values: StockAdjustValues) => {
    if (!selected) return
    setError(null)
    try {
      await adjust.mutateAsync({ productId: selected.id, values })
      setOpen(false)
      setSelected(null)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Adjustment failed')
    }
  }

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Inventory</h1>
        <p className="text-sm text-muted-foreground">
          On-hand levels and value. Purchases/sales post automatically;
          {canAdjust ? ' use Adjust for cycle counts.' : ' adjustments need admin/purchase.'}
        </p>
      </div>

      <div className="flex flex-wrap items-center gap-4">
        <SearchField
          value={search}
          onChange={(v) => {
            setSearch(v)
            setPage(1)
          }}
          placeholder="Search SKU or name…"
        />
        <div className="flex items-center gap-2">
          <Switch
            id="low-only"
            checked={lowOnly}
            onCheckedChange={(v) => {
              setLowOnly(v)
              setPage(1)
            }}
          />
          <Label htmlFor="low-only">Low stock only</Label>
        </div>
      </div>

      {list.isLoading ? (
        <p className="text-sm text-muted-foreground">Loading stock…</p>
      ) : list.isError ? (
        <p className="text-sm text-destructive">
          {list.error instanceof Error ? list.error.message : 'Failed to load'}
        </p>
      ) : (
        <StockLevelsTable
          rows={list.data?.rows ?? []}
          canAdjust={canAdjust}
          onAdjust={(row) => {
            setError(null)
            setSelected(row)
            setOpen(true)
          }}
        />
      )}

      <PaginationBar
        page={page}
        total={list.data?.total ?? 0}
        pageSize={PAGE_SIZE}
        onPageChange={setPage}
      />

      <AdjustStockDialog
        open={open}
        product={selected}
        submitting={adjust.isPending}
        error={error}
        onOpenChange={(next) => {
          setOpen(next)
          if (!next) setSelected(null)
        }}
        onSubmit={(values) => {
          void onSubmit(values)
        }}
      />
    </div>
  )
}
