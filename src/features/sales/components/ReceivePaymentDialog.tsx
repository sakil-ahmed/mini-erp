import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  receivePaymentSchema,
  type ReceivePaymentValues,
} from '@/features/sales/schemas'
import { formatMoney } from '@/shared/lib/money'

type ReceivePaymentDialogProps = {
  open: boolean
  due: number
  submitting?: boolean
  error?: string | null
  onOpenChange: (open: boolean) => void
  onSubmit: (values: ReceivePaymentValues) => void
}

export function ReceivePaymentDialog({
  open,
  due,
  submitting,
  error,
  onOpenChange,
  onSubmit,
}: ReceivePaymentDialogProps) {
  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<ReceivePaymentValues>({
    resolver: zodResolver(receivePaymentSchema),
    values: {
      amount: due,
      method: 'cash',
    },
  })

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-sm">
        <DialogHeader>
          <DialogTitle>Receive payment</DialogTitle>
        </DialogHeader>
        <p className="text-xs text-muted-foreground">
          Outstanding on this sale: {formatMoney(due)}. Payments allocate FIFO
          to the customer&apos;s open sales.
        </p>
        <form
          className="space-y-4"
          onSubmit={handleSubmit(onSubmit)}
          noValidate
        >
          <div className="space-y-1.5">
            <Label htmlFor="pay-amount">Amount</Label>
            <Input
              id="pay-amount"
              type="number"
              step="0.01"
              min="0.01"
              max={due}
              disabled={submitting}
              {...register('amount', { valueAsNumber: true })}
            />
            {errors.amount ? (
              <p className="text-xs text-destructive">{errors.amount.message}</p>
            ) : null}
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="pay-method">Method</Label>
            <select
              id="pay-method"
              className="border-input bg-background h-8 w-full rounded-lg border px-2.5 text-sm"
              disabled={submitting}
              {...register('method')}
            >
              <option value="cash">Cash</option>
              <option value="bank">Bank</option>
            </select>
          </div>
          {error ? (
            <p className="rounded-md bg-destructive/10 px-3 py-2 text-xs text-destructive">
              {error}
            </p>
          ) : null}
          <div className="flex justify-end gap-2">
            <Button
              type="button"
              variant="outline"
              disabled={submitting}
              onClick={() => onOpenChange(false)}
            >
              Cancel
            </Button>
            <Button type="submit" disabled={submitting || due <= 0}>
              {submitting ? 'Posting…' : 'Record payment'}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  )
}
