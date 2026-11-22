import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { useRole } from '@/features/auth'
import {
  PAGE_SIZE,
  usePurchasesQuery,
  useSuppliersQuery,
} from '@/features/purchases/api'
import { PurchaseFilters } from '@/features/purchases/components/PurchaseFilters'
import { PurchaseTable } from '@/features/purchases/components/PurchaseTable'
import type { DocStatus, PurchaseListFilters } from '@/features/purchases/types'
import { PaginationBar } from '@/shared/components/PaginationBar'

export function PurchasesPage() {
  const { hasRole } = useRole()
  const canCreate = hasRole('purchase', 'admin')
  const suppliers = useSuppliersQuery()

  const [filters, setFilters] = useState<PurchaseListFilters>({
    page: 1,
    dateFrom: '',
    dateTo: '',
    supplierId: '',
    status: '',
  })

  const list = usePurchasesQuery(filters)

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Purchases</h1>
          <p className="text-sm text-muted-foreground">
            Posted purchase documents — void instead of delete.
          </p>
        </div>
        {canCreate ? (
          <Button type="button" asChild>
            <Link to="/purchases/new">New purchase</Link>
          </Button>
        ) : null}
      </div>

      <PurchaseFilters
        dateFrom={filters.dateFrom}
        dateTo={filters.dateTo}
        supplierId={filters.supplierId}
        status={filters.status}
        suppliers={suppliers.data ?? []}
        onChange={(patch) =>
          setFilters((prev) => ({
            ...prev,
            ...patch,
            page: 1,
            status: (patch.status ?? prev.status) as '' | DocStatus,
          }))
        }
      />

      {list.isLoading ? (
        <p className="text-sm text-muted-foreground">Loading purchases…</p>
      ) : list.isError ? (
        <p className="text-sm text-destructive">
          {list.error instanceof Error ? list.error.message : 'Failed to load'}
        </p>
      ) : (
        <PurchaseTable rows={list.data?.rows ?? []} />
      )}

      <PaginationBar
        page={filters.page}
        total={list.data?.total ?? 0}
        pageSize={PAGE_SIZE}
        onPageChange={(page) => setFilters((prev) => ({ ...prev, page }))}
      />
    </div>
  )
}
