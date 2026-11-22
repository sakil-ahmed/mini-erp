import { useState } from 'react'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import {
  PAGE_SIZE,
  useStockLevelsQuery,
} from '@/features/inventory/api'
import { StockLevelsTable } from '@/features/inventory/components/StockLevelsTable'
import { PaginationBar } from '@/shared/components/PaginationBar'
import { SearchField } from '@/shared/components/SearchField'
import { useDebouncedValue } from '@/shared/hooks/useDebouncedValue'

export function InventoryPage() {
  const [page, setPage] = useState(1)
  const [search, setSearch] = useState('')
  const [lowOnly, setLowOnly] = useState(false)
  const debouncedSearch = useDebouncedValue(search)
  const list = useStockLevelsQuery(page, debouncedSearch, lowOnly)

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Inventory</h1>
        <p className="text-sm text-muted-foreground">
          On-hand levels and value — read-only (posting via purchases/sales).
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
        <StockLevelsTable rows={list.data?.rows ?? []} />
      )}

      <PaginationBar
        page={page}
        total={list.data?.total ?? 0}
        pageSize={PAGE_SIZE}
        onPageChange={setPage}
      />
    </div>
  )
}
