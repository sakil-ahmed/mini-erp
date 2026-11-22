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
  usePurchaseQuery,
  useVoidPurchaseMutation,
} from '@/features/purchases/api'
import { PurchaseTotals } from '@/features/purchases/components/PurchaseTotals'
import { formatMoney, formatQty } from '@/shared/lib/money'

export function PurchaseDetailPage() {
  const { id } = useParams<{ id: string }>()
  const { isAdmin } = useRole()
  const detail = usePurchaseQuery(id)
  const voidPurchase = useVoidPurchaseMutation()
  const [voidError, setVoidError] = useState<string | null>(null)

  if (detail.isLoading) {
    return <p className="text-sm text-muted-foreground">Loading purchase…</p>
  }

  if (detail.isError || !detail.data) {
    return (
      <div className="space-y-3">
        <p className="text-sm text-destructive">
          {detail.error instanceof Error
            ? detail.error.message
            : 'Purchase not found'}
        </p>
        <Button type="button" variant="outline" asChild>
          <Link to="/purchases">Back to list</Link>
        </Button>
      </div>
    )
  }

  const purchase = detail.data
  const due = Math.max(0, purchase.total - purchase.amount_paid)

  const onVoid = async () => {
    if (!id) return
    const ok = window.confirm(
      `Void purchase ${purchase.doc_number}? This reverses stock and journal entries.`,
    )
    if (!ok) return
    setVoidError(null)
    try {
      await voidPurchase.mutateAsync(id)
    } catch (err) {
      setVoidError(err instanceof Error ? err.message : 'Void failed')
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="flex items-center gap-2">
            <h1 className="text-2xl font-semibold tracking-tight">
              {purchase.doc_number}
            </h1>
            <Badge
              variant={purchase.status === 'posted' ? 'default' : 'secondary'}
            >
              {purchase.status}
            </Badge>
          </div>
          <p className="text-sm text-muted-foreground">
            {purchase.doc_date} · {purchase.supplier_name}
          </p>
        </div>
        <div className="flex gap-2">
          <Button type="button" variant="outline" asChild>
            <Link to="/purchases">Back</Link>
          </Button>
          {isAdmin && purchase.status === 'posted' ? (
            <Button
              type="button"
              variant="destructive"
              disabled={voidPurchase.isPending}
              onClick={() => {
                void onVoid()
              }}
            >
              {voidPurchase.isPending ? 'Voiding…' : 'Void'}
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
              <TableHead className="text-right">Unit cost</TableHead>
              <TableHead className="text-right">Line total</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {purchase.items.map((item) => (
              <TableRow key={item.id}>
                <TableCell>{item.product_sku}</TableCell>
                <TableCell>{item.product_name}</TableCell>
                <TableCell className="text-right">
                  {formatQty(item.qty)}
                </TableCell>
                <TableCell className="text-right">
                  {formatMoney(item.unit_cost)}
                </TableCell>
                <TableCell className="text-right">
                  {formatMoney(item.line_total)}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>

      <div className="max-w-sm">
        <PurchaseTotals
          subtotal={purchase.subtotal}
          discount={purchase.discount}
          total={purchase.total}
          paid={purchase.amount_paid}
          due={due}
        />
      </div>
    </div>
  )
}
