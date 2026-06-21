import { useState } from 'react'
import { Users, UserPlus, Trash2, Copy, Check, X, Crown, Shield, User as UserIcon, Mail, Clock } from 'lucide-react'
import { useAuthStore } from '@/stores/useAuthStore'
import {
  useOrganizationMembers,
  useAddOrganizationMember,
  useUpdateMemberRole,
  useRemoveOrganizationMember,
  useOrganizationInvitations,
  useRevokeInvitation,
} from '@/hooks/useOrganizations'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useCopy } from '@/hooks/useCopy'
import { toast } from 'sonner'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'

type Role = 'owner' | 'admin' | 'member'

function daysUntilString(dateStr: string): string {
  const ms = new Date(dateStr).getTime() - Date.now()
  const days = Math.max(0, Math.ceil(ms / (1000 * 60 * 60 * 24)))
  return days === 0 ? 'Expires today' : `${days}d left`
}

const ROLE_INFO: Record<Role, { label: string; icon: typeof Crown; color: string }> = {
  owner: { label: 'Owner', icon: Crown, color: 'text-amber-400' },
  admin: { label: 'Admin', icon: Shield, color: 'text-rail-purple' },
  member: { label: 'Member', icon: UserIcon, color: 'text-[#A0A0B0]' },
}

export default function MembersTab() {
  const orgId = useAuthStore((s) => s.currentOrganizationId)
  const currentUserId = useAuthStore((s) => s.user?.id)
  const currentOrg = useAuthStore((s) => s.currentOrganization())
  const currentUserRole = currentOrg?.role as Role | undefined

  const { data: members = [], isLoading: membersLoading } = useOrganizationMembers(orgId)
  const { data: invitations = [], isLoading: invitationsLoading } = useOrganizationInvitations(orgId)
  const addMember = useAddOrganizationMember(orgId)
  const updateRole = useUpdateMemberRole(orgId)
  const removeMember = useRemoveOrganizationMember(orgId)
  const revokeInvitation = useRevokeInvitation(orgId)
  const { copiedKey, copy } = useCopy(2000)

  const [inviteOpen, setInviteOpen] = useState(false)
  const [inviteEmail, setInviteEmail] = useState('')
  const [inviteRole, setInviteRole] = useState<'admin' | 'member'>('member')
  const [lastInviteUrl, setLastInviteUrl] = useState<string | null>(null)

  const canManage = currentUserRole === 'owner' || currentUserRole === 'admin'
  const isOwner = currentUserRole === 'owner'

  if (!orgId) {
    return (
      <div className="max-w-3xl">
        <div className="bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-xl p-8 text-center">
          <Users size={24} className="text-[#4A4A55] mx-auto mb-2" />
          <p className="text-sm text-[#A0A0B0]">No organization selected</p>
          <p className="text-[11px] text-[#4A4A55] mt-1">
            Switch to an organization from the Organizations tab to manage its members.
          </p>
        </div>
      </div>
    )
  }

  const handleInvite = () => {
    if (!inviteEmail.trim()) return
    addMember.mutate(
      { email: inviteEmail.trim(), role: inviteRole },
      {
        onSuccess: (result) => {
          setInviteEmail('')
          if (result.acceptUrl && !result.existingUser) {
            setLastInviteUrl(result.acceptUrl)
          } else {
            setInviteOpen(false)
          }
        },
      }
    )
  }

  const closeInviteDialog = () => {
    setInviteOpen(false)
    setLastInviteUrl(null)
    setInviteEmail('')
  }

  const handleRoleChange = (userId: string, role: Role) => {
    if (role === 'owner' && !isOwner) {
      toast.error('Only owners can promote members to owner')
      return
    }
    updateRole.mutate({ userId, role })
  }

  const handleRemove = (userId: string, name: string, isYou: boolean) => {
    const message = isYou ? 'Leave this organization?' : `Remove ${name} from this organization?`
    if (confirm(message)) {
      removeMember.mutate(userId)
    }
  }

  return (
    <div className="max-w-3xl space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-sm font-medium text-white">Members</h2>
          <p className="text-[11px] text-[#4A4A55] mt-0.5">
            Invite teammates to collaborate on <span className="text-[#A0A0B0]">{currentOrg?.name}</span>
          </p>
        </div>
        {canManage && (
          <Dialog open={inviteOpen} onOpenChange={(open) => (open ? setInviteOpen(true) : closeInviteDialog())}>
            <DialogTrigger asChild>
              <Button size="sm" className="bg-rail-purple hover:bg-rail-purple/90 text-white text-xs h-8">
                <UserPlus size={14} className="mr-1" />
                Invite Member
              </Button>
            </DialogTrigger>
            <DialogContent className="bg-[#161618] border-[rgba(255,255,255,0.06)] text-[#F0F1F3]">
              <DialogHeader>
                <DialogTitle className="text-sm">
                  {lastInviteUrl ? 'Invitation created' : `Invite to ${currentOrg?.name}`}
                </DialogTitle>
                <DialogDescription className="text-[11px] text-[#4A4A55]">
                  {lastInviteUrl
                    ? 'Share this link with your teammate. It expires in 7 days.'
                    : 'Enter an email address. If they already have a RailDock account they\'ll be added immediately; otherwise we\'ll send an invitation.'}
                </DialogDescription>
              </DialogHeader>

              {lastInviteUrl ? (
                <div className="py-2 space-y-3">
                  <div className="flex items-center gap-2">
                    <code className="flex-1 text-[11px] font-mono text-[#A0A0B0] bg-[rgba(255,255,255,0.03)] rounded px-2 py-2 truncate">
                      {lastInviteUrl}
                    </code>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => copy(lastInviteUrl, 'invite')}
                      className="text-[11px] text-[#A0A0B0] hover:text-white h-8 shrink-0"
                    >
                      {copiedKey === 'invite' ? <><Check size={12} className="mr-1 text-[#22c55e]" /> Copied</> : <><Copy size={12} className="mr-1" /> Copy</>}
                    </Button>
                  </div>
                  <p className="text-[10px] text-[#4A4A55]">
                    We also tried to send an email. If it didn't go out, share this link directly.
                  </p>
                </div>
              ) : (
                <div className="space-y-3 py-2">
                  <div>
                    <label className="text-[11px] text-[#A0A0B0] mb-1 block">Email</label>
                    <Input
                      type="email"
                      autoFocus
                      value={inviteEmail}
                      onChange={(e) => setInviteEmail(e.target.value)}
                      placeholder="teammate@company.com"
                      className="bg-[rgba(255,255,255,0.04)] border-[rgba(255,255,255,0.08)] text-sm h-9"
                    />
                  </div>
                  <div>
                    <label className="text-[11px] text-[#A0A0B0] mb-1 block">Role</label>
                    <div className="grid grid-cols-2 gap-2">
                      {(['member', 'admin'] as const).map((r) => {
                        const info = ROLE_INFO[r]
                        const Icon = info.icon
                        const selected = inviteRole === r
                        return (
                          <button
                            key={r}
                            type="button"
                            onClick={() => setInviteRole(r)}
                            className={`flex items-start gap-2 p-2.5 rounded-lg border text-left transition-colors ${
                              selected
                                ? 'bg-[rgba(139,92,246,0.08)] border-[rgba(139,92,246,0.4)]'
                                : 'bg-[rgba(255,255,255,0.02)] border-[rgba(255,255,255,0.06)] hover:border-[rgba(255,255,255,0.12)]'
                            }`}
                          >
                            <Icon size={14} className={`mt-0.5 ${info.color}`} />
                            <div>
                              <div className="text-xs text-white font-medium">{info.label}</div>
                              <div className="text-[10px] text-[#4A4A55] mt-0.5">
                                {r === 'admin' ? 'Can manage members and projects' : 'Can deploy and view projects'}
                              </div>
                            </div>
                          </button>
                        )
                      })}
                    </div>
                  </div>
                </div>
              )}

              <DialogFooter>
                {lastInviteUrl ? (
                  <Button
                    onClick={closeInviteDialog}
                    className="bg-rail-purple hover:bg-rail-purple/90 text-white text-xs"
                  >
                    Done
                  </Button>
                ) : (
                  <Button
                    onClick={handleInvite}
                    disabled={addMember.isPending || !inviteEmail.trim()}
                    className="bg-rail-purple hover:bg-rail-purple/90 text-white text-xs"
                  >
                    {addMember.isPending ? 'Sending...' : 'Send Invitation'}
                  </Button>
                )}
              </DialogFooter>
            </DialogContent>
          </Dialog>
        )}
      </div>

      {/* Active members */}
      {membersLoading ? (
        <div className="text-[11px] text-[#4A4A55]">Loading members...</div>
      ) : (
        <div className="space-y-2">
          {members.map((m) => {
            const role = m.role as Role
            const info = ROLE_INFO[role]
            const Icon = info.icon
            return (
              <div
                key={m.id}
                className="flex items-center justify-between p-4 rounded-xl border bg-[rgba(255,255,255,0.02)] border-[rgba(255,255,255,0.05)]"
              >
                <div className="flex items-center gap-3 min-w-0">
                  <div className="w-8 h-8 rounded-full bg-[rgba(139,92,246,0.12)] flex items-center justify-center text-rail-purple text-xs font-bold shrink-0">
                    {(m.user.name || m.user.email).slice(0, 2).toUpperCase()}
                  </div>
                  <div className="min-w-0">
                    <div className="text-sm text-white font-medium truncate flex items-center gap-2">
                      {m.user.name}
                      {m.isYou && <span className="text-[9px] px-1.5 py-0.5 rounded bg-[rgba(255,255,255,0.06)] text-[#4A4A55]">You</span>}
                    </div>
                    <div className="text-[11px] text-[#4A4A55] truncate">{m.user.email}</div>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  {canManage && !m.isYou ? (
                    <select
                      value={role}
                      onChange={(e) => handleRoleChange(m.userId, e.target.value as Role)}
                      disabled={updateRole.isPending}
                      className="h-7 px-2 bg-[rgba(255,255,255,0.04)] border border-[rgba(255,255,255,0.08)] rounded text-[11px] text-white focus:outline-none focus:border-rail-purple"
                    >
                      {(role === 'owner' || isOwner) && <option value="owner">Owner</option>}
                      <option value="admin">Admin</option>
                      <option value="member">Member</option>
                    </select>
                  ) : (
                    <span className={`text-[10px] flex items-center gap-1 px-2 py-0.5 rounded ${info.color}`}>
                      <Icon size={10} />
                      {info.label}
                    </span>
                  )}
                  {canManage && !m.isYou && role !== 'owner' && (
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleRemove(m.userId, m.user.name, false)}
                      className="text-[#4A4A55] hover:text-red-400 h-7 w-7 p-0"
                      title="Remove from organization"
                    >
                      <Trash2 size={13} />
                    </Button>
                  )}
                  {m.isYou && role !== 'owner' && (
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleRemove(m.userId, m.user.name, true)}
                      className="text-[#4A4A55] hover:text-red-400 h-7 text-[11px]"
                    >
                      Leave
                    </Button>
                  )}
                </div>
              </div>
            )
          })}
        </div>
      )}

      {/* Pending invitations */}
      {canManage && (
        <div className="pt-4 border-t border-[rgba(255,255,255,0.05)]">
          <div className="flex items-center justify-between mb-3">
            <div>
              <h3 className="text-sm font-medium text-white">Pending Invitations</h3>
              <p className="text-[11px] text-[#4A4A55] mt-0.5">Invitations awaiting acceptance</p>
            </div>
          </div>

          {invitationsLoading ? (
            <div className="text-[11px] text-[#4A4A55]">Loading...</div>
          ) : invitations.length === 0 ? (
            <div className="text-[11px] text-[#4A4A55] bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-lg p-4 text-center">
              <Mail size={18} className="text-[#4A4A55] mx-auto mb-2" />
              No pending invitations
            </div>
          ) : (
            <div className="space-y-2">
              {invitations.map((inv) => {
                const role = (inv.role as Role) || 'member'
                const info = ROLE_INFO[role]
                const Icon = info.icon
                return (
                  <div
                    key={inv.id}
                    className="flex items-center justify-between p-3 rounded-xl border bg-[rgba(255,255,255,0.02)] border-[rgba(255,255,255,0.05)]"
                  >
                    <div className="flex items-center gap-3 min-w-0">
                      <Mail size={14} className="text-[#4A4A55] shrink-0" />
                      <div className="min-w-0">
                        <div className="text-sm text-white truncate">{inv.email}</div>
                        <div className="text-[10px] text-[#4A4A55] flex items-center gap-2">
                          <span className={`flex items-center gap-1 ${info.color}`}>
                            <Icon size={10} />
                            {info.label}
                          </span>
                          <span className="flex items-center gap-1">
                            <Clock size={10} />
                            {daysUntilString(inv.expiresAt)}
                          </span>
                          {inv.invitedBy && (
                            <span>by {inv.invitedBy.name}</span>
                          )}
                        </div>
                      </div>
                    </div>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => revokeInvitation.mutate(inv.id)}
                      disabled={revokeInvitation.isPending}
                      className="text-[#4A4A55] hover:text-red-400 h-7 w-7 p-0"
                      title="Revoke invitation"
                    >
                      <X size={13} />
                    </Button>
                  </div>
                )
              })}
            </div>
          )}
        </div>
      )}
    </div>
  )
}