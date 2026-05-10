import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { api } from '@/lib/api'

export function useProjects() {
  return useQuery({
    queryKey: ['projects'],
    queryFn: () => api.projects.list(),
  })
}

export function useProject(id: string) {
  return useQuery({
    queryKey: ['projects', id],
    queryFn: () => api.projects.get(id),
    enabled: !!id,
  })
}

export function useCreateProject() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.projects.create,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['projects'] })
      toast.success('Project created')
    },
    onError: (err) => toast.error(`Failed to create project: ${err.message}`),
  })
}

export function useDestroyProject() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.projects.destroy,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['projects'] })
      toast.success('Project deleted')
    },
    onError: (err) => toast.error(`Failed to delete project: ${err.message}`),
  })
}

export function useUpdateProjectSharedVars() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, vars }: { id: string; vars: { key: string; value: string }[] }) =>
      api.projects.updateSharedVars(id, vars),
    onSuccess: (_, { id }) => {
      queryClient.invalidateQueries({ queryKey: ['projects', id] })
      toast.success('Shared variables updated')
    },
    onError: (err) => toast.error(`Update failed: ${err.message}`),
  })
}
