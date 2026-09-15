import { useQuery } from '@tanstack/react-query'
import { organizationsApi } from '@/lib/api'

const QUERY_KEY = (organizationId: string) => ['organizations', organizationId, 'data-safety']

/**
 * Audit of everything in this organization that is one failure away from being
 * unrecoverable: datastores without a verified destination, volumes without
 * snapshots, and destinations that no longer verify.
 */
export function useDataSafety(organizationId?: string) {
  return useQuery({
    queryKey: QUERY_KEY(organizationId || ''),
    queryFn: () => organizationsApi.dataSafety(organizationId!),
    enabled: !!organizationId,
    refetchInterval: 60000,
  })
}
