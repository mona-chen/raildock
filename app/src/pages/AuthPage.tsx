import { useState, useEffect } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { LogIn, UserPlus, Loader2, Zap } from 'lucide-react'
import { useAuthStore } from '@/stores/useAuthStore'
import { authApi } from '@/lib/api'

export default function AuthPage() {
  const navigate = useNavigate()
  const location = useLocation()
  const isSetup = location.pathname === '/setup'
  const { setToken, setUser, isAuthenticated } = useAuthStore()

  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [name, setName] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const [setupRequired, setSetupRequired] = useState(false)

  // Redirect if already authenticated
  useEffect(() => {
    if (isAuthenticated()) {
      navigate('/dashboard', { replace: true })
    }
  }, [])

  // Check if setup is required
  useEffect(() => {
    if (!isSetup) {
      fetch(`${import.meta.env.VITE_API_BASE_URL || ''}/api/setup`)
        .then(r => r.json())
        .then(data => {
          if (data.required) {
            setSetupRequired(true)
            navigate('/setup', { replace: true })
          }
        })
        .catch(() => {
          // Backend not reachable — assume mock mode, no redirect needed
        })
    }
  }, [isSetup, navigate])

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')
    setLoading(true)
    try {
      const data = await authApi.login(email, password)
      setToken(data.token)
      setUser(data.user)
      navigate('/dashboard')
    } catch (err: any) {
      setError(err.message || 'Invalid credentials')
    } finally {
      setLoading(false)
    }
  }

  const handleSetup = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')
    setLoading(true)
    try {
      const data = await authApi.register({ name, email, password })
      setToken(data.token)
      setUser(data.user)
      navigate('/dashboard')
    } catch (err: any) {
      setError(err.message || 'Setup failed')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen bg-[#0B0B0D] flex items-center justify-center px-4">
      <div className="w-full max-w-sm">
        {/* Logo */}
        <div className="flex items-center justify-center gap-2 mb-8">
          <div className="w-8 h-8 rounded-lg bg-[rgba(139,92,246,0.2)] flex items-center justify-center border border-[rgba(139,92,246,0.3)]">
            <Zap size={16} className="text-rail-purple" />
          </div>
          <span className="text-lg font-bold text-white">RailDock</span>
        </div>

        <div className="bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.06)] rounded-xl p-6">
          <h1 className="text-base font-semibold text-white mb-1">
            {isSetup ? 'Create Admin Account' : 'Sign In'}
          </h1>
          <p className="text-xs text-[#4A4A55] mb-5">
            {isSetup
              ? 'Set up your first admin user to get started.'
              : 'Enter your credentials to access the dashboard.'}
          </p>

          {error && (
            <div className="mb-4 px-3 py-2 bg-red-500/10 border border-red-500/20 rounded-lg text-xs text-red-400">
              {error}
            </div>
          )}

          <form onSubmit={isSetup ? handleSetup : handleLogin} className="space-y-3">
            {isSetup && (
              <div>
                <label className="block text-[10px] text-[#4A4A55] uppercase tracking-wider font-medium mb-1.5">
                  Full Name
                </label>
                <input
                  type="text"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  required
                  className="w-full h-9 px-3 bg-[rgba(255,255,255,0.03)] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white placeholder-[#4A4A55] focus:outline-none focus:border-[rgba(139,92,246,0.4)] transition-colors"
                  placeholder="Admin User"
                />
              </div>
            )}
            <div>
              <label className="block text-[10px] text-[#4A4A55] uppercase tracking-wider font-medium mb-1.5">
                Email
              </label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                className="w-full h-9 px-3 bg-[rgba(255,255,255,0.03)] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white placeholder-[#4A4A55] focus:outline-none focus:border-[rgba(139,92,246,0.4)] transition-colors"
                placeholder="admin@example.com"
              />
            </div>
            <div>
              <label className="block text-[10px] text-[#4A4A55] uppercase tracking-wider font-medium mb-1.5">
                Password
              </label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                minLength={6}
                className="w-full h-9 px-3 bg-[rgba(255,255,255,0.03)] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white placeholder-[#4A4A55] focus:outline-none focus:border-[rgba(139,92,246,0.4)] transition-colors"
                placeholder="••••••••"
              />
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full h-9 flex items-center justify-center gap-2 bg-rail-purple text-white text-sm font-medium rounded-lg hover:bg-rail-purple-dark transition-all disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {loading ? (
                <Loader2 size={14} className="animate-spin" />
              ) : isSetup ? (
                <>
                  <UserPlus size={14} /> Create Account
                </>
              ) : (
                <>
                  <LogIn size={14} /> Sign In
                </>
              )}
            </button>
          </form>
        </div>

        <p className="text-center text-[10px] text-[#4A4A55] mt-4">
          {isSetup ? 'Already have an account? ' : 'Need to set up? '}
          {isSetup ? (
            <button onClick={() => navigate('/login')} className="text-rail-purple hover:underline">
              Sign in
            </button>
          ) : setupRequired ? (
            <button onClick={() => navigate('/setup')} className="text-rail-purple hover:underline">
              Create admin account
            </button>
          ) : null}
        </p>
      </div>
    </div>
  )
}
