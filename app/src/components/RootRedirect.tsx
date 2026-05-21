import { useState, useEffect } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuthStore } from '@/stores/useAuthStore'
import { Loader2 } from 'lucide-react'

export default function RootRedirect() {
  const { token } = useAuthStore()
  const [setupRequired, setSetupRequired] = useState<boolean | null>(null)

  useEffect(() => {
    // If already authenticated, no need to check setup
    if (token) {
      setSetupRequired(false)
      return
    }

    fetch(`${import.meta.env.VITE_API_BASE_URL || ''}/api/setup`)
      .then(r => r.json())
      .then(data => setSetupRequired(data.required))
      .catch(() => setSetupRequired(false))
  }, [token])

  if (setupRequired === null) {
    return (
      <div className="min-h-screen bg-[#0B0B0D] flex items-center justify-center">
        <Loader2 size={20} className="text-rail-purple animate-spin" />
      </div>
    )
  }

  if (token) {
    return <Navigate to="/dashboard" replace />
  }

  if (setupRequired) {
    return <Navigate to="/setup" replace />
  }

  return <Navigate to="/login" replace />
}
