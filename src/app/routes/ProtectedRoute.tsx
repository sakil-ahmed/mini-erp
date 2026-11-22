import { useEffect, useState } from 'react'
import { Navigate, Outlet, useLocation } from 'react-router-dom'
import type { Session } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase'

const authBypass = import.meta.env.VITE_AUTH_BYPASS === 'true'

/**
 * Scaffolding for authenticated routes.
 * Redirects to /login when there is no Supabase session.
 * Set VITE_AUTH_BYPASS=true in .env to preview the app shell without auth.
 */
export function ProtectedRoute() {
  const location = useLocation()
  const [session, setSession] = useState<Session | null | undefined>(
    authBypass ? null : undefined,
  )

  useEffect(() => {
    if (authBypass) {
      return
    }

    let mounted = true

    void supabase.auth.getSession().then(({ data }) => {
      if (mounted) {
        setSession(data.session)
      }
    })

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession)
    })

    return () => {
      mounted = false
      subscription.unsubscribe()
    }
  }, [])

  if (authBypass) {
    return <Outlet />
  }

  if (session === undefined) {
    return (
      <div className="flex min-h-svh items-center justify-center text-sm text-muted-foreground">
        Loading…
      </div>
    )
  }

  if (!session) {
    return <Navigate to="/login" replace state={{ from: location }} />
  }

  return <Outlet />
}
