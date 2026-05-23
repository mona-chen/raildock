import { Navigate, useLocation } from 'react-router-dom'
import { useAuthStore } from '@/stores/useAuthStore'
import { useEffect } from 'react'
import { authApi } from '@/lib/api'

export default function AuthGuard({ children }: { children: React.ReactNode }) {
  const { token, user, setUser, setLoading, isLoading, logout } = useAuthStore()
  const location = useLocation()

  // Verify token on mount
  useEffect(() => {
    if (!token) {
      setLoading(false)
      return
    }

    authApi.me()
      .then((me) => {
        if (me) {
          setUser(me)
        } else {
          logout()
        }
      })
      .catch((err) => {
        // Only log out on 401 Unauthorized.
        // 429 (rate limit), 500, or network errors should keep the session.
        if (err instanceof Error && err.message.includes('401')) {
          logout()
        }
      })
      .finally(() => setLoading(false))
  }, [token])

  if (isLoading) {
    return (
      <div className="min-h-screen bg-[#0B0B0D] flex items-center justify-center">
        <div className="w-6 h-6 border-2 border-rail-purple border-t-transparent rounded-full animate-spin" />
      </div>
    )
  }

  if (!token) {
    return <Navigate to="/login" state={{ from: location }} replace />
  }

  return <>{children}</>
}
