import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { api } from '@/lib/api'

export function useManifest(projectId: string) {
  return useQuery({
    queryKey: ['projects', projectId, 'manifest'],
    queryFn: () => api.manifest.get(projectId),
    enabled: !!projectId,
  })
}

export function useManifestStatus(projectId: string) {
  return useQuery({
    queryKey: ['projects', projectId, 'manifest', 'status'],
    queryFn: () => api.manifest.status(projectId),
    enabled: !!projectId,
    refetchInterval: 10000,
  })
}

export function useUpdateManifest() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ projectId, content, format }: { projectId: string; content: string; format?: string }) =>
      api.manifest.update(projectId, content, format),
    onSuccess: (_, { projectId }) => {
      queryClient.invalidateQueries({ queryKey: ['projects', projectId, 'manifest'] })
      queryClient.invalidateQueries({ queryKey: ['projects', projectId, 'manifest', 'status'] })
      toast.success('Manifest updated')
    },
    onError: (err) => toast.error(`Failed to update manifest: ${err.message}`),
  })
}

export function useManifestPreview() {
  return useMutation({
    mutationFn: ({ projectId }: { projectId: string }) =>
      api.manifest.preview(projectId),
    onError: (err) => toast.error(`Preview failed: ${err.message}`),
  })
}

export function useManifestApply() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ projectId }: { projectId: string }) =>
      api.manifest.apply(projectId),
    onSuccess: (_, { projectId }) => {
      queryClient.invalidateQueries({ queryKey: ['projects', projectId, 'manifest'] })
      queryClient.invalidateQueries({ queryKey: ['projects', projectId, 'manifest', 'status'] })
      queryClient.invalidateQueries({ queryKey: ['projects', projectId, 'services'] })
      toast.success('Manifest changes queued')
    },
    onError: (err) => toast.error(`Failed to apply manifest: ${err.message}`),
  })
}
