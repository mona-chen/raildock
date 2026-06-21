import { useState, useEffect, useRef } from 'react'
import { useParams, useNavigate, Link } from 'react-router-dom'
import { CheckCircle2, XCircle, AlertCircle, Loader2, Mail, Eye, EyeOff } from 'lucide-react'
import { useAuthStore } from '@/stores/useAuthStore'
import { invitationsApi } from '@/lib/api'
import Logo from '@/components/Logo'
import { toast } from 'sonner'
import type { InvitationDetails } from '@/types'

export default function AcceptInvitationPage() {
  const { token } = useParams<{ token: string }>()
  const navigate = useNavigate()
  const { setToken, setUser, setCurrentOrganizationId } = useAuthStore()

  const [invitation, setInvitation] = useState<InvitationDetails | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [name, setName] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const passwordRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (!token) {
      setError('Invalid invitation link')
      setLoading(false)
      return
    }
    invitationsApi
      .show(token)
      .then((data) => setInvitation(data.invitation))
      .catch((err) => setError(err.message || 'This invitation is invalid or has expired'))
      .finally(() => setLoading(false))
  }, [token])

  const passwordStrength = password.length >= 8 ? 'Good' : 'Too weak'
  const passwordStrong = password.length >= 8

  const handleAccept = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!token || !invitation) return
    const pwd = passwordRef.current?.value || password
    if (!pwd) {
      setError('Password is required')
      return
    }

    setSubmitting(true)
    setError(null)
    try {
      const data = await invitationsApi.accept(token, {
        name: invitation.existingUser ? undefined : name.trim(),
        password: pwd,
      })
      setToken(data.token)
      setUser({
        ...data.user,
        organizations: [{
          id: data.organization.id,
          name: data.organization.name,
          slug: data.organization.slug,
          role: data.organization.role as 'owner' | 'admin' | 'member',
          memberCount: 0,
        }],
      })
      setCurrentOrganizationId(data.organization.id)
      toast.success(data.newAccount ? `Welcome to ${data.organization.name}!` : `Joined ${data.organization.name}`)
      navigate('/dashboard')
    } catch (err: any) {
      setError(err.message || 'Failed to accept invitation')
    } finally {
      setSubmitting(false)
    }
  }

  if (loading) {
    return (
      <CenteredCard>
        <Loader2 size={20} className="text-rail-purple animate-spin mx-auto" />
        <p className="text-[11px] text-[#4A4A55] mt-3 text-center">Loading invitation...</p>
      </CenteredCard>
    )
  }

  if (error || !invitation) {
    return (
      <CenteredCard>
        <XCircle size={28} className="text-red-400 mx-auto mb-3" />
        <h1 className="text-base font-semibold text-white mb-1 text-center">Invitation unavailable</h1>
        <p className="text-xs text-[#A0A0B0] text-center mb-5">{error || 'This invitation cannot be used'}</p>
        <Link
          to="/login"
          className="block text-center text-[11px] text-rail-purple hover:underline"
        >
          Go to sign in
        </Link>
      </CenteredCard>
    )
  }

  return (
    <CenteredCard>
      <div className="text-center mb-5">
        <div className="w-10 h-10 rounded-full bg-[rgba(139,92,246,0.12)] flex items-center justify-center mx-auto mb-3">
          <Mail size={18} className="text-rail-purple" />
        </div>
        <h1 className="text-base font-semibold text-white mb-1">Join {invitation.organization.name}</h1>
        <p className="text-xs text-[#A0A0B0]">
          <strong>{invitation.invitedBy.name}</strong> invited <strong>{invitation.email}</strong> as a{' '}
          <strong className="capitalize">{invitation.role}</strong>
        </p>
      </div>

      <form onSubmit={handleAccept} className="space-y-3">
        {!invitation.existingUser && (
          <div>
            <label className="block text-[10px] text-[#4A4A55] uppercase tracking-wider font-medium mb-1.5">
              Full Name
            </label>
            <input
              type="text"
              autoFocus
              autoComplete="name"
              required
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="w-full h-9 px-3 bg-[rgba(255,255,255,0.03)] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white placeholder-[#4A4A55] focus:outline-none focus:border-[rgba(139,92,246,0.4)] transition-colors"
              placeholder="Your name"
            />
          </div>
        )}

        <div>
          <label className="block text-[10px] text-[#4A4A55] uppercase tracking-wider font-medium mb-1.5">
            {invitation.existingUser ? 'Confirm your password' : 'Choose a password'}
          </label>
          <div className="relative">
            <input
              ref={passwordRef}
              type={showPassword ? 'text' : 'password'}
              autoComplete={invitation.existingUser ? 'current-password' : 'new-password'}
              required
              minLength={8}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full h-9 px-3 pr-9 bg-[rgba(255,255,255,0.03)] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white placeholder-[#4A4A55] focus:outline-none focus:border-[rgba(139,92,246,0.4)] transition-colors"
              placeholder="••••••••"
            />
            <button
              type="button"
              aria-label={showPassword ? 'Hide password' : 'Show password'}
              onClick={() => setShowPassword(!showPassword)}
              className="absolute right-2.5 top-1/2 -translate-y-1/2 text-[#4A4A55] hover:text-[#A0A0B0]"
            >
              {showPassword ? <EyeOff size={14} /> : <Eye size={14} />}
            </button>
          </div>
          {password.length > 0 && (
            <div className="flex items-center gap-2 mt-1.5">
              <div className="flex-1 h-1 bg-[rgba(255,255,255,0.06)] rounded-full overflow-hidden">
                <div
                  className={`h-full rounded-full transition-all ${passwordStrong ? 'bg-[#22c55e]' : 'bg-red-500'}`}
                  style={{ width: `${Math.min(100, (password.length / 12) * 100)}%` }}
                />
              </div>
              <span className={`text-[10px] ${passwordStrong ? 'text-[#22c55e]' : 'text-red-400'}`}>{passwordStrength}</span>
            </div>
          )}
        </div>

        {error && (
          <div className="px-3 py-2 bg-red-500/10 border border-red-500/20 rounded-lg text-xs text-red-400 flex items-center gap-2">
            <AlertCircle size={14} />
            {error}
          </div>
        )}

        <button
          type="submit"
          disabled={submitting || !passwordStrong || (!invitation.existingUser && !name.trim())}
          className="w-full h-9 flex items-center justify-center gap-2 bg-rail-purple text-white text-sm font-medium rounded-lg hover:bg-rail-purple-dark transition-all disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {submitting ? (
            <Loader2 size={14} className="animate-spin" />
          ) : (
            <>
              <CheckCircle2 size={14} /> Accept & Join
            </>
          )}
        </button>
      </form>

      <p className="text-center text-[10px] text-[#4A4A55] mt-4">
        Already have an account?{' '}
        <Link to="/login" className="text-rail-purple hover:underline">
          Sign in
        </Link>
      </p>
    </CenteredCard>
  )
}

function CenteredCard({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-[#0B0B0D] flex items-center justify-center px-4">
      <div className="w-full max-w-sm">
        <div className="flex items-center justify-center gap-2.5 mb-8">
          <Logo className="h-9 w-9" />
          <span className="text-lg font-bold text-white">RailDock</span>
        </div>
        <div className="bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.06)] rounded-xl p-6">
          {children}
        </div>
      </div>
    </div>
  )
}