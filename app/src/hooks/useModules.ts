import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { api } from '@/lib/api'

export function useModules() {
  return useQuery({
    queryKey: ['modules'],
    queryFn: () => api.modules.list(),
  })
}

export const BUILDERS = [
  { id: "herokuish", name: "Herokuish", description: "Heroku-compatible buildpack-based builder" },
  { id: "pack", name: "Cloud Native Buildpacks", description: "Modern OCI-compliant buildpacks via pack" },
  { id: "dockerfile", name: "Dockerfile", description: "Build from a Dockerfile in your repo" },
  { id: "nixpacks", name: "Nixpacks", description: "Auto-detect language and build with Nix" },
  { id: "railpack", name: "Railpack", description: "Railway's modern buildpack alternative" },
  { id: "lambda", name: "AWS Lambda", description: "Package for AWS Lambda deployment" },
  { id: "null", name: "Null Builder", description: "Skip build, use existing image" }
]

export function useBuilders() {
  return { data: BUILDERS, isLoading: false }
}

export function useNetworks() {
  return useQuery({
    queryKey: ['networks'],
    queryFn: () => api.networks.list(),
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
