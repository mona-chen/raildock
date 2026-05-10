import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { api } from '@/lib/api'

export function useModules() {
  return useQuery({
    queryKey: ['modules'],
    queryFn: () => api.modules.list(),
  })
}

export function useBuilders() {
  return useQuery({
    queryKey: ['builders'],
    queryFn: () => api.builders.list(),
  })
}

export function useNetworks() {
  return useQuery({
    queryKey: ['networks'],
    queryFn: () => api.networks.list(),
  })
}

export function useTemplates() {
  return useQuery({
    queryKey: ['templates'],
    queryFn: () => api.templates.list(),
  })
}

export function useDeployTemplate() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ templateId, projectId }: { templateId: string; projectId: string }) =>
      api.templates.deploy(templateId, projectId),
    onSuccess: (_, { projectId }) => {
      queryClient.invalidateQueries({ queryKey: ['projects', projectId, 'services'] })
      queryClient.invalidateQueries({ queryKey: ['projects', projectId] })
      toast.success('Template deployed')
    },
    onError: () => toast.error('Deploy failed. Check the deploy log for details.'),
  })
}
