import { z } from 'zod'

export const stockAdjustSchema = z
  .object({
    qty_delta: z.number().refine((n) => Number.isFinite(n) && n !== 0, {
      message: 'Qty change must be non-zero',
    }),
    unit_cost: z.number().min(0).optional(),
    note: z.string().max(200).optional(),
  })
  .superRefine((data, ctx) => {
    if (data.qty_delta > 0 && data.unit_cost === undefined) {
      // UI may leave blank to use avg; RPC enforces when stock is 0
      return
    }
    if (data.qty_delta < 0 && data.unit_cost !== undefined) {
      ctx.addIssue({
        code: 'custom',
        path: ['unit_cost'],
        message: 'Unit cost is only used for stock increases',
      })
    }
  })

export type StockAdjustValues = z.infer<typeof stockAdjustSchema>
