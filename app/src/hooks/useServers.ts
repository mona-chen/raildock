import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { api } from '@/lib/api'
import type { ServerTestResult } from '@/lib/api'
import type { DockerContainer } from '@/types'

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

export function useTestServer() {
  return useMutation<ServerTestResult, Error, { host: string; sshUser?: string }>({
    mutationFn: api.servers.test,
  })
}

export function useProvisionServer() {
  return useMutation<{ setupId: string }, Error, { host: string; adminUser?: string; setupId: string }>({
    mutationFn: api.servers.provision,
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
