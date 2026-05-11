import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { api } from '@/lib/api'

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
