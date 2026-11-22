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
  paySupplierSchema,
  type PaySupplierValues,
} from '@/features/purchases/schemas'
import { formatMoney } from '@/shared/lib/money'

type PaySupplierDialogProps = {
  open: boolean
  due: number
  submitting?: boolean
  error?: string | null
  onOpenChange: (open: boolean) => void
  onSubmit: (values: PaySupplierValues) => void
}

export function PaySupplierDialog({
  open,
  due,
  submitting,
  error,
  onOpenChange,
  onSubmit,
}: PaySupplierDialogProps) {
  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<PaySupplierValues>({
    resolver: zodResolver(paySupplierSchema),
    values: {
      amount: due,
      method: 'cash',
    },
  })

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-sm">
        <DialogHeader>
          <DialogTitle>Pay supplier</DialogTitle>
        </DialogHeader>
        <p className="text-xs text-muted-foreground">
          Outstanding on this purchase: {formatMoney(due)}. Payments allocate
          FIFO to the supplier&apos;s open purchases.
        </p>
        <form
          className="space-y-4"
          onSubmit={handleSubmit(onSubmit)}
          noValidate
        >
          <div className="space-y-1.5">
            <Label htmlFor="ap-amount">Amount</Label>
            <Input
              id="ap-amount"
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
            <Label htmlFor="ap-method">Method</Label>
            <select
              id="ap-method"
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
