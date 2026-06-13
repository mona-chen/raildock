import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { api } from '@/lib/api'

export function useServers() {
  return useQuery({
    queryKey: ['servers'],
    queryFn: () => api.servers.list(),
  })
}

export function useCreateServer() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.servers.create,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['servers'] })
      toast.success('Server added')
    },
    onError: (err) => toast.error(`Failed to add server: ${err.message}`),
  })
}

export function useValidateServer() {
  return useMutation({
    mutationFn: api.servers.validate,
  })
}

export function useUpdateServer() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: Parameters<typeof api.servers.update>[1] }) =>
      api.servers.update(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['servers'] })
      toast.success('Server settings saved')
    },
    onError: (err) => toast.error(`Failed to save server: ${err.message}`),
  })
}

export function useDestroyServer() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.servers.destroy,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['servers'] })
      toast.success('Server removed')
    },
    onError: (err) => toast.error(`Failed to remove server: ${err.message}`),
  })
}
