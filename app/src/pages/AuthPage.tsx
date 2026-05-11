import { useState, useEffect, useRef } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { LogIn, UserPlus, Loader2, Zap, Eye, EyeOff, CheckCircle2, XCircle, AlertCircle } from 'lucide-react'
import { useAuthStore } from '@/stores/useAuthStore'
import { authApi } from '@/lib/api'
import { toast } from 'sonner'

function getPasswordStrength(password: string): { score: number; label: string; color: string } {
  let score = 0
  if (password.length >= 8) score++
  if (password.length >= 12) score++
  if (/[A-Z]/.test(password)) score++
  if (/[0-9]/.test(password)) score++
  if (/[^A-Za-z0-9]/.test(password)) score++

  const levels = [
    { label: 'Too weak', color: '#ef4444' },
    { label: 'Weak', color: '#f97316' },
    { label: 'Fair', color: '#eab308' },
    { label: 'Good', color: '#22c55e' },
    { label: 'Strong', color: '#22c55e' },
    { label: 'Very strong', color: '#8b5cf6' },
  ]
  return { score, label: levels[score].label, color: levels[score].color }
}

export default function AuthPage() {
  const navigate = useNavigate()
  const location = useLocation()
  const isSetup = location.pathname === '/setup'
  const { setToken, setUser, isAuthenticated } = useAuthStore()

  const emailRef = useRef<HTMLInputElement>(null)
  const passwordRef = useRef<HTMLInputElement>(null)
  const confirmPasswordRef = useRef<HTMLInputElement>(null)
  const nameRef = useRef<HTMLInputElement>(null)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [name, setName] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const [setupRequired, setSetupRequired] = useState(false)

  const strength = getPasswordStrength(password)
  const passwordsMatch = !isSetup || password === confirmPassword || confirmPassword === ''

  // Redirect if already authenticated
  useEffect(() => {
    if (isAuthenticated()) {
      navigate('/dashboard', { replace: true })
    }
  }, [])

  // Check if setup is required — run on both /login and /setup
  useEffect(() => {
    fetch(`${import.meta.env.VITE_API_BASE_URL || ''}/api/setup`)
      .then(r => r.json())
      .then(data => {
        setSetupRequired(data.required)
        if (data.required && !isSetup) {
          navigate('/setup', { replace: true })
        }
      })
      .catch(() => {
        // Backend not reachable — assume mock mode, no redirect needed
      })
  }, [isSetup, navigate])

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')
    setLoading(true)
    // Read values directly from refs to handle password-manager autofill
    // which may not trigger React onChange events
    const emailValue = emailRef.current?.value || email
    const passwordValue = passwordRef.current?.value || password
    try {
      const data = await authApi.login(emailValue, passwordValue)
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
    const nameValue = nameRef.current?.value || name
    const emailValue = emailRef.current?.value || email
    const passwordValue = passwordRef.current?.value || password
    const confirmValue = confirmPasswordRef.current?.value || confirmPassword

    if (passwordValue !== confirmValue) {
      setError('Passwords do not match')
      return
    }
    if (passwordValue.length < 8) {
      setError('Password must be at least 8 characters')
      return
    }

    setLoading(true)
    try {
      const data = await authApi.register({ name: nameValue, email: emailValue, password: passwordValue })
      setToken(data.token)
      setUser(data.user)
      toast.success(`Welcome to RailDock, ${nameValue}!`)
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
            <div className="mb-4 px-3 py-2 bg-red-500/10 border border-red-500/20 rounded-lg text-xs text-red-400 flex items-center gap-2">
              <AlertCircle size={14} />
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
                  ref={nameRef}
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
                ref={emailRef}
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
              <div className="relative">
                <input
                  ref={passwordRef}
                  type={showPassword ? 'text' : 'password'}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                  minLength={6}
                  className="w-full h-9 px-3 pr-9 bg-[rgba(255,255,255,0.03)] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white placeholder-[#4A4A55] focus:outline-none focus:border-[rgba(139,92,246,0.4)] transition-colors"
                  placeholder="••••••••"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-2.5 top-1/2 -translate-y-1/2 text-[#4A4A55] hover:text-[#A0A0B0]"
                >
                  {showPassword ? <EyeOff size={14} /> : <Eye size={14} />}
                </button>
              </div>
              {isSetup && password.length > 0 && (
                <div className="mt-2">
                  <div className="flex items-center gap-2 mb-1">
                    <div className="flex-1 h-1 bg-[rgba(255,255,255,0.06)] rounded-full overflow-hidden">
                      <div
                        className="h-full rounded-full transition-all"
                        style={{ width: `${(strength.score / 5) * 100}%`, backgroundColor: strength.color }}
                      />
                    </div>
                    <span className="text-[10px]" style={{ color: strength.color }}>{strength.label}</span>
                  </div>
                  <div className="flex flex-wrap gap-x-3 gap-y-0.5">
                    {[
                      { label: '8+ chars', met: password.length >= 8 },
                      { label: 'Uppercase', met: /[A-Z]/.test(password) },
                      { label: 'Number', met: /[0-9]/.test(password) },
                      { label: 'Symbol', met: /[^A-Za-z0-9]/.test(password) },
                    ].map((req) => (
                      <span key={req.label} className={`text-[10px] flex items-center gap-1 ${req.met ? 'text-rail-green' : 'text-[#4A4A55]'}`}>
                        {req.met ? <CheckCircle2 size={10} /> : <XCircle size={10} />}
                        {req.label}
                      </span>
                    ))}
                  </div>
                </div>
              )}
            </div>

            {isSetup && (
              <div>
                <label className="block text-[10px] text-[#4A4A55] uppercase tracking-wider font-medium mb-1.5">
                  Confirm Password
                </label>
                <input
                  ref={confirmPasswordRef}
                  type={showPassword ? 'text' : 'password'}
                  value={confirmPassword}
                  onChange={(e) => setConfirmPassword(e.target.value)}
                  required
                  className={`w-full h-9 px-3 bg-[rgba(255,255,255,0.03)] border rounded-lg text-sm text-white placeholder-[#4A4A55] focus:outline-none transition-colors ${
                    passwordsMatch ? 'border-[rgba(255,255,255,0.08)] focus:border-[rgba(139,92,246,0.4)]' : 'border-red-500/30 focus:border-red-500/50'
                  }`}
                  placeholder="••••••••"
                />
                {!passwordsMatch && (
                  <p className="text-[10px] text-red-400 mt-1">Passwords do not match</p>
                )}
              </div>
            )}

            <button
              type="submit"
              disabled={loading || (isSetup && !passwordsMatch)}
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

          {!isSetup && (
            <div className="mt-3 text-center">
              <button
                onClick={() => toast.info('Password reset is not yet configured. Contact your admin.')}
                className="text-[11px] text-[#4A4A55] hover:text-[#A0A0B0] transition-colors"
              >
                Forgot password?
              </button>
            </div>
          )}
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
