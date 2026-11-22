import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { PartyForm } from '@/features/parties/components/PartyForm'
import type { PartyFormValues } from '@/features/parties/schemas'
import type { Party, PartyKind } from '@/features/parties/types'

type PartyDialogProps = {
  open: boolean
  kind: PartyKind
  party: Party | null
  submitting?: boolean
  error?: string | null
  onOpenChange: (open: boolean) => void
  onSubmit: (values: PartyFormValues) => void
}

export function PartyDialog({
  open,
  kind,
  party,
  submitting,
  error,
  onOpenChange,
  onSubmit,
}: PartyDialogProps) {
  const label = kind === 'customer' ? 'customer' : 'supplier'

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>
            {party ? `Edit ${label}` : `New ${label}`}
          </DialogTitle>
        </DialogHeader>
        <PartyForm
          key={party?.id ?? `new-${kind}`}
          initial={party}
          submitting={submitting}
          error={error}
          onSubmit={onSubmit}
          onCancel={() => onOpenChange(false)}
        />
      </DialogContent>
    </Dialog>
  )
}
