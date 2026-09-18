import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { api } from '@/lib/api'

/**
 * Environments are first-class per project. The default (`production`)
 * environment is created with the project and cannot be deleted, matching
 * Railway, Coolify and Dokploy.
 */
export function useEnvironments(projectId: string) {
  return useQuery({
    queryKey: ['projects', projectId, 'environments'],
    queryFn: () => api.environments.list(projectId),
    enabled: !!projectId,
  })
}

function invalidate(projectId: string, queryClient: ReturnType<typeof useQueryClient>) {
  queryClient.invalidateQueries({ queryKey: ['projects', projectId, 'environments'] })
  queryClient.invalidateQueries({ queryKey: ['projects', projectId] })
}

export function useCreateEnvironment() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ projectId, data }: { projectId: string; data: { name: string; description?: string } }) =>
      api.environments.create(projectId, data),
    onSuccess: (_, { projectId }) => {
      invalidate(projectId, queryClient)
      toast.success('Environment created')
    },
    onError: (err) => toast.error(`Failed to create environment: ${err.message}`),
  })
}

export function useUpdateEnvironment() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({
      projectId,
      id,
      data,
    }: {
      projectId: string
      id: string
      data: { name?: string; description?: string | null }
    }) => api.environments.update(projectId, id, data),
    onSuccess: (_, { projectId }) => {
      invalidate(projectId, queryClient)
      toast.success('Environment updated')
    },
    onError: (err) => toast.error(`Failed to update environment: ${err.message}`),
  })
}

export function useDestroyEnvironment() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ projectId, id }: { projectId: string; id: string }) =>
      api.environments.destroy(projectId, id),
    onSuccess: (_, { projectId }) => {
      invalidate(projectId, queryClient)
      toast.success('Environment deleted')
    },
    // The backend refuses to delete the default environment or one that still
    // owns services; surface that reason verbatim instead of a generic error.
    onError: (err) => toast.error(err.message),
  })
}
