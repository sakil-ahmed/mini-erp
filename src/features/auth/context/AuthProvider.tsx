import {
  useCallback,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react'
import type { Session, User } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase'
import { AuthContext, type AuthContextValue } from '@/features/auth/context/auth-context'
import { isAppRole, type Profile } from '@/features/auth/types'

async function fetchProfile(userId: string): Promise<Profile> {
  const { data, error } = await supabase
    .from('profiles')
    .select('id, full_name, role')
    .eq('id', userId)
    .single()

  if (error) {
    throw new Error(error.message)
  }

  if (!data || typeof data.role !== 'string' || !isAppRole(data.role)) {
    throw new Error('Profile is missing or has an invalid role')
  }

  return {
    id: data.id as string,
    full_name: (data.full_name as string | null) ?? null,
    role: data.role,
  }
}

type AuthProviderProps = {
  children: ReactNode
}

export function AuthProvider({ children }: AuthProviderProps) {
  const [session, setSession] = useState<Session | null>(null)
  const [user, setUser] = useState<User | null>(null)
  const [profile, setProfile] = useState<Profile | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [isProfileLoading, setIsProfileLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const loadProfile = useCallback(async (nextUser: User | null) => {
    if (!nextUser) {
      setProfile(null)
      setIsProfileLoading(false)
      return
    }

    setIsProfileLoading(true)
    try {
      const nextProfile = await fetchProfile(nextUser.id)
      setProfile(nextProfile)
      setError(null)
    } catch (err) {
      setProfile(null)
      setError(err instanceof Error ? err.message : 'Failed to load profile')
    } finally {
      setIsProfileLoading(false)
    }
  }, [])

  useEffect(() => {
    let mounted = true

    void supabase.auth.getSession().then(({ data, error: sessionError }) => {
      if (!mounted) return

      if (sessionError) {
        setError(sessionError.message)
        setSession(null)
        setUser(null)
        setProfile(null)
        setIsLoading(false)
        return
      }

      setSession(data.session)
      setUser(data.session?.user ?? null)
      setIsLoading(false)

      void loadProfile(data.session?.user ?? null)
    })

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession)
      setUser(nextSession?.user ?? null)
      void loadProfile(nextSession?.user ?? null)
    })

    return () => {
      mounted = false
      subscription.unsubscribe()
    }
  }, [loadProfile])

  const signIn = useCallback(async (email: string, password: string) => {
    setError(null)
    const { error: signInError } = await supabase.auth.signInWithPassword({
      email,
      password,
    })
    if (signInError) {
      setError(signInError.message)
      throw signInError
    }
  }, [])

  const signOut = useCallback(async () => {
    setError(null)
    const { error: signOutError } = await supabase.auth.signOut()
    if (signOutError) {
      setError(signOutError.message)
      throw signOutError
    }
    setProfile(null)
  }, [])

  const clearError = useCallback(() => setError(null), [])

  const value = useMemo<AuthContextValue>(
    () => ({
      session,
      user,
      profile,
      isLoading,
      isProfileLoading,
      error,
      signIn,
      signOut,
      clearError,
    }),
    [
      session,
      user,
      profile,
      isLoading,
      isProfileLoading,
      error,
      signIn,
      signOut,
      clearError,
    ],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
