import { Fragment, useState } from 'react'
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
import { PAGE_SIZE, useJournalsQuery } from '@/features/accounts/api'
import type { JournalEntry } from '@/features/accounts/types'
import { PaginationBar } from '@/shared/components/PaginationBar'
import { formatMoney } from '@/shared/lib/money'

function JournalLines({ entry }: { entry: JournalEntry }) {
  return (
    <div className="rounded-md border bg-muted/30 p-2">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Account</TableHead>
            <TableHead className="text-right">Debit</TableHead>
            <TableHead className="text-right">Credit</TableHead>
            <TableHead>Memo</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {entry.lines.map((line) => (
            <TableRow key={line.id}>
              <TableCell>
                {line.account_code} · {line.account_name}
              </TableCell>
              <TableCell className="text-right">
                {line.debit > 0 ? formatMoney(line.debit) : '—'}
              </TableCell>
              <TableCell className="text-right">
                {line.credit > 0 ? formatMoney(line.credit) : '—'}
              </TableCell>
              <TableCell className="text-muted-foreground">
                {line.memo ?? '—'}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  )
}

export function JournalsPage() {
  const [page, setPage] = useState(1)
  const [openId, setOpenId] = useState<string | null>(null)
  const journals = useJournalsQuery(page)

  if (journals.isLoading) {
    return <p className="text-sm text-muted-foreground">Loading journals…</p>
  }
  if (journals.isError) {
    return (
      <p className="text-sm text-destructive">
        {journals.error instanceof Error
          ? journals.error.message
          : 'Failed to load'}
      </p>
    )
  }

  const rows = journals.data?.rows ?? []

  return (
    <div className="space-y-4">
      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead>Memo</TableHead>
              <TableHead>Source</TableHead>
              <TableHead>Status</TableHead>
              <TableHead className="text-right">Lines</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow>
                <TableCell
                  colSpan={5}
                  className="text-center text-muted-foreground"
                >
                  No journal entries.
                </TableCell>
              </TableRow>
            ) : (
              rows.map((entry) => {
                const expanded = openId === entry.id
                return (
                  <Fragment key={entry.id}>
                    <TableRow>
                      <TableCell>{entry.entry_date}</TableCell>
                      <TableCell>{entry.memo ?? '—'}</TableCell>
                      <TableCell className="text-sm text-muted-foreground">
                        {entry.source_type ?? '—'}
                      </TableCell>
                      <TableCell>
                        <Badge
                          variant={
                            entry.status === 'posted' ? 'default' : 'secondary'
                          }
                        >
                          {entry.status}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-right">
                        <Button
                          type="button"
                          variant="ghost"
                          size="sm"
                          onClick={() =>
                            setOpenId(expanded ? null : entry.id)
                          }
                        >
                          {expanded ? 'Hide' : `Show (${entry.lines.length})`}
                        </Button>
                      </TableCell>
                    </TableRow>
                    {expanded ? (
                      <TableRow>
                        <TableCell colSpan={5}>
                          <JournalLines entry={entry} />
                        </TableCell>
                      </TableRow>
                    ) : null}
                  </Fragment>
                )
              })
            )}
          </TableBody>
        </Table>
      </div>

      <PaginationBar
        page={page}
        total={journals.data?.total ?? 0}
        pageSize={PAGE_SIZE}
        onPageChange={setPage}
      />
    </div>
  )
}
