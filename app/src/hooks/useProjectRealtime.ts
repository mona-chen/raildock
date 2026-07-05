import { useEffect, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { getCable, isCableAvailable } from '@/lib/cable'
import { useRealtimeState } from './useRealtimeState'

interface ProjectEvent {
  type: 'deployment' | 'activity' | 'manifest_apply' | 'manifest_preview' | 'manifest_preview_error' | 'template_deploy'
  service_id?: string
  deployment_id?: string
  status?: string
  message?: string
  details?: string[]
}

export function useProjectRealtime(projectId: string) {
  const queryClient = useQueryClient()
  const { state, expectConnection, markLive, markFallback, markUnavailable } = useRealtimeState()
  const [lastConfirmedAt, setLastConfirmedAt] = useState<string | null>(null)

  useEffect(() => {
    if (!projectId || !isCableAvailable()) {
      markUnavailable()
      return
    }
    expectConnection()

    const subscription = getCable().subscriptions.create(
      { channel: 'ProjectChannel', project_id: projectId },
      {
        connected() { markLive(); setLastConfirmedAt(new Date().toISOString()) },
        disconnected() { expectConnection('reconnecting') },
        rejected() { markFallback() },
        received(event: ProjectEvent) {
          setLastConfirmedAt(new Date().toISOString())
          if (event.type === 'deployment' || event.type === 'template_deploy') {
            queryClient.invalidateQueries({ queryKey: ['projects', projectId, 'services'] })
            if (event.service_id) {
              queryClient.invalidateQueries({ queryKey: ['services', String(event.service_id)] })
              queryClient.invalidateQueries({ queryKey: ['services', String(event.service_id), 'deployments'] })
            }
            if (event.deployment_id) queryClient.invalidateQueries({ queryKey: ['deployments', String(event.deployment_id)] })
          } else if (event.type === 'activity') {
            queryClient.invalidateQueries({ queryKey: ['projects', projectId, 'activity'] })
          } else if (event.type.startsWith('manifest')) {
            queryClient.invalidateQueries({ queryKey: ['projects', projectId, 'manifest'] })
            if (event.type === 'manifest_apply' && event.status === 'failed') {
              const detail = event.details?.filter(Boolean).join('\n')
              toast.error(event.message || 'Manifest apply failed', {
                description: detail || 'Check the service logs or Activity tab for details.',
              })
            }
          }
        },
      },
    )

    return () => subscription.unsubscribe()
  }, [projectId, queryClient, expectConnection, markFallback, markLive, markUnavailable])

  return { connectionState: state, lastConfirmedAt }
}
