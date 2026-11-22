import { z } from 'zod'

export const partyFormSchema = z.object({
  name: z.string().trim().min(1, 'Name is required').max(120),
  email: z
    .string()
    .trim()
    .refine(
      (v) => v === '' || z.string().email().safeParse(v).success,
      'Enter a valid email',
    ),
  phone: z.string().trim().max(32),
  is_active: z.boolean(),
})

export type PartyFormValues = z.infer<typeof partyFormSchema>
