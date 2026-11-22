export const APP_ROLES = ['admin', 'sales', 'purchase', 'accountant'] as const

export type AppRole = (typeof APP_ROLES)[number]

export type Profile = {
  id: string
  full_name: string | null
  role: AppRole
}

export function isAppRole(value: string): value is AppRole {
  return (APP_ROLES as readonly string[]).includes(value)
}
