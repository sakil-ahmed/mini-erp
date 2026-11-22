import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { useRole } from '@/features/auth'
import {
  useProductMutations,
  useProductsQuery,
} from '@/features/products/api'
import { ProductDialog } from '@/features/products/components/ProductDialog'
import { ProductTable } from '@/features/products/components/ProductTable'
import type { ProductFormValues } from '@/features/products/schemas'
import type { Product } from '@/features/products/types'
import { PaginationBar } from '@/shared/components/PaginationBar'
import { SearchField } from '@/shared/components/SearchField'
import { useDebouncedValue } from '@/shared/hooks/useDebouncedValue'

export function ProductsPage() {
  const { isAdmin } = useRole()
  const [page, setPage] = useState(1)
  const [search, setSearch] = useState('')
  const debouncedSearch = useDebouncedValue(search)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<Product | null>(null)
  const [formError, setFormError] = useState<string | null>(null)

  const list = useProductsQuery(page, debouncedSearch)
  const { create, update, setActive, pageSize } = useProductMutations()

  const openCreate = () => {
    setEditing(null)
    setFormError(null)
    setDialogOpen(true)
  }

  const openEdit = (product: Product) => {
    setEditing(product)
    setFormError(null)
    setDialogOpen(true)
  }

  const onSubmit = async (values: ProductFormValues) => {
    setFormError(null)
    try {
      if (editing) {
        await update.mutateAsync({ id: editing.id, values })
      } else {
        await create.mutateAsync(values)
      }
      setDialogOpen(false)
    } catch (err) {
      setFormError(err instanceof Error ? err.message : 'Save failed')
    }
  }

  const onToggleActive = async (product: Product) => {
    try {
      await setActive.mutateAsync({
        id: product.id,
        isActive: !product.is_active,
      })
    } catch (err) {
      setFormError(err instanceof Error ? err.message : 'Update failed')
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Products</h1>
          <p className="text-sm text-muted-foreground">
            Catalog with search and soft deactivate.
          </p>
        </div>
        {isAdmin ? (
          <Button type="button" onClick={openCreate}>
            New product
          </Button>
        ) : null}
      </div>

      <SearchField
        value={search}
        onChange={(v) => {
          setSearch(v)
          setPage(1)
        }}
        placeholder="Search SKU or name…"
      />

      {list.isLoading ? (
        <p className="text-sm text-muted-foreground">Loading products…</p>
      ) : list.isError ? (
        <p className="text-sm text-destructive">
          {list.error instanceof Error ? list.error.message : 'Failed to load'}
        </p>
      ) : (
        <ProductTable
          rows={list.data?.rows ?? []}
          canWrite={isAdmin}
          busyId={setActive.isPending ? setActive.variables?.id : null}
          onEdit={openEdit}
          onToggleActive={(p) => {
            void onToggleActive(p)
          }}
        />
      )}

      <PaginationBar
        page={page}
        total={list.data?.total ?? 0}
        pageSize={pageSize}
        onPageChange={setPage}
      />

      {formError && !dialogOpen ? (
        <p className="text-sm text-destructive">{formError}</p>
      ) : null}

      <ProductDialog
        open={dialogOpen}
        product={editing}
        submitting={create.isPending || update.isPending}
        error={formError}
        onOpenChange={setDialogOpen}
        onSubmit={(values) => {
          void onSubmit(values)
        }}
      />
    </div>
  )
}
