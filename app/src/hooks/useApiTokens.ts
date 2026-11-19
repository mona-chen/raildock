import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { api, type CreateApiTokenInput } from '@/lib/api'
import { useAuthStore } from '@/stores/useAuthStore'

export function useApiTokens() {
  const organizationId = useAuthStore((state) => state.currentOrganizationId)
  return useQuery({
    queryKey: ['api-tokens', organizationId],
    queryFn: () => api.apiTokens.list(),
    enabled: !!organizationId,
  })
}

export function useCreateApiToken() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (input: CreateApiTokenInput) => api.apiTokens.create(input),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['api-tokens'] })
    },
    onError: (err) => toast.error(`Failed to create token: ${err.message}`),
  })
}

export function useRevokeApiToken() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => api.apiTokens.revoke(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['api-tokens'] })
      toast.success('Token revoked')
    },
    onError: (err) => toast.error(`Failed to revoke token: ${err.message}`),
  })
}
