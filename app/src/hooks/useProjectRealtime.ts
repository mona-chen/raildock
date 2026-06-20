import { useEffect, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { getCable, isCableAvailable } from '@/lib/cable'

interface ProjectEvent {
  type: 'deployment' | 'activity' | 'manifest_apply' | 'manifest_preview' | 'manifest_preview_error' | 'template_deploy'
  service_id?: string
  deployment_id?: string
  status?: string
}

export function useProjectRealtime(projectId: string) {
  const queryClient = useQueryClient()
  const [connectionState, setConnectionState] = useState<'live' | 'reconnecting' | 'offline'>('offline')
  const [lastConfirmedAt, setLastConfirmedAt] = useState<string | null>(null)

  useEffect(() => {
    if (!projectId || !isCableAvailable()) return

    const subscription = getCable().subscriptions.create(
      { channel: 'ProjectChannel', project_id: projectId },
      {
        connected() { setConnectionState('live'); setLastConfirmedAt(new Date().toISOString()) },
        disconnected() { setConnectionState('reconnecting') },
        rejected() { setConnectionState('offline') },
        received(event: ProjectEvent) {
          setLastConfirmedAt(new Date().toISOString())
          queryClient.invalidateQueries({ queryKey: ['projects', projectId, 'services'] })
          queryClient.invalidateQueries({ queryKey: ['projects', projectId, 'activity'] })
          if (event.service_id) {
            queryClient.invalidateQueries({ queryKey: ['services', String(event.service_id)] })
            queryClient.invalidateQueries({ queryKey: ['services', String(event.service_id), 'deployments'] })
          }
          if (event.deployment_id) queryClient.invalidateQueries({ queryKey: ['deployments', String(event.deployment_id)] })
          if (event.type.startsWith('manifest')) {
            queryClient.invalidateQueries({ queryKey: ['projects', projectId, 'manifest'] })
          }
        },
      },
    )

    return () => subscription.unsubscribe()
  }, [projectId, queryClient])

  return { connectionState, lastConfirmedAt }
}
