import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { api } from '@/lib/api'
import { useAuthStore } from '@/stores/useAuthStore'

export function useOrganizations() {
  return useQuery({
    queryKey: ['organizations'],
    queryFn: () => api.organizations.list(),
  })
}

export function useCreateOrganization() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { name: string; slug: string; avatarUrl?: string }) =>
      api.organizations.create(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['organizations'] })
      toast.success('Organization created')
    },
    onError: (err: Error) => toast.error(`Failed to create organization: ${err.message}`),
  })
}

export function useDeleteOrganization() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => api.organizations.destroy(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['organizations'] })
      toast.success('Organization deleted')
    },
    onError: (err: Error) => toast.error(`Failed to delete organization: ${err.message}`),
  })
}

export function useServerBootstrap(organizationId: string | null) {
  return useQuery({
    queryKey: ['organizations', organizationId, 'server-bootstrap'],
    queryFn: () => api.organizations.serverBootstrap(organizationId!),
    enabled: !!organizationId,
  })
}

// ── Members ─────────────────────────────────────

export function useOrganizationMembers(organizationId: string | null) {
  return useQuery({
    queryKey: ['organizations', organizationId, 'members'],
    queryFn: () => api.organizations.members.list(organizationId!),
    enabled: !!organizationId,
  })
}

export function useAddOrganizationMember(organizationId: string | null) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { email: string; role?: 'admin' | 'member' }) =>
      api.organizations.members.create(organizationId!, data),
    onSuccess: (result) => {
      queryClient.invalidateQueries({ queryKey: ['organizations', organizationId, 'members'] })
      queryClient.invalidateQueries({ queryKey: ['organizations', organizationId, 'invitations'] })
      if (result.existingUser) {
        toast.success(`Added ${result.membership?.user.email}`)
      } else if (result.emailEnqueued) {
        toast.success(`Invitation sent to ${result.invitation?.email}`)
      } else {
        toast.success(`Invitation created for ${result.invitation?.email}`, {
          description: 'Email is not configured, so copy the invite link and share it directly.',
        })
      }
    },
    onError: (err: Error) => toast.error(`Failed to add member: ${err.message}`),
  })
}

export function useUpdateMemberRole(organizationId: string | null) {
  const queryClient = useQueryClient()
  const currentUserId = useAuthStore((s) => s.user?.id)
  return useMutation({
    mutationFn: ({ userId, role }: { userId: string; role: 'owner' | 'admin' | 'member' }) =>
      api.organizations.members.updateRole(organizationId!, userId, role),
    onSuccess: (_, vars) => {
      queryClient.invalidateQueries({ queryKey: ['organizations', organizationId, 'members'] })
      if (currentUserId && String(currentUserId) === String(vars.userId)) {
        toast.info('Your role was updated. Refresh to see sidebar changes.')
      }
    },
    onError: (err: Error) => toast.error(`Failed to update role: ${err.message}`),
  })
}

export function useRemoveOrganizationMember(organizationId: string | null) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (userId: string) => api.organizations.members.remove(organizationId!, userId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['organizations', organizationId, 'members'] })
      toast.success('Member removed')
    },
    onError: (err: Error) => toast.error(`Failed to remove member: ${err.message}`),
  })
}

// ── Invitations ─────────────────────────────────

export function useOrganizationInvitations(organizationId: string | null) {
  return useQuery({
    queryKey: ['organizations', organizationId, 'invitations'],
    queryFn: () => api.organizations.invitations.list(organizationId!),
    enabled: !!organizationId,
  })
}

export function useRevokeInvitation(organizationId: string | null) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (invitationId: string) => api.organizations.invitations.revoke(organizationId!, invitationId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['organizations', organizationId, 'invitations'] })
      toast.success('Invitation revoked')
    },
    onError: (err: Error) => toast.error(`Failed to revoke invitation: ${err.message}`),
  })
}