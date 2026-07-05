import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useMemo } from 'react'
import { toast } from 'sonner'
import { api } from '@/lib/api'

export function useModules() {
  return useQuery({
    queryKey: ['modules'],
    queryFn: () => api.modules.list(),
  })
}

export function useServiceSubtypes(serviceType?: string) {
  const { data: modules = [] } = useModules()
  return useMemo(() => {
    if (!serviceType) return []
    return modules.flatMap((m) => m.serviceSubtypes).filter((s) => s.serviceType === serviceType)
  }, [modules, serviceType])
}

export function useBuilders(sourceType?: string) {
  const { data: modules = [], isLoading } = useModules()
  const builders = useMemo(() => {
    const all = modules.flatMap((m) => m.builders || [])
    if (!sourceType) return all
    return all.filter((b) => b.sourceTypes.includes(sourceType))
  }, [modules, sourceType])
  return { data: builders, isLoading }
}

export function useBuilder(slug?: string) {
  const { data: builders = [] } = useBuilders()
  return useMemo(() => builders.find((b) => b.slug === slug), [builders, slug])
}

export function useInstallPlugin() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { sourceUrl: string; sourceType?: string; sourceRef?: string }) =>
      api.modules.install(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['modules'] })
      toast.success('Plugin installation queued')
    },
    onError: (err: Error) => toast.error(`Install failed: ${err.message}`),
  })
}

export function useEnablePlugin() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (slug: string) => api.modules.enable(slug),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['modules'] })
      toast.success('Plugin enabled')
    },
    onError: (err: Error) => toast.error(`Enable failed: ${err.message}`),
  })
}

export function useDisablePlugin() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (slug: string) => api.modules.disable(slug),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['modules'] })
      toast.success('Plugin disabled')
    },
    onError: (err: Error) => toast.error(`Disable failed: ${err.message}`),
  })
}

export function useUninstallPlugin() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (slug: string) => api.modules.uninstall(slug),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['modules'] })
      toast.success('Plugin uninstallation queued')
    },
    onError: (err: Error) => toast.error(`Uninstall failed: ${err.message}`),
  })
}

export function usePluginSettings(slug?: string) {
  return useQuery({
    queryKey: ['modules', slug, 'settings'],
    queryFn: () => api.modules.settings(slug!),
    enabled: Boolean(slug),
  })
}

export function useUpdatePluginSettings() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ slug, settings }: { slug: string; settings: Record<string, string | number | boolean> }) =>
      api.modules.updateSettings(slug, settings),
    onSuccess: (_, { slug }) => {
      queryClient.invalidateQueries({ queryKey: ['modules', slug, 'settings'] })
      queryClient.invalidateQueries({ queryKey: ['modules'] })
      toast.success('Plugin settings saved')
    },
    onError: (err: Error) => toast.error(`Save failed: ${err.message}`),
  })
}

export function useNetworks(serverId?: string) {
  return useQuery({
    queryKey: ['networks', serverId],
    queryFn: () => api.networks.list(serverId!),
    enabled: Boolean(serverId),
  })
}

export function useValidateNetwork() {
  return useMutation({
    mutationFn: ({ serverId, network }: { serverId: string; network: string }) =>
      api.networks.validate(serverId, network),
    onSuccess: ({ network }) => toast.success(`Traefik network ${network} verified`),
    onError: (err) => toast.error(`Network validation failed: ${err.message}`),
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
