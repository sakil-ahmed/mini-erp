import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
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
import { useRole } from '@/features/auth'
import {
  useReceivePaymentMutation,
  useSaleQuery,
  useVoidSaleMutation,
} from '@/features/sales/api'
import { ReceivePaymentDialog } from '@/features/sales/components/ReceivePaymentDialog'
import { SaleTotals } from '@/features/sales/components/SaleTotals'
import type { ReceivePaymentValues } from '@/features/sales/schemas'
import { formatMoney, formatQty } from '@/shared/lib/money'

export function SaleDetailPage() {
  const { id } = useParams<{ id: string }>()
  const { isAdmin, hasRole } = useRole()
  const showProfit = isAdmin || hasRole('accountant')
  const canReceive = isAdmin || hasRole('accountant')

  const detail = useSaleQuery(id)
  const voidSale = useVoidSaleMutation()
  const receivePayment = useReceivePaymentMutation()

  const [voidError, setVoidError] = useState<string | null>(null)
  const [payOpen, setPayOpen] = useState(false)
  const [payError, setPayError] = useState<string | null>(null)

  if (detail.isLoading) {
    return <p className="text-sm text-muted-foreground">Loading sale…</p>
  }

  if (detail.isError || !detail.data) {
    return (
      <div className="space-y-3">
        <p className="text-sm text-destructive">
          {detail.error instanceof Error
            ? detail.error.message
            : 'Sale not found'}
        </p>
        <Button type="button" variant="outline" asChild>
          <Link to="/sales">Back to list</Link>
        </Button>
      </div>
    )
  }

  const sale = detail.data
  const due = Math.max(0, sale.total - sale.amount_paid)

  const onVoid = async () => {
    if (!id) return
    const ok = window.confirm(
      `Void sale ${sale.doc_number}? This restores stock and reverses journals.`,
    )
    if (!ok) return
    setVoidError(null)
    try {
      await voidSale.mutateAsync(id)
    } catch (err) {
      setVoidError(err instanceof Error ? err.message : 'Void failed')
    }
  }

  const onReceive = async (values: ReceivePaymentValues) => {
    setPayError(null)
    if (values.amount > due) {
      setPayError(`Amount cannot exceed due (${due.toFixed(2)})`)
      return
    }
    try {
      await receivePayment.mutateAsync({
        customerId: sale.customer_id,
        amount: values.amount,
        method: values.method,
      })
      setPayOpen(false)
      await detail.refetch()
    } catch (err) {
      setPayError(err instanceof Error ? err.message : 'Payment failed')
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="flex items-center gap-2">
            <h1 className="text-2xl font-semibold tracking-tight">
              {sale.doc_number}
            </h1>
            <Badge variant={sale.status === 'posted' ? 'default' : 'secondary'}>
              {sale.status}
            </Badge>
          </div>
          <p className="text-sm text-muted-foreground">
            {sale.doc_date} · {sale.customer_name}
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button type="button" variant="outline" asChild>
            <Link to="/sales">Back</Link>
          </Button>
          {canReceive && sale.status === 'posted' && due > 0 ? (
            <Button
              type="button"
              onClick={() => {
                setPayError(null)
                setPayOpen(true)
              }}
            >
              Receive payment
            </Button>
          ) : null}
          {isAdmin && sale.status === 'posted' ? (
            <Button
              type="button"
              variant="destructive"
              disabled={voidSale.isPending}
              onClick={() => {
                void onVoid()
              }}
            >
              {voidSale.isPending ? 'Voiding…' : 'Void'}
            </Button>
          ) : null}
        </div>
      </div>

      {voidError ? (
        <p className="rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">
          {voidError}
        </p>
      ) : null}

      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>SKU</TableHead>
              <TableHead>Product</TableHead>
              <TableHead className="text-right">Qty</TableHead>
              <TableHead className="text-right">Price</TableHead>
              {showProfit ? (
                <TableHead className="text-right">Cost</TableHead>
              ) : null}
              <TableHead className="text-right">Line total</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {sale.items.map((item) => (
              <TableRow key={item.id}>
                <TableCell>{item.product_sku}</TableCell>
                <TableCell>{item.product_name}</TableCell>
                <TableCell className="text-right">
                  {formatQty(item.qty)}
                </TableCell>
                <TableCell className="text-right">
                  {formatMoney(item.unit_price)}
                </TableCell>
                {showProfit ? (
                  <TableCell className="text-right">
                    {formatMoney(item.unit_cost)}
                  </TableCell>
                ) : null}
                <TableCell className="text-right">
                  {formatMoney(item.line_total)}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>

      <div className="max-w-sm">
        <SaleTotals
          subtotal={sale.subtotal}
          discount={sale.discount}
          total={sale.total}
          paid={sale.amount_paid}
          due={due}
          cogs={sale.cogs}
          profit={sale.profit}
          showProfit={showProfit}
        />
      </div>

      <ReceivePaymentDialog
        open={payOpen}
        due={due}
        submitting={receivePayment.isPending}
        error={payError}
        onOpenChange={setPayOpen}
        onSubmit={(values) => {
          void onReceive(values)
        }}
      />
    </div>
  )
}
