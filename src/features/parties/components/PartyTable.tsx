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
import type { Party } from '@/features/parties/types'

type PartyTableProps = {
  rows: Party[]
  canWrite: boolean
  busyId?: string | null
  onEdit: (party: Party) => void
  onToggleActive: (party: Party) => void
}

export function PartyTable({
  rows,
  canWrite,
  busyId,
  onEdit,
  onToggleActive,
}: PartyTableProps) {
  if (rows.length === 0) {
    return (
      <p className="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
        No parties found.
      </p>
    )
  }

  return (
    <div className="rounded-lg border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Name</TableHead>
            <TableHead>Email</TableHead>
            <TableHead>Phone</TableHead>
            <TableHead>Status</TableHead>
            {canWrite ? <TableHead className="text-right">Actions</TableHead> : null}
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((p) => (
            <TableRow key={p.id} className={!p.is_active ? 'opacity-60' : undefined}>
              <TableCell className="font-medium">{p.name}</TableCell>
              <TableCell>{p.email ?? '—'}</TableCell>
              <TableCell>{p.phone ?? '—'}</TableCell>
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
