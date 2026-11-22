import { z } from 'zod'

export const saleLineSchema = z.object({
  product_id: z.string().uuid('Select a product'),
  product_label: z.string(),
  stock_qty: z.number().min(0),
  qty: z.number().gt(0, 'Qty must be > 0'),
  unit_price: z.number().min(0, 'Price must be ≥ 0'),
})

export const saleFormSchema = z
  .object({
    customer_id: z.string().uuid('Select a customer'),
    doc_date: z.string().min(1, 'Date is required'),
    discount: z.number().min(0, 'Discount must be ≥ 0'),
    amount_paid: z.number().min(0, 'Paid must be ≥ 0'),
    items: z.array(saleLineSchema).min(1, 'Add at least one line'),
  })
  .superRefine((data, ctx) => {
    const subtotal = data.items.reduce(
      (sum, line) => sum + roundMoney(line.qty * line.unit_price),
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

    // Sum qty per product — UI block; DB still enforces stock.
    const used = new Map<string, { qty: number; stock: number; label: string }>()
    data.items.forEach((line, index) => {
      const prev = used.get(line.product_id)
      const qty = (prev?.qty ?? 0) + (Number.isFinite(line.qty) ? line.qty : 0)
      used.set(line.product_id, {
        qty,
        stock: line.stock_qty,
        label: line.product_label,
      })
      if (Number.isFinite(line.qty) && line.qty > line.stock_qty) {
        ctx.addIssue({
          code: 'custom',
          path: ['items', index, 'qty'],
          message: `Only ${line.stock_qty} in stock`,
        })
      }
    })
    for (const [, agg] of used) {
      if (agg.qty > agg.stock) {
        ctx.addIssue({
          code: 'custom',
          path: ['items'],
          message: `Insufficient stock for ${agg.label} (need ${agg.qty}, have ${agg.stock})`,
        })
      }
    }
  })

export type SaleFormValues = z.infer<typeof saleFormSchema>
export type SaleLineValues = z.infer<typeof saleLineSchema>

export function roundMoney(n: number) {
  return Math.round((n + Number.EPSILON) * 100) / 100
}

export function calcSaleTotals(
  items: Array<{ qty: number; unit_price: number }>,
  discount: number,
  paid: number,
) {
  const subtotal = roundMoney(
    items.reduce(
      (sum, line) => sum + roundMoney(line.qty * line.unit_price),
      0,
    ),
  )
  const safeDiscount = Number.isFinite(discount) ? discount : 0
  const safePaid = Number.isFinite(paid) ? paid : 0
  const total = roundMoney(Math.max(0, subtotal - safeDiscount))
  const due = roundMoney(Math.max(0, total - safePaid))
  return { subtotal, total, due }
}

export const receivePaymentSchema = z.object({
  amount: z.number().gt(0, 'Amount must be > 0'),
  method: z.enum(['cash', 'bank']),
})

export type ReceivePaymentValues = z.infer<typeof receivePaymentSchema>
