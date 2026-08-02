import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { api } from '@/lib/api'
import type { Service, StorageMountKind, BackupSchedule } from '@/types'

export function useServices(projectId: string) {
  return useQuery({
    queryKey: ['projects', projectId, 'services'],
    queryFn: () => api.services.list(projectId),
    enabled: !!projectId,
    refetchInterval: 15000,
  })
}

export function useService(id: string) {
  return useQuery({
    queryKey: ['services', id],
    queryFn: () => api.services.get(id),
    enabled: !!id,
    refetchInterval: 15000,
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
      queryClient.invalidateQueries({ queryKey: ['projects'] })
    },
  })
}

export function useUpdateServiceConfig() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, config }: { id: string; config: Record<string, unknown> }) =>
      api.services.update(id, { config }),
    onSuccess: (_, { id }) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
      toast.success('Settings synced to Dokku')
    },
    onError: (err) => toast.error(`Failed to sync settings: ${err.message}`),
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
    onSuccess: (data, { id, key }) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
      if (data?.restart_deployment_id) {
        queryClient.invalidateQueries({ queryKey: ['services', id, 'deployments'] })
        toast.success(`Saved ${key} — restarting to apply`)
      } else {
        toast.success(`Saved ${key}`)
      }
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

export function useSetEnvVars() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, vars }: { id: string; vars: { key: string; value: string }[] }) =>
      api.services.setEnvVars(id, vars),
    onSuccess: (data, { id }) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
      if (data?.restart_deployment_id) {
        queryClient.invalidateQueries({ queryKey: ['services', id, 'deployments'] })
        toast.success(`Saved ${data.updated} variable(s) — restarting to apply`)
      } else {
        toast.success(`Saved ${data?.updated ?? 0} variable(s)`)
      }
    },
    onError: (err) => toast.error(`Failed to save variables: ${err.message}`),
  })
}

export function useAddDomain() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, hostname, port, targetPort }: { id: string; hostname: string; port: number; targetPort?: number }) =>
      api.services.addDomain(id, hostname, port, targetPort),
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

export function useGenerateDomain() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => api.services.generateDomain(id),
    onSuccess: (_, id) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
      toast.success('Domain generated')
    },
    onError: (err) => toast.error(`Failed to generate domain: ${err.message}`),
  })
}

export function useAddStorageMount() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, hostPath, containerPath, kind }: { id: string; hostPath?: string; containerPath: string; kind: StorageMountKind }) =>
      api.services.addStorageMount(id, { hostPath, containerPath, kind }),
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
    refetchInterval: 10000,
  })
}

export function useDatabaseInfo(id: string) {
  return useQuery({
    queryKey: ['services', id, 'database_info'],
    queryFn: () => api.services.databaseInfo(id),
    enabled: !!id,
    staleTime: 60000,
  })
}

export function useDataTables(id: string) {
  return useQuery({
    queryKey: ['services', id, 'data', 'tables'],
    queryFn: () => api.services.dataTables(id),
    enabled: !!id,
    staleTime: 30000,
  })
}

export function useDataTableRows(id: string, table: string | null, limit = 50, offset = 0) {
  return useQuery({
    queryKey: ['services', id, 'data', 'rows', table, limit, offset],
    queryFn: () => api.services.dataTableRows(id, table!, limit, offset),
    enabled: !!id && !!table,
    staleTime: 15000,
  })
}

export function useServiceMetrics(id: string) {
  return useQuery({
    queryKey: ['services', id, 'metrics'],
    queryFn: () => api.services.metrics(id),
    enabled: !!id,
    refetchInterval: 10000,
  })
}

export function useServiceMetricsHistory(id: string, hours = 24) {
  return useQuery({
    queryKey: ['services', id, 'metrics_history', hours],
    queryFn: () => api.services.metricsHistory(id, hours),
    enabled: !!id,
    refetchInterval: 60000,
  })
}

export function useServiceDeployments(id: string) {
  return useQuery({
    queryKey: ['services', id, 'deployments'],
    queryFn: () => api.services.deployments(id),
    enabled: !!id,
    refetchInterval: (query) => query.state.data?.some((deployment) => ['pending', 'building', 'deploying'].includes(deployment.status)) ? 3000 : false,
  })
}

export function useBackups(id: string) {
  return useQuery({
    queryKey: ['services', id, 'backups'],
    queryFn: () => api.services.backups(id),
    enabled: !!id,
    refetchInterval: (query) => query.state.data?.some((backup) => backup.status === 'pending' || backup.status === 'running') ? 3000 : false,
  })
}

export function useVolumeSnapshots(id: string) {
  return useQuery({
    queryKey: ['services', id, 'snapshots'],
    queryFn: () => api.services.snapshots(id),
    enabled: !!id,
    refetchInterval: (query) => query.state.data?.some((backup) => backup.status === 'pending' || backup.status === 'running') ? 3000 : false,
  })
}

export function useRecovery(id: string) {
  return useQuery({ queryKey: ['services', id, 'recovery'], queryFn: () => api.services.recovery(id), enabled: !!id, refetchInterval: 10000 })
}

export function useCreateBackupDestination() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: Record<string, string> }) => api.services.createBackupDestination(id, data),
    onSuccess: (_, { id }) => { queryClient.invalidateQueries({ queryKey: ['services', id, 'recovery'] }); toast.success('Encrypted destination verified') },
    onError: (err) => toast.error(`Destination failed: ${err.message}`),
  })
}

export function useSnapshotVolume() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, storageMountId, backupDestinationIds }: { id: string; storageMountId: string; backupDestinationIds?: string[] }) => api.services.snapshotVolume(id, storageMountId, backupDestinationIds),
    onSuccess: (_, { id }) => {
      queryClient.invalidateQueries({ queryKey: ['services', id, 'backups'] })
      queryClient.invalidateQueries({ queryKey: ['services', id, 'snapshots'] })
      toast.success('Volume snapshot queued')
    },
    onError: (err) => toast.error(`Snapshot failed: ${err.message}`),
  })
}

export function useCreateSnapshotSchedule() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: { frequency: string; retentionCount: number; storageMountId: string; destinationIds?: string[] } }) =>
      api.services.createSnapshotSchedule(id, data),
    onSuccess: (_, { id }) => {
      queryClient.invalidateQueries({ queryKey: ['services', id, 'backup_schedules'] })
      toast.success('Snapshot schedule created')
    },
    onError: (err) => toast.error(`Failed to create schedule: ${err.message}`),
  })
}

export function useConfigurePitr() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, destinationId, retentionDays }: { id: string; destinationId: string; retentionDays: number }) => api.services.configurePitr(id, destinationId, retentionDays),
    onSuccess: (_, { id }) => { queryClient.invalidateQueries({ queryKey: ['services', id, 'recovery'] }); toast.success('Point-in-time recovery enabled') },
    onError: (err) => toast.error(`PITR setup failed: ${err.message}`),
  })
}

export function useRunRestoreDrill() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, backupId }: { id: string; backupId: string }) => api.services.runRestoreDrill(id, backupId),
    onSuccess: (_, { id }) => { queryClient.invalidateQueries({ queryKey: ['services', id, 'recovery'] }); toast.success('Isolated restore drill queued') },
    onError: (err) => toast.error(`Drill failed: ${err.message}`),
  })
}

export function useBackupSchedules(id: string) {
  return useQuery<BackupSchedule[]>({
    queryKey: ['services', id, 'backup_schedules'],
    queryFn: () => api.services.backupSchedules(id),
    enabled: !!id,
  })
}

export function useCreateBackupSchedule() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: { frequency: string; retentionCount: number; destinationIds?: string[] } }) =>
      api.services.createBackupSchedule(id, data),
    onSuccess: (_, { id }) => {
      queryClient.invalidateQueries({ queryKey: ['services', id, 'backup_schedules'] })
      toast.success('Backup schedule created')
    },
    onError: (err) => toast.error(`Failed to create schedule: ${err.message}`),
  })
}

export function useDestroyBackupSchedule() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, scheduleId }: { id: string; scheduleId: string }) =>
      api.services.destroyBackupSchedule(id, scheduleId),
    onSuccess: (_, { id }) => {
      queryClient.invalidateQueries({ queryKey: ['services', id, 'backup_schedules'] })
      toast.success('Backup schedule removed')
    },
    onError: (err) => toast.error(`Failed to remove schedule: ${err.message}`),
  })
}

export function useLinkService() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, targetId }: { id: string; targetId: string }) => api.services.link(id, targetId),
    onSuccess: (_, { id, targetId }) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
      queryClient.invalidateQueries({ queryKey: ['services', targetId] })
      queryClient.invalidateQueries({ queryKey: ['services', id, 'linked-by'] })
      queryClient.invalidateQueries({ queryKey: ['services', targetId, 'linked-by'] })
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
    onMutate: async ({ id, targetId }) => {
      // Cancel outgoing refetches so they don't overwrite our optimistic update
      await queryClient.cancelQueries({ queryKey: ['services', targetId, 'linked-by'] })
      await queryClient.cancelQueries({ queryKey: ['services', id, 'linked-by'] })
      // Snapshot previous values
      const prevTargetLinkedBy = queryClient.getQueryData<Service[]>(['services', targetId, 'linked-by'])
      const prevAppLinkedBy = queryClient.getQueryData<Service[]>(['services', id, 'linked-by'])
      // Optimistically remove from target's linked-by list
      queryClient.setQueryData(['services', targetId, 'linked-by'], (old: Service[] | undefined) =>
        old?.filter((s) => String(s.id) !== String(id)) ?? []
      )
      // Optimistically remove from app's linked-by list (reverse direction)
      queryClient.setQueryData(['services', id, 'linked-by'], (old: Service[] | undefined) =>
        old?.filter((s) => String(s.id) !== String(targetId)) ?? []
      )
      return { prevTargetLinkedBy, prevAppLinkedBy, id, targetId }
    },
    onError: (err, { id, targetId }, context) => {
      if (context?.prevTargetLinkedBy) {
        queryClient.setQueryData(['services', targetId, 'linked-by'], context.prevTargetLinkedBy)
      }
      if (context?.prevAppLinkedBy) {
        queryClient.setQueryData(['services', id, 'linked-by'], context.prevAppLinkedBy)
      }
      toast.error(`Unlink failed: ${err.message}`)
    },
    onSettled: (_data, _err, { id, targetId }) => {
      queryClient.invalidateQueries({ queryKey: ['services', id] })
      queryClient.invalidateQueries({ queryKey: ['services', targetId] })
      queryClient.invalidateQueries({ queryKey: ['services', id, 'linked-by'] })
      queryClient.invalidateQueries({ queryKey: ['services', targetId, 'linked-by'] })
      queryClient.invalidateQueries({ queryKey: ['projects'] })
      toast.success('Service unlinked')
    },
  })
}

export function useLinkedByServices(id: string) {
  return useQuery({
    queryKey: ['services', id, 'linked-by'],
    queryFn: () => api.services.linkedBy(id),
    enabled: !!id,
  })
}

export function useBackupService() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (input: string | { id: string; backupDestinationIds?: string[] }) => {
      const { id, backupDestinationIds } = typeof input === 'string' ? { id: input, backupDestinationIds: undefined } : input
      return backupDestinationIds?.length ? api.services.backup(id, backupDestinationIds) : api.services.backup(id)
    },
    onSuccess: (_, input) => {
      const id = typeof input === 'string' ? input : input.id
      queryClient.invalidateQueries({ queryKey: ['services', id, 'backups'] })
      toast.success('Backup queued')
    },
    onError: (err) => toast.error(`Backup failed: ${err.message}`),
  })
}

export function useRestoreBackup() {
  return useMutation({
    mutationFn: ({ id, backupId }: { id: string; backupId: string }) => api.services.restoreBackup(id, backupId),
    onSuccess: () => toast.success('Restore completed'),
    onError: (err) => toast.error(`Restore failed: ${err.message}`),
  })
}

export function useDeleteBackup() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ id, backupId }: { id: string; backupId: string }) => api.services.deleteBackup(id, backupId),
    onSuccess: (_, { id }) => {
      queryClient.invalidateQueries({ queryKey: ['services', id, 'backups'] })
      toast.success('Backup deleted')
    },
    onError: (err) => toast.error(`Delete failed: ${err.message}`),
  })
}

export function useRestoreService() {
  return useMutation({
    mutationFn: ({ id, file }: { id: string; file?: File }) => api.services.restore(id, file),
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
    refetchInterval: (query) => query.state.data && ['pending', 'building', 'deploying'].includes(query.state.data.status) ? 3000 : false,
  })
}

export function useCancelDeployment() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (deploymentId: string) => api.services.cancelDeployment(deploymentId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['deployments'] })
      queryClient.invalidateQueries({ queryKey: ['services'] })
      toast.success('Deployment cancelled')
    },
    onError: (err) => toast.error(`Cancel failed: ${err.message}`),
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

export function useRunOneOff() {
  return useMutation({
    mutationFn: ({ id, command }: { id: string; command: string }) =>
      api.services.runOneOff(id, command),
    onError: (err) => toast.error(`Command failed: ${err.message}`),
  })
}

export function useEnterService() {
  return useMutation({
    mutationFn: ({ id, command }: { id: string; command: string }) =>
      api.services.enter(id, command),
    onError: (err) => toast.error(`Enter failed: ${err.message}`),
  })
}

export function useConfigShow(projectId: string, serviceId: string) {
  return useQuery({
    queryKey: ['projects', projectId, 'services', serviceId, 'config_show'],
    queryFn: () => api.services.configShow(projectId, serviceId),
    enabled: !!projectId && !!serviceId,
  })
}

export function useTraefikConfig(projectId: string, serviceId: string) {
  return useQuery({
    queryKey: ['projects', projectId, 'services', serviceId, 'traefik_config'],
    queryFn: () => api.services.traefikConfig(projectId, serviceId),
    enabled: !!projectId && !!serviceId,
  })
}

export function useStorageList(projectId: string, serviceId: string) {
  return useQuery({
    queryKey: ['projects', projectId, 'services', serviceId, 'storage_list'],
    queryFn: () => api.services.storageList(projectId, serviceId),
    enabled: !!projectId && !!serviceId,
  })
}

export function useBrowseStorageMount(id: string, storageMountId: string, path: string) {
  return useQuery({
    queryKey: ['services', id, 'storage_mounts', storageMountId, 'browse', path],
    queryFn: () => api.services.browseStorageMount(id, storageMountId, path),
    enabled: !!id && !!storageMountId,
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
    onError: (err) => toast.error(`Failed to deploy template: ${err.message}`),
  })
}
