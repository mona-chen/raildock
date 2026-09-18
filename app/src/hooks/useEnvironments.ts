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

/**
 * Copies every service and its configuration into a new environment. The copies
 * are staged (stopped, undeployed), so this resolves to a summary to review
 * rather than to anything that is already live.
 */
export function useDuplicateEnvironment() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({
      projectId,
      id,
      data,
    }: {
      projectId: string
      id: string
      data: { name: string; description?: string }
    }) => api.environments.duplicate(projectId, id, data),
    onSuccess: (result, { projectId }) => {
      invalidate(projectId, queryClient)
      queryClient.invalidateQueries({ queryKey: ['projects', projectId, 'services'] })
      const { summary } = result
      toast.success(
        `Duplicated ${summary.services} service${summary.services === 1 ? '' : 's'} into ${result.environment.name} — staged, nothing deployed yet`,
      )
    },
    onError: (err) => toast.error(`Failed to duplicate environment: ${err.message}`),
  })
}

/**
 * The staged-change review for a sync. Read-only, so it is a query: the dialog
 * can be opened, closed and reopened without applying anything.
 */
export function useEnvironmentSyncPlan(projectId: string, targetId?: string, sourceId?: string) {
  return useQuery({
    queryKey: ['projects', projectId, 'environments', targetId, 'sync_plan', sourceId],
    queryFn: () => api.environments.syncPlan(projectId, targetId as string, sourceId as string),
    enabled: !!projectId && !!targetId && !!sourceId && sourceId !== targetId,
  })
}

export function useSyncEnvironment() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ projectId, id, sourceId }: { projectId: string; id: string; sourceId: string }) =>
      api.environments.sync(projectId, id, sourceId),
    onSuccess: (result, { projectId }) => {
      invalidate(projectId, queryClient)
      queryClient.invalidateQueries({ queryKey: ['projects', projectId, 'services'] })
      toast.success(result.message)
    },
    onError: (err) => toast.error(`Failed to sync environment: ${err.message}`),
  })
}
