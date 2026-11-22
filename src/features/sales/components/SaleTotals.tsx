import { formatMoney } from '@/shared/lib/money'

type SaleTotalsProps = {
  subtotal: number
  discount: number
  total: number
  paid: number
  due: number
  cogs?: number
  profit?: number
  showProfit?: boolean
}

export function SaleTotals({
  subtotal,
  discount,
  total,
  paid,
  due,
  cogs,
  profit,
  showProfit,
}: SaleTotalsProps) {
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
      {showProfit ? (
        <>
          <div className="my-2 border-t" />
          <div className="flex justify-between">
            <dt className="text-muted-foreground">COGS</dt>
            <dd>{formatMoney(cogs ?? 0)}</dd>
          </div>
          <div className="flex justify-between font-semibold">
            <dt>Profit</dt>
            <dd>{formatMoney(profit ?? 0)}</dd>
          </div>
        </>
      ) : null}
    </dl>
  )
}
