import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { api } from '@/lib/api'
import { useAuthStore } from '@/stores/useAuthStore'

export function useGitSources() {
  const orgId = useAuthStore((s) => s.currentOrganizationId)
  return useQuery({
    queryKey: ['git-sources', orgId],
    queryFn: () => api.gitSources.list(orgId || undefined),
  })
}

export function useConnectGitSource() {
  const queryClient = useQueryClient()
  const orgId = useAuthStore((s) => s.currentOrganizationId)
  return useMutation({
    mutationFn: ({ provider, token }: { provider: string; token: string }) =>
      api.gitSources.connect(provider, token, orgId || undefined),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['git-sources'] })
      toast.success('Git source connected')
    },
    onError: (err: Error) => toast.error(`Connection failed: ${err.message}`),
  })
}

export function useDisconnectGitSource() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.gitSources.disconnect,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['git-sources'] })
      toast.success('Git source disconnected')
    },
    onError: (err: Error) => toast.error(`Disconnect failed: ${err.message}`),
  })
}
