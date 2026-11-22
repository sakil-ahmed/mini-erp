import { useAuth } from '@/features/auth/hooks/useAuth'
import { roleCanAccess } from '@/features/auth/lib/access'
import type { AppRole } from '@/features/auth/types'

export function useRole() {
  const { profile, isLoading, isProfileLoading } = useAuth()
  const role = profile?.role ?? null

  return {
    role,
    profile,
    isLoading: isLoading || isProfileLoading,
    isAdmin: role === 'admin',
    hasRole: (...roles: AppRole[]) =>
      role !== null && (role === 'admin' || roles.includes(role)),
    canAccess: (allowed: readonly AppRole[]) => roleCanAccess(role, allowed),
  }
}
