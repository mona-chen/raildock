import { useEffect, useState, useCallback, useRef } from 'react'
import { getCable, isCableAvailable, reconnectCable } from '@/lib/cable'
import { useQueryClient } from '@tanstack/react-query'

interface DeploymentUpdate {
  deployment_id: string
  status: 'pending' | 'deploying' | 'succeeded' | 'failed'
  message: string
  log_chunk?: string
  started_at?: string
  completed_at?: string
}

export function useWebSocketDeployments(serviceId: string) {
  const [lastUpdate, setLastUpdate] = useState<DeploymentUpdate | null>(null)
  const [isConnected, setIsConnected] = useState(false)
  const [isRejected, setIsRejected] = useState(false)
  const logMapRef = useRef<Record<string, string>>({})
  const [logMap, setLogMap] = useState<Record<string, string>>({})
  const queryClient = useQueryClient()

  const invalidate = useCallback(() => {
    queryClient.invalidateQueries({ queryKey: ['services', serviceId, 'deployments'] })
    queryClient.invalidateQueries({ queryKey: ['services', serviceId] })
  }, [queryClient, serviceId])

  useEffect(() => {
    if (!isCableAvailable() || !serviceId) {
      setIsConnected(false)
      setIsRejected(false)
      return
    }

    setIsRejected(false)

    const subscription = getCable().subscriptions.create(
      { channel: 'DeploymentsChannel', service_id: serviceId },
      {
        connected() {
          console.log('[WebSocket] DeploymentsChannel connected for', serviceId)
          setIsConnected(true)
          setIsRejected(false)
        },
        disconnected() {
          console.log('[WebSocket] DeploymentsChannel disconnected for', serviceId)
          setIsConnected(false)
        },
        rejected() {
          console.warn('[WebSocket] DeploymentsChannel rejected for', serviceId)
          setIsConnected(false)
          setIsRejected(true)
        },
        received(data: DeploymentUpdate) {
          console.log('[WebSocket] DeploymentsChannel received:', data)
          setLastUpdate(data)
          if (data.log_chunk && data.deployment_id) {
            logMapRef.current[data.deployment_id] = (logMapRef.current[data.deployment_id] || '') + data.log_chunk
            setLogMap({ ...logMapRef.current })
          }
          invalidate()
        },
      }
    )

    return () => {
      subscription.unsubscribe()
      setIsConnected(false)
    }
  }, [serviceId, invalidate])

  return { lastUpdate, isConnected, isRejected, logMap }
}
