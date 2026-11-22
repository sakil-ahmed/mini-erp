import { useState } from 'react'
import { Button } from '@/components/ui/button'
import {
  usePartiesQuery,
  usePartyMutations,
} from '@/features/parties/api'
import { PartyDialog } from '@/features/parties/components/PartyDialog'
import { PartyTable } from '@/features/parties/components/PartyTable'
import type { PartyFormValues } from '@/features/parties/schemas'
import type { Party, PartyKind } from '@/features/parties/types'
import { PaginationBar } from '@/shared/components/PaginationBar'
import { SearchField } from '@/shared/components/SearchField'
import { useDebouncedValue } from '@/shared/hooks/useDebouncedValue'

type PartyKindPanelProps = {
  kind: PartyKind
  canWrite: boolean
}

export function PartyKindPanel({ kind, canWrite }: PartyKindPanelProps) {
  const [page, setPage] = useState(1)
  const [search, setSearch] = useState('')
  const debouncedSearch = useDebouncedValue(search)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<Party | null>(null)
  const [formError, setFormError] = useState<string | null>(null)

  const list = usePartiesQuery(kind, page, debouncedSearch)
  const { create, update, setActive, pageSize } = usePartyMutations()

  const onSubmit = async (values: PartyFormValues) => {
    setFormError(null)
    try {
      if (editing) {
        await update.mutateAsync({ id: editing.id, values })
      } else {
        await create.mutateAsync({ kind, values })
      }
      setDialogOpen(false)
    } catch (err) {
      setFormError(err instanceof Error ? err.message : 'Save failed')
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <SearchField
          value={search}
          onChange={(v) => {
            setSearch(v)
            setPage(1)
          }}
          placeholder="Search name, email, phone…"
        />
        {canWrite ? (
          <Button
            type="button"
            onClick={() => {
              setEditing(null)
              setFormError(null)
              setDialogOpen(true)
            }}
          >
            New {kind}
          </Button>
        ) : null}
      </div>

      {list.isLoading ? (
        <p className="text-sm text-muted-foreground">Loading…</p>
      ) : list.isError ? (
        <p className="text-sm text-destructive">
          {list.error instanceof Error ? list.error.message : 'Failed to load'}
        </p>
      ) : (
        <PartyTable
          rows={list.data?.rows ?? []}
          canWrite={canWrite}
          busyId={setActive.isPending ? setActive.variables?.id : null}
          onEdit={(p) => {
            setEditing(p)
            setFormError(null)
            setDialogOpen(true)
          }}
          onToggleActive={(p) => {
            void setActive
              .mutateAsync({ id: p.id, isActive: !p.is_active })
              .catch((err: unknown) => {
                setFormError(
                  err instanceof Error ? err.message : 'Update failed',
                )
              })
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

      <PartyDialog
        open={dialogOpen}
        kind={kind}
        party={editing}
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
