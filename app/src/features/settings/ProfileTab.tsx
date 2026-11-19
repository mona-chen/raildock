import { useState } from 'react'
import {
  AlertCircle,
  Check,
  Eye,
  EyeOff,
  Loader2,
  LockKeyhole,
  Mail,
  UserRound,
} from 'lucide-react'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { IconButton } from '@/components/ui/icon-button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Separator } from '@/components/ui/separator'
import { useAuthStore } from '@/stores/useAuthStore'
import { useUpdateProfile } from '@/hooks/useProfile'
import { cn } from '@/lib/utils'

function initialsFor(value: string): string {
  return value
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0])
    .join('')
    .toUpperCase() || '?'
}

function PasswordInput({
  id,
  value,
  onChange,
  autoComplete,
  invalid,
  placeholder,
}: {
  id: string
  value: string
  onChange: (value: string) => void
  autoComplete: string
  invalid?: boolean
  placeholder?: string
}) {
  const [visible, setVisible] = useState(false)

  return (
    <div className="relative">
      <Input
        id={id}
        type={visible ? 'text' : 'password'}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        autoComplete={autoComplete}
        placeholder={placeholder}
        aria-invalid={invalid || undefined}
        className="h-10 border-white/8 bg-white/[0.03] pr-10 text-[13px] text-white/85 placeholder:text-white/25"
      />
      <IconButton
        type="button"
        title={visible ? 'Hide password' : 'Show password'}
        aria-label={visible ? 'Hide password' : 'Show password'}
        onClick={() => setVisible((current) => !current)}
        className="absolute right-1 top-1/2 -translate-y-1/2 text-white/35 hover:text-white/70"
      >
        {visible ? <EyeOff /> : <Eye />}
      </IconButton>
    </div>
  )
}

export default function ProfileTab() {
  const user = useAuthStore((state) => state.user)
  const updateProfile = useUpdateProfile()

  const [name, setName] = useState(user?.name ?? '')
  const [email, setEmail] = useState(user?.email ?? '')
  const [currentPassword, setCurrentPassword] = useState('')
  const [newPassword, setNewPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')

  if (!user) {
    return (
      <div className="max-w-3xl">
        <div className="h-40 animate-pulse rounded-2xl border border-white/6 bg-white/[0.02]" />
      </div>
    )
  }

  const trimmedName = name.trim()
  const trimmedEmail = email.trim()
  const emailChanged = trimmedEmail !== user.email
  const passwordChange = newPassword.length > 0
  const credentialsChanged = emailChanged || passwordChange
  const confirmationMismatch = passwordChange && confirmPassword.length > 0 && newPassword !== confirmPassword
  const hasChanges = trimmedName !== user.name || emailChanged || passwordChange
  const dirty = hasChanges || currentPassword.length > 0 || confirmPassword.length > 0

  const canSave =
    !updateProfile.isPending &&
    hasChanges &&
    trimmedName.length > 0 &&
    trimmedEmail.length > 0 &&
    (!credentialsChanged || currentPassword.length > 0) &&
    (!passwordChange || (confirmPassword.length > 0 && !confirmationMismatch))

  const error = updateProfile.error as (Error & { code?: string }) | null
  const passwordError = error?.code === 'current_password_invalid' || error?.code === 'password_confirmation_mismatch'
  const profileError = error && !passwordError ? error : null

  const clearError = () => {
    if (updateProfile.isError) updateProfile.reset()
  }

  const handleSave = () => {
    if (!canSave) return
    updateProfile.mutate(
      {
        name: trimmedName,
        email: trimmedEmail,
        currentPassword: currentPassword || undefined,
        password: newPassword || undefined,
        passwordConfirmation: confirmPassword || undefined,
      },
      {
        onSuccess: () => {
          setCurrentPassword('')
          setNewPassword('')
          setConfirmPassword('')
        },
      }
    )
  }

  const handleReset = () => {
    setName(user.name)
    setEmail(user.email)
    setCurrentPassword('')
    setNewPassword('')
    setConfirmPassword('')
    updateProfile.reset()
  }

  return (
    <form
      className="max-w-3xl space-y-5"
      onSubmit={(event) => {
        event.preventDefault()
        handleSave()
      }}
    >
      <div>
        <h2 className="text-sm font-medium text-white">Profile</h2>
        <p className="mt-1 text-[11px] leading-relaxed text-[#9292a3]">
          The name and email your teammates see, and the password you use to sign in.
        </p>
      </div>

      <section className="overflow-hidden rounded-2xl border border-white/6 bg-[#16161a] shadow-[0_1px_0_rgba(255,255,255,0.03)_inset]">
        <div className="flex items-center gap-4 border-b border-white/6 p-5 sm:p-6">
          <Avatar className="size-14 ring-1 ring-rail-purple/25">
            <AvatarFallback className="bg-[radial-gradient(circle_at_30%_20%,rgba(139,92,246,0.32),rgba(139,92,246,0.08))] text-[15px] font-semibold tracking-wide text-rail-purple">
              {initialsFor(user.name || user.email)}
            </AvatarFallback>
          </Avatar>
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <p className="truncate text-sm font-medium text-white">{user.name}</p>
              {user.admin && (
                <Badge variant="outline" className="border-amber-400/25 bg-amber-400/8 text-[9px] font-medium text-amber-300">
                  Instance admin
                </Badge>
              )}
            </div>
            <p className="mt-0.5 truncate text-[11px] text-white/40">{user.email}</p>
            <p className="mt-2 flex items-center gap-1.5 text-[10px] text-white/35">
              <UserRound size={11} className="text-rail-purple/70" />
              Personal account
            </p>
          </div>
        </div>

        <div className="space-y-5 p-5 sm:p-6">
          {profileError && (
            <Alert variant="destructive" className="border-red-500/20 bg-red-500/[0.06] text-red-300">
              <AlertCircle />
              <AlertDescription className="text-[11px] text-red-300/90">{profileError.message}</AlertDescription>
            </Alert>
          )}

          <div className="grid gap-5 sm:grid-cols-2">
            <div className="space-y-1.5">
              <Label htmlFor="profile-name" className="text-[11px] font-medium text-white/60">
                Display name
              </Label>
              <Input
                id="profile-name"
                value={name}
                onChange={(event) => { clearError(); setName(event.target.value) }}
                autoComplete="name"
                className="h-10 border-white/8 bg-white/[0.03] text-[13px] text-white/85"
              />
              <p className="text-[10px] leading-relaxed text-white/30">Shown on projects, deployments and activity.</p>
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="profile-email" className="text-[11px] font-medium text-white/60">
                Email address
              </Label>
              <div className="relative">
                <Mail size={14} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-white/25" />
                <Input
                  id="profile-email"
                  type="email"
                  value={email}
                  onChange={(event) => { clearError(); setEmail(event.target.value) }}
                  autoComplete="email"
                  className="h-10 border-white/8 bg-white/[0.03] pl-9 text-[13px] text-white/85"
                />
              </div>
              <p className={cn('text-[10px] leading-relaxed', emailChanged ? 'text-amber-300/80' : 'text-white/30')}>
                {emailChanged ? 'Changing your email requires your current password.' : 'Used to sign in and receive invitations.'}
              </p>
            </div>
          </div>
        </div>
      </section>

      <section className="overflow-hidden rounded-2xl border border-white/6 bg-[#16161a] shadow-[0_1px_0_rgba(255,255,255,0.03)_inset]">
        <div className="flex items-start gap-3 border-b border-white/6 p-5 sm:p-6">
          <span className="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-lg border border-rail-purple/20 bg-rail-purple/10">
            <LockKeyhole size={14} className="text-rail-purple" />
          </span>
          <div>
            <h3 className="text-[13px] font-medium text-white">Password</h3>
            <p className="mt-0.5 text-[11px] leading-relaxed text-[#9292a3]">
              Leave the new password fields blank to keep your current password.
            </p>
          </div>
        </div>

        <div className="space-y-5 p-5 sm:p-6">
          {passwordError && (
            <Alert variant="destructive" className="border-red-500/20 bg-red-500/[0.06] text-red-300">
              <AlertCircle />
              <AlertDescription className="text-[11px] text-red-300/90">{error?.message}</AlertDescription>
            </Alert>
          )}

          <div className="space-y-1.5">
            <Label htmlFor="profile-current-password" className="text-[11px] font-medium text-white/60">
              Current password
            </Label>
            <PasswordInput
              id="profile-current-password"
              value={currentPassword}
              onChange={(value) => { clearError(); setCurrentPassword(value) }}
              autoComplete="current-password"
              invalid={error?.code === 'current_password_invalid'}
              placeholder="Enter your current password"
            />
            <p className={cn('text-[10px] leading-relaxed', credentialsChanged ? 'text-amber-300/80' : 'text-white/30')}>
              {credentialsChanged
                ? 'Required to save your new email or password.'
                : 'Only needed when changing your email or password.'}
            </p>
          </div>

          <Separator className="bg-white/6" />

          <div className="grid gap-5 sm:grid-cols-2">
            <div className="space-y-1.5">
              <Label htmlFor="profile-new-password" className="text-[11px] font-medium text-white/60">
                New password
              </Label>
              <PasswordInput
                id="profile-new-password"
                value={newPassword}
                onChange={(value) => { clearError(); setNewPassword(value) }}
                autoComplete="new-password"
                invalid={confirmationMismatch}
                placeholder="New password"
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="profile-confirm-password" className="text-[11px] font-medium text-white/60">
                Confirm new password
              </Label>
              <PasswordInput
                id="profile-confirm-password"
                value={confirmPassword}
                onChange={(value) => { clearError(); setConfirmPassword(value) }}
                autoComplete="new-password"
                invalid={confirmationMismatch}
                placeholder="Repeat new password"
              />
            </div>
          </div>

          {confirmationMismatch && (
            <p className="flex items-center gap-1.5 text-[10px] text-red-300/90">
              <AlertCircle size={11} />
              New password and confirmation do not match.
            </p>
          )}

          <p className="text-[10px] leading-relaxed text-white/30">
            Choose a password you do not use anywhere else. Changing it does not sign out other sessions.
          </p>
        </div>

        <div className="flex flex-wrap items-center justify-between gap-3 border-t border-white/6 bg-white/[0.015] px-5 py-3.5 sm:px-6">
          <div className="flex items-center gap-2 text-[10px] text-white/35" aria-live="polite">
            {dirty ? (
              <>
                <span className="size-1.5 rounded-full bg-amber-400" />
                Unsaved changes
              </>
            ) : (
              <>
                <Check size={12} className="text-emerald-400/80" />
                All changes saved
              </>
            )}
          </div>
          <div className="flex items-center gap-2">
            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={handleReset}
              disabled={!dirty || updateProfile.isPending}
              className="h-8 text-[11px] text-white/50 hover:bg-white/5 hover:text-white/80"
            >
              Reset
            </Button>
            <Button
              type="submit"
              size="sm"
              disabled={!canSave}
              className={cn(
                'h-8 px-3 text-[11px]',
                canSave
                  ? 'bg-rail-purple text-white hover:bg-rail-purple/90'
                  : 'bg-white/8 text-white/35'
              )}
            >
              {updateProfile.isPending ? <Loader2 className="animate-spin" /> : <Check />}
              {updateProfile.isPending ? 'Saving…' : 'Save changes'}
            </Button>
          </div>
        </div>
      </section>
    </form>
  )
}
