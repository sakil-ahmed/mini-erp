import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { useRole } from '@/features/auth'
import {
  PAGE_SIZE,
  useCustomersQuery,
  useSalesQuery,
} from '@/features/sales/api'
import { SaleFilters } from '@/features/sales/components/SaleFilters'
import { SaleTable } from '@/features/sales/components/SaleTable'
import type { DocStatus, SaleListFilters } from '@/features/sales/types'
import { PaginationBar } from '@/shared/components/PaginationBar'

export function SalesPage() {
  const { hasRole } = useRole()
  const canCreate = hasRole('sales')
  const customers = useCustomersQuery()

  const [filters, setFilters] = useState<SaleListFilters>({
    page: 1,
    dateFrom: '',
    dateTo: '',
    customerId: '',
    status: '',
  })

  const list = useSalesQuery(filters)

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Sales</h1>
          <p className="text-sm text-muted-foreground">
            Posted sales — stock and COGS posted via RPC.
          </p>
        </div>
        {canCreate ? (
          <Button type="button" asChild>
            <Link to="/sales/new">New sale</Link>
          </Button>
        ) : null}
      </div>

      <SaleFilters
        dateFrom={filters.dateFrom}
        dateTo={filters.dateTo}
        customerId={filters.customerId}
        status={filters.status}
        customers={customers.data ?? []}
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
        <p className="text-sm text-muted-foreground">Loading sales…</p>
      ) : list.isError ? (
        <p className="text-sm text-destructive">
          {list.error instanceof Error ? list.error.message : 'Failed to load'}
        </p>
      ) : (
        <SaleTable rows={list.data?.rows ?? []} />
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
