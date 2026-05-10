import { useQuery } from '@tanstack/react-query'
import { api } from '@/lib/api'

export function useActivity(projectId?: string) {
  return useQuery({
    queryKey: projectId ? ['projects', projectId, 'activity'] : ['activity', 'all'],
    queryFn: () => api.activity.list(projectId),
    enabled: projectId ? !!projectId : true,
  })
}
