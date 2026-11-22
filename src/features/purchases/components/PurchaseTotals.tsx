import { formatMoney } from '@/shared/lib/money'

type PurchaseTotalsProps = {
  subtotal: number
  discount: number
  total: number
  paid: number
  due: number
}

export function PurchaseTotals({
  subtotal,
  discount,
  total,
  paid,
  due,
}: PurchaseTotalsProps) {
  return (
    <dl className="space-y-1 rounded-lg border p-3 text-sm">
      <div className="flex justify-between">
        <dt className="text-muted-foreground">Subtotal</dt>
        <dd>{formatMoney(subtotal)}</dd>
      </div>
      <div className="flex justify-between">
        <dt className="text-muted-foreground">Discount</dt>
        <dd>{formatMoney(discount)}</dd>
      </div>
      <div className="flex justify-between font-medium">
        <dt>Total</dt>
        <dd>{formatMoney(total)}</dd>
      </div>
      <div className="flex justify-between">
        <dt className="text-muted-foreground">Paid</dt>
        <dd>{formatMoney(paid)}</dd>
      </div>
      <div className="flex justify-between text-base font-semibold">
        <dt>Due</dt>
        <dd>{formatMoney(due)}</dd>
      </div>
    </dl>
  )
}
