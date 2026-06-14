import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { api } from '@/lib/api'
import { useAuthStore } from '@/stores/useAuthStore'

export function useGitSources() {
  const orgId = useAuthStore((s) => s.currentOrganizationId)
  return useQuery({
    queryKey: ['git-sources', orgId],
    queryFn: () => api.gitSources.list(orgId || undefined),
  })
}

export function useConnectGitSource() {
  const queryClient = useQueryClient()
  const orgId = useAuthStore((s) => s.currentOrganizationId)
  return useMutation({
    mutationFn: ({ provider, token }: { provider: string; token: string }) =>
      api.gitSources.connect(provider, token, orgId || undefined),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['git-sources'] })
      toast.success('Git source connected')
    },
    onError: (err: Error) => toast.error(`Connection failed: ${err.message}`),
  })
}

export function useDisconnectGitSource() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: api.gitSources.disconnect,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['git-sources'] })
      toast.success('Git source disconnected')
    },
    onError: (err: Error) => toast.error(`Disconnect failed: ${err.message}`),
  })
}

export function useGitSourceRepos(sourceId: string | undefined) {
  return useQuery({
    queryKey: ['git-source-repos', sourceId],
    queryFn: () => api.gitSources.repos(sourceId!),
    enabled: !!sourceId,
  })
}

export function useGitHubAppConfig() {
  return useQuery({
    queryKey: ['github-app-config'],
    queryFn: () => api.gitSources.config(),
    staleTime: 5 * 60 * 1000, // 5 minutes
  })
}

export function useSystemSettings() {
  return useQuery({
    queryKey: ['system-settings'],
    queryFn: () => api.adminSettings.list(),
    staleTime: 30 * 1000,
  })
}

export function useUpdateSystemSetting() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (settings: Record<string, string | undefined>) =>
      api.adminSettings.update(settings),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['system-settings'] })
      queryClient.invalidateQueries({ queryKey: ['github-app-config'] })
      toast.success('Settings saved')
    },
    onError: (err: Error) => toast.error(`Save failed: ${err.message}`),
  })
}

export function useTestGitHubApp() {
  return useMutation({
    mutationFn: () => api.adminSettings.testGitHubApp(),
    onSuccess: (data) => {
      if (data.valid) {
        toast.success(`GitHub App verified: ${data.name}`)
      } else {
        toast.error(data.error || 'GitHub App validation failed')
      }
    },
    onError: (err: Error) => toast.error(`Test failed: ${err.message}`),
  })
}

export function useCreateGitHubAppManifest() {
  return useMutation({
    mutationFn: () => api.adminSettings.createGitHubAppManifest(),
    onError: (err: Error) => toast.error(`Failed to create manifest: ${err.message}`),
  })
}

export function useFinishGitHubAppSetup() {
  const organizationId = useAuthStore((s) => s.currentOrganizationId)

  return useMutation({
    mutationFn: (installationId: string) =>
      api.adminSettings.finishGitHubAppSetup(installationId, organizationId || undefined),
    onSuccess: (data) => {
      window.location.href = data.authorizationUrl
    },
    onError: (err: Error) => toast.error(`Setup failed: ${err.message}`),
  })
}

export function useDeleteGitHubAppInstallation() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (installationId: string) => api.adminSettings.deleteGitHubAppInstallation(installationId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['git-sources'] })
      queryClient.invalidateQueries({ queryKey: ['github-app-config'] })
      toast.success('GitHub App uninstalled')
    },
    onError: (err: Error) => toast.error(`Uninstall failed: ${err.message}`),
  })
}

export function useDeleteGitHubApp() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: () => api.adminSettings.deleteGitHubApp(),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['git-sources'] })
      queryClient.invalidateQueries({ queryKey: ['github-app-config'] })
      queryClient.invalidateQueries({ queryKey: ['system-settings'] })
      toast.success('GitHub App disconnected from RailDock')
    },
    onError: (err: Error) => toast.error(`Disconnect failed: ${err.message}`),
  })
}
