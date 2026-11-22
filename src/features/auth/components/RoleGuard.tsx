import type { ReactNode } from 'react'
import { Navigate } from 'react-router-dom'
import { useRole } from '@/features/auth/hooks/useRole'
import type { AppRole } from '@/features/auth/types'

type RoleGuardProps = {
  allow: readonly AppRole[]
  children: ReactNode
  fallbackTo?: string
}

export function RoleGuard({
  allow,
  children,
  fallbackTo = '/',
}: RoleGuardProps) {
  const { canAccess, isLoading } = useRole()

  if (isLoading) {
    return (
      <div className="flex min-h-40 items-center justify-center text-sm text-muted-foreground">
        Checking access…
      </div>
    )
  }

  if (!canAccess(allow)) {
    return <Navigate to={fallbackTo} replace />
  }

  return children
}
