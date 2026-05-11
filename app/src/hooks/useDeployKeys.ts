import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { api } from '@/lib/api'

export function useDeployKeys() {
  return useQuery({
    queryKey: ['deploy-keys'],
    queryFn: () => api.deployKeys.list(),
  })
}

export function useCreateDeployKey() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { name: string }) => api.deployKeys.create(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['deploy-keys'] })
      toast.success('Deploy key created')
    },
    onError: (err: Error) => toast.error(`Failed to create deploy key: ${err.message}`),
  })
}

export function useDeleteDeployKey() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => api.deployKeys.destroy(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['deploy-keys'] })
      toast.success('Deploy key deleted')
    },
    onError: (err: Error) => toast.error(`Failed to delete deploy key: ${err.message}`),
  })
}
