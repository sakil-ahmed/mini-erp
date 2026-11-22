import type { AppRole } from '@/features/auth/types'

/** Nav / route access matrix aligned with RLS read rules. */
export const ROUTE_ROLES = {
  dashboard: ['admin', 'sales', 'purchase', 'accountant'],
  sales: ['admin', 'sales', 'accountant'],
  purchases: ['admin', 'purchase', 'accountant'],
  inventory: ['admin', 'sales', 'purchase', 'accountant'],
  accounts: ['admin', 'accountant'],
} as const satisfies Record<string, readonly AppRole[]>

export type RouteKey = keyof typeof ROUTE_ROLES

export function roleCanAccess(
  role: AppRole | null | undefined,
  allowed: readonly AppRole[],
): boolean {
  if (!role) return false
  if (role === 'admin') return true
  return allowed.includes(role)
}
