import { useQuery, useMutation, useMutationState, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { api } from '@/lib/api'
import type { ServerTestResult } from '@/lib/api'
import type { DockerContainer } from '@/types'

export function useServers() {
  return useQuery({
    queryKey: ['servers'],
    queryFn: () => api.servers.list(),
    refetchInterval: 30000,
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

export function useTestServer() {
  return useMutation<ServerTestResult, Error, { host: string; sshUser?: string }>({
    mutationFn: api.servers.test,
  })
}

export function useProvisionServer() {
  return useMutation<{ setupId: string }, Error, Parameters<typeof api.servers.provision>[0]>({
    mutationFn: api.servers.provision,
  })
}

const VALIDATE_SERVER_KEY = ['servers', 'validate'] as const

export function useValidateServer() {
  const queryClient = useQueryClient()
  const mutation = useMutation({
    mutationKey: VALIDATE_SERVER_KEY,
    mutationFn: (id: string) => api.servers.validate(id),
    onSuccess: (result: { success?: boolean; error?: string }) => {
      if (result?.success === false) {
        toast.error(`Connection check failed${result.error ? `: ${result.error}` : ''}`)
      } else {
        toast.success('Connection verified')
      }
    },
    onError: (err) => toast.error(`Connection check failed: ${err.message}`),
    // Status, versions and proxy details change on every check, pass or fail.
    onSettled: () => queryClient.invalidateQueries({ queryKey: ['servers'] }),
  })
  // Track every in-flight check by server id so one card's check does not
  // show every other card as "Checking…".
  const pendingIds = useMutationState({
    filters: { mutationKey: VALIDATE_SERVER_KEY, status: 'pending' },
    select: (m) => String(m.state.variables),
  })
  return { ...mutation, pendingIds }
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

export function useTraefikOverview(serverId: string | undefined) {
  return useQuery({
    queryKey: ['servers', serverId, 'traefik'],
    queryFn: () => api.servers.traefik(serverId!),
    enabled: !!serverId,
    refetchInterval: 30000,
  })
}

export function useTraefikLogs(serverId: string | undefined, enabled: boolean, container?: string) {
  return useQuery({
    queryKey: ['servers', serverId, 'traefik', 'logs', container ?? 'auto'],
    queryFn: () => api.servers.traefikLogs(serverId!, 200, container),
    enabled: !!serverId && enabled,
  })
}

export function useTraefikAction(serverId: string | undefined) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ operation, confirmation }: { operation: 'start' | 'stop' | 'restart' | 'check'; confirmation?: string }) =>
      api.servers.traefikAction(serverId!, operation, confirmation),
    onSuccess: (result) => {
      queryClient.invalidateQueries({ queryKey: ['servers', serverId, 'traefik'] })
      queryClient.invalidateQueries({ queryKey: ['servers', serverId, 'traefik', 'logs'] })
      if (result.accepted) toast.success('Routing check queued')
      else if (result.operation === 'start') toast.success('Traefik started')
      else if (result.operation === 'stop') toast.success('Traefik stopped')
      else toast.success('Traefik restarted')
    },
    onError: (error: Error) => toast.error(error.message),
  })
}

export function useServerDockerContainers(serverId: string | undefined) {
  return useQuery({
    queryKey: ['servers', serverId, 'docker-imports'],
    queryFn: () => api.servers.dockerImports.list(serverId!),
    enabled: !!serverId,
  })
}

export function useImportDockerContainers(serverId: string | undefined) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ containers, projectId }: { containers: DockerContainer[]; projectId?: string }) =>
      api.servers.dockerImports.import(serverId!, { containers, projectId }),
    onSuccess: (result) => {
      queryClient.invalidateQueries({ queryKey: ['projects'] })
      queryClient.invalidateQueries({ queryKey: ['servers', serverId, 'docker-imports'] })
      const imported = result.results.filter((r) => r.success).length
      toast.success(`Imported ${imported} container${imported === 1 ? '' : 's'} into ${result.projectName}`)
    },
    onError: (err) => toast.error(`Import failed: ${err.message}`),
  })
}

export function useUnmanagedDatastores(serverId: string | undefined) {
  return useQuery({
    queryKey: ['servers', serverId, 'unmanaged-datastores'],
    queryFn: () => api.servers.unmanagedDatastores.list(serverId!),
    enabled: !!serverId,
  })
}

export function useAdoptDatastore(serverId: string | undefined) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ resourceName, projectId, name }: { resourceName: string; projectId: string; name?: string }) =>
      api.servers.unmanagedDatastores.adopt(serverId!, { resourceName, projectId, name }),
    onSuccess: (service) => {
      queryClient.invalidateQueries({ queryKey: ['servers', serverId, 'unmanaged-datastores'] })
      queryClient.invalidateQueries({ queryKey: ['projects'] })
      toast.success(
        `Adopted ${service.name} — RailDock can now back it up. Nothing on the host was changed.`
      )
    },
    onError: (err) => toast.error(`Adoption failed: ${err.message}`),
  })
}
