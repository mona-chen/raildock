import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { api } from '@/lib/api'

export function useServices(projectId: string) {
  return useQuery({
    queryKey: ['projects', projectId, 'services'],
    queryFn: () => api.services.list(projectId),
    enabled: !!projectId,
  })
}

export function useService(id: string) {
  return useQuery({
    queryKey: ['services', id],
    queryFn: () => api.services.get(id),
    enabled: !!id,
  })
}

export function useCreateService() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ projectId, data }: { projectId: string; data: Parameters<typeof api.services.create>[1] }) =>
      api.services.create(projectId, data),
    onSuccess: (_, { projectId }) => {
      queryClient.invalidateQueries({ queryKey: ['projects', projectId, 'services'] })
      queryClient.invalidateQueries({ queryKey: ['projects', projectId] })
      toast.success('Service created')
    },
    onError: (err) => toast.error(`Failed to create service: ${err.message}`),
  })
}

export function useDestroyService() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.services.destroy,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['projects'] })
      queryClient.invalidateQueries({ queryKey: ['services'] })
      toast.success('Service removed')
    },
    onError: (err) => toast.error(`Failed to remove service: ${err.message}`),
  })
}

export function useUpdateService() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: Parameters<typeof api.services.update>[1] }) =>
      api.services.update(id, data),
    onSuccess: (_, { id }) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
    },
  })
}

export function useDeployService() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.services.deploy,
    onSuccess: (_, id) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
      queryClient.invalidateQueries({ queryKey: ['services', id, 'deployments'] })
      toast.success('Deployment triggered')
    },
    onError: () => toast.error('Deployment failed. Check the deploy log for details.'),
  })
}

export function useScaleProcess() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, processName, quantity }: { id: string; processName: string; quantity: number }) =>
      api.services.scale(id, processName, quantity),
    onSuccess: (_, { id, processName, quantity }) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
      toast.success(`Scaled ${processName} to ${quantity}`)
    },
    onError: (err) => toast.error(`Scale failed: ${err.message}`),
  })
}

export function useSetEnvVar() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, key, value, source }: { id: string; key: string; value: string; source?: string }) =>
      api.services.setEnvVar(id, key, value, source),
    onSuccess: (_, { id, key }) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
      toast.success(`Set ${key}`)
    },
    onError: (err) => toast.error(`Failed to set variable: ${err.message}`),
  })
}

export function useUnsetEnvVar() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, key }: { id: string; key: string }) => api.services.unsetEnvVar(id, key),
    onSuccess: (_, { id, key }) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
      toast.success(`Removed ${key}`)
    },
    onError: (err) => toast.error(`Failed to remove variable: ${err.message}`),
  })
}

export function useAddDomain() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, hostname, port }: { id: string; hostname: string; port: number }) =>
      api.services.addDomain(id, hostname, port),
    onSuccess: (_, { id, hostname }) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
      toast.success(`Added domain ${hostname}`)
    },
    onError: (err) => toast.error(`Failed to add domain: ${err.message}`),
  })
}

export function useRemoveDomain() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, hostname }: { id: string; hostname: string }) => api.services.removeDomain(id, hostname),
    onSuccess: (_, { id, hostname }) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
      toast.success(`Removed domain ${hostname}`)
    },
    onError: (err) => toast.error(`Failed to remove domain: ${err.message}`),
  })
}

export function useAddStorageMount() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, hostPath, containerPath }: { id: string; hostPath: string; containerPath: string }) =>
      api.services.addStorageMount(id, hostPath, containerPath),
    onSuccess: (_, { id }) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
      toast.success('Storage mount added')
    },
    onError: (err) => toast.error(`Failed to add storage: ${err.message}`),
  })
}

export function useRemoveStorageMount() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, hostPath }: { id: string; hostPath: string }) => api.services.removeStorageMount(id, hostPath),
    onSuccess: (_, { id }) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
      toast.success('Storage mount removed')
    },
    onError: (err) => toast.error(`Failed to remove storage: ${err.message}`),
  })
}

export function useServiceLogs(id: string) {
  return useQuery({
    queryKey: ['services', id, 'logs'],
    queryFn: () => api.services.logs(id),
    enabled: !!id,
    refetchInterval: 5000,
  })
}

export function useServiceMetrics(id: string) {
  return useQuery({
    queryKey: ['services', id, 'metrics'],
    queryFn: () => api.services.metrics(id),
    enabled: !!id,
    refetchInterval: 5000,
  })
}

export function useServiceDeployments(id: string) {
  return useQuery({
    queryKey: ['services', id, 'deployments'],
    queryFn: () => api.services.deployments(id),
    enabled: !!id,
  })
}

export function useLinkService() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, targetId }: { id: string; targetId: string }) => api.services.link(id, targetId),
    onSuccess: (_, { id }) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
      queryClient.invalidateQueries({ queryKey: ['projects'] })
      toast.success('Service linked')
    },
    onError: (err) => toast.error(`Link failed: ${err.message}`),
  })
}

export function useUnlinkService() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, targetId }: { id: string; targetId: string }) => api.services.unlink(id, targetId),
    onSuccess: (_, { id }) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
      queryClient.invalidateQueries({ queryKey: ['projects'] })
      toast.success('Service unlinked')
    },
    onError: (err) => toast.error(`Unlink failed: ${err.message}`),
  })
}

export function useBackupService() {
  return useMutation({
    mutationFn: (id: string) => api.services.backup(id),
    onSuccess: () => toast.success('Backup created'),
    onError: (err) => toast.error(`Backup failed: ${err.message}`),
  })
}

export function useRestoreService() {
  return useMutation({
    mutationFn: (id: string) => api.services.restore(id),
    onSuccess: () => toast.success('Restore initiated'),
    onError: (err) => toast.error(`Restore failed: ${err.message}`),
  })
}

export function useStartService() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.services.start,
    onSuccess: (_, id) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
      queryClient.invalidateQueries({ queryKey: ['services', id, 'container-status'] })
      toast.success('Service started')
    },
    onError: (err) => toast.error(`Start failed: ${err.message}`),
  })
}

export function useStopService() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.services.stop,
    onSuccess: (_, id) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
      queryClient.invalidateQueries({ queryKey: ['services', id, 'container-status'] })
      toast.success('Service stopped')
    },
    onError: (err) => toast.error(`Stop failed: ${err.message}`),
  })
}

export function useRestartService() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.services.restart,
    onSuccess: (_, id) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
      queryClient.invalidateQueries({ queryKey: ['services', id, 'container-status'] })
      toast.success('Service restarted')
    },
    onError: (err) => toast.error(`Restart failed: ${err.message}`),
  })
}

export function useRebuildService() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.services.rebuild,
    onSuccess: (_, id) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
      queryClient.invalidateQueries({ queryKey: ['services', id, 'container-status'] })
      toast.success('Service rebuilt')
    },
    onError: (err) => toast.error(`Rebuild failed: ${err.message}`),
  })
}

export function useRollbackService() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, deploymentId }: { id: string; deploymentId: string }) =>
      api.services.rollback(id, deploymentId),
    onSuccess: (_, { id }) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
      queryClient.invalidateQueries({ queryKey: ['services', id, 'deployments'] })
      toast.success('Rollback initiated')
    },
    onError: (err) => toast.error(`Rollback failed: ${err.message}`),
  })
}

export function useDeployment(deploymentId: string | null) {
  return useQuery({
    queryKey: ['deployments', deploymentId],
    queryFn: () => api.services.deployment(deploymentId!),
    enabled: !!deploymentId,
  })
}

export function useContainerStatus(id: string) {
  return useQuery({
    queryKey: ['services', id, 'container-status'],
    queryFn: () => api.services.containerStatus(id),
    enabled: !!id,
    refetchInterval: 10000,
  })
}
