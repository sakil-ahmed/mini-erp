import { z } from 'zod'

export const purchaseLineSchema = z.object({
  product_id: z.string().uuid('Select a product'),
  product_label: z.string(),
  qty: z.number().gt(0, 'Qty must be > 0'),
  unit_cost: z.number().min(0, 'Cost must be ≥ 0'),
})

export const purchaseFormSchema = z
  .object({
    supplier_id: z.string().uuid('Select a supplier'),
    doc_date: z.string().min(1, 'Date is required'),
    discount: z.number().min(0, 'Discount must be ≥ 0'),
    amount_paid: z.number().min(0, 'Paid must be ≥ 0'),
    items: z.array(purchaseLineSchema).min(1, 'Add at least one line'),
  })
  .superRefine((data, ctx) => {
    const subtotal = data.items.reduce(
      (sum, line) => sum + roundMoney(line.qty * line.unit_cost),
      0,
    )
    const total = roundMoney(subtotal - data.discount)
    if (data.discount > subtotal) {
      ctx.addIssue({
        code: 'custom',
        path: ['discount'],
        message: 'Discount cannot exceed subtotal',
      })
    }
    if (total <= 0) {
      ctx.addIssue({
        code: 'custom',
        path: ['discount'],
        message: 'Total must be greater than zero',
      })
    }
    if (data.amount_paid > total && total > 0) {
      ctx.addIssue({
        code: 'custom',
        path: ['amount_paid'],
        message: 'Paid cannot exceed total',
      })
    }
  })

export type PurchaseFormValues = z.infer<typeof purchaseFormSchema>
export type PurchaseLineValues = z.infer<typeof purchaseLineSchema>

export const paySupplierSchema = z.object({
  amount: z.number().gt(0, 'Amount must be > 0'),
  method: z.enum(['cash', 'bank']),
})

export type PaySupplierValues = z.infer<typeof paySupplierSchema>

export function roundMoney(n: number) {
  return Math.round((n + Number.EPSILON) * 100) / 100
}

export function calcPurchaseTotals(
  items: Array<{ qty: number; unit_cost: number }>,
  discount: number,
  paid: number,
) {
  const subtotal = roundMoney(
    items.reduce((sum, line) => sum + roundMoney(line.qty * line.unit_cost), 0),
  )
  const safeDiscount = Number.isFinite(discount) ? discount : 0
  const safePaid = Number.isFinite(paid) ? paid : 0
  const total = roundMoney(Math.max(0, subtotal - safeDiscount))
  const due = roundMoney(Math.max(0, total - safePaid))
  return { subtotal, total, due }
}
