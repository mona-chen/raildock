import { useEffect, useState, useCallback, useRef } from 'react'
import { getCable, isCableAvailable, reconnectCable } from '@/lib/cable'
import { useQueryClient } from '@tanstack/react-query'
import { debugLog, debugWarn } from '@/lib/debug'

interface DeploymentUpdate {
  deployment_id: string
  status: 'pending' | 'building' | 'deploying' | 'succeeded' | 'failed' | 'cancelled'
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
          debugLog('[WebSocket] DeploymentsChannel connected for', serviceId)
          setIsConnected(true)
          setIsRejected(false)
        },
        disconnected() {
          debugLog('[WebSocket] DeploymentsChannel disconnected for', serviceId)
          setIsConnected(false)
        },
        rejected() {
          debugWarn('[WebSocket] DeploymentsChannel rejected for', serviceId)
          setIsConnected(false)
          setIsRejected(true)
        },
        received(data: DeploymentUpdate) {
          debugLog('[WebSocket] DeploymentsChannel received:', data)
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
