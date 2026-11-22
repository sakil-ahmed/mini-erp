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
  stockAdjustSchema,
  type StockAdjustValues,
} from '@/features/inventory/schemas'
import { formatMoney, formatQty } from '@/shared/lib/money'
import type { StockLevelRow } from '@/features/inventory/types'

type AdjustStockDialogProps = {
  open: boolean
  product: StockLevelRow | null
  submitting?: boolean
  error?: string | null
  onOpenChange: (open: boolean) => void
  onSubmit: (values: StockAdjustValues) => void
}

export function AdjustStockDialog({
  open,
  product,
  submitting,
  error,
  onOpenChange,
  onSubmit,
}: AdjustStockDialogProps) {
  const {
    register,
    handleSubmit,
    watch,
    formState: { errors },
  } = useForm<StockAdjustValues>({
    resolver: zodResolver(stockAdjustSchema),
    values: {
      qty_delta: 1,
      unit_cost: product?.avg_cost,
      note: '',
    },
  })

  const qtyDelta = watch('qty_delta')

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-sm">
        <DialogHeader>
          <DialogTitle>Adjust stock</DialogTitle>
        </DialogHeader>
        {product ? (
          <p className="text-xs text-muted-foreground">
            {product.sku} · {product.name} — on hand{' '}
            {formatQty(product.stock_qty)} @ {formatMoney(product.avg_cost)}.
            Positive adds stock; negative removes at avg cost.
          </p>
        ) : null}
        <form
          className="space-y-4"
          onSubmit={handleSubmit(onSubmit)}
          noValidate
        >
          <div className="space-y-1.5">
            <Label htmlFor="adj-qty">Qty change</Label>
            <Input
              id="adj-qty"
              type="number"
              step="0.001"
              disabled={submitting}
              {...register('qty_delta', { valueAsNumber: true })}
            />
            {errors.qty_delta ? (
              <p className="text-xs text-destructive">
                {errors.qty_delta.message}
              </p>
            ) : null}
          </div>
          {Number.isFinite(qtyDelta) && qtyDelta > 0 ? (
            <div className="space-y-1.5">
              <Label htmlFor="adj-cost">Unit cost (optional)</Label>
              <Input
                id="adj-cost"
                type="number"
                step="0.01"
                min="0"
                disabled={submitting}
                {...register('unit_cost', { valueAsNumber: true })}
              />
              <p className="text-[11px] text-muted-foreground">
                Defaults to current avg cost. Required if on-hand is zero.
              </p>
              {errors.unit_cost ? (
                <p className="text-xs text-destructive">
                  {errors.unit_cost.message}
                </p>
              ) : null}
            </div>
          ) : null}
          <div className="space-y-1.5">
            <Label htmlFor="adj-note">Note</Label>
            <Input
              id="adj-note"
              disabled={submitting}
              placeholder="Cycle count / damage / …"
              {...register('note')}
            />
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
            <Button type="submit" disabled={submitting || !product}>
              {submitting ? 'Posting…' : 'Post adjustment'}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  )
}
