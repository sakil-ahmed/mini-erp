import { z } from 'zod'

export const productFormSchema = z.object({
  sku: z.string().trim().min(1, 'SKU is required').max(64),
  name: z.string().trim().min(1, 'Name is required').max(120),
  unit: z.string().trim().min(1, 'Unit is required').max(32),
  sale_price: z.number().min(0, 'Must be ≥ 0'),
  reorder_level: z.number().min(0, 'Must be ≥ 0'),
  is_active: z.boolean(),
})

export type ProductFormValues = z.infer<typeof productFormSchema>
