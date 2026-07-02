import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { organizationsApi } from '@/lib/api'
import { toast } from 'sonner'
import type { BackupDestination } from '@/types'

const QUERY_KEY = (organizationId: string) => ['organizations', organizationId, 'backup-destinations']

export function useBackupDestinations(organizationId?: string) {
  return useQuery({
    queryKey: QUERY_KEY(organizationId || ''),
    queryFn: () => organizationsApi.backupDestinations.list(organizationId!),
    enabled: !!organizationId,
  })
}

export function useCreateBackupDestination() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ organizationId, data }: { organizationId: string; data: Record<string, string> }) =>
      organizationsApi.backupDestinations.create(organizationId, data),
    onSuccess: (_, { organizationId }) => {
      queryClient.invalidateQueries({ queryKey: QUERY_KEY(organizationId) })
      toast.success('Backup destination verified and saved')
    },
    onError: (err: Error) => toast.error(`Failed to save destination: ${err.message}`),
  })
}

export function useUpdateBackupDestination() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ organizationId, destinationId, data }: { organizationId: string; destinationId: string; data: Record<string, string> }) =>
      organizationsApi.backupDestinations.update(organizationId, destinationId, data),
    onSuccess: (_, { organizationId }) => {
      queryClient.invalidateQueries({ queryKey: QUERY_KEY(organizationId) })
      toast.success('Backup destination updated')
    },
    onError: (err: Error) => toast.error(`Failed to update destination: ${err.message}`),
  })
}

export function useDeleteBackupDestination() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ organizationId, destinationId }: { organizationId: string; destinationId: string }) =>
      organizationsApi.backupDestinations.destroy(organizationId, destinationId),
    onSuccess: (_, { organizationId }) => {
      queryClient.invalidateQueries({ queryKey: QUERY_KEY(organizationId) })
      toast.success('Backup destination removed')
    },
    onError: (err: Error) => toast.error(`Failed to remove destination: ${err.message}`),
  })
}

export function useVerifyBackupDestination() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ organizationId, destinationId }: { organizationId: string; destinationId: string }) =>
      organizationsApi.backupDestinations.verify(organizationId, destinationId),
    onSuccess: (_, { organizationId }) => {
      queryClient.invalidateQueries({ queryKey: QUERY_KEY(organizationId) })
      toast.success('Destination connection verified')
    },
    onError: (err: Error) => toast.error(`Verification failed: ${err.message}`),
  })
}
