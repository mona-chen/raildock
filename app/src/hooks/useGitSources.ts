import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { api } from '@/lib/api'

export function useGitSources() {
  return useQuery({
    queryKey: ['git-sources'],
    queryFn: () => api.gitSources.list(),
  })
}

export function useConnectGitSource() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ provider, token }: { provider: string; token: string }) =>
      api.gitSources.connect(provider, token),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['git-sources'] })
      toast.success('Git source connected')
    },
    onError: (err) => toast.error(`Connection failed: ${err.message}`),
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
    onError: (err) => toast.error(`Disconnect failed: ${err.message}`),
  })
}
