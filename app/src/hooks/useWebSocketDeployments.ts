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
  sequence?: number
}

export function useWebSocketDeployments(serviceId: string) {
  const [lastUpdate, setLastUpdate] = useState<DeploymentUpdate | null>(null)
  const [isConnected, setIsConnected] = useState(false)
  const [isRejected, setIsRejected] = useState(false)
  const logMapRef = useRef<Record<string, string>>({})
  const sequenceRef = useRef<Record<string, number>>({})
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
            const previousSequence = sequenceRef.current[data.deployment_id] || 0
            if (data.sequence && data.sequence <= previousSequence) return
            if (data.sequence && previousSequence && data.sequence > previousSequence + 1) {
              queryClient.invalidateQueries({ queryKey: ['deployments', data.deployment_id] })
            }
            if (data.sequence) sequenceRef.current[data.deployment_id] = data.sequence
            logMapRef.current[data.deployment_id] = (logMapRef.current[data.deployment_id] || '') + data.log_chunk
            setLogMap({ ...logMapRef.current })
            queryClient.setQueryData(['deployments', data.deployment_id], (current: Record<string, unknown> | undefined) => current ? {
              ...current,
              status: data.status,
              deployLog: `${String(current.deployLog || '')}${data.log_chunk}`,
              eventSequence: data.sequence || current.eventSequence,
            } : current)
          }
          if (!data.log_chunk || data.status === 'succeeded' || data.status === 'failed' || data.status === 'cancelled') invalidate()
        },
      }
    )

    return () => {
      subscription.unsubscribe()
      setIsConnected(false)
    }
  }, [serviceId, invalidate, queryClient])

  return { lastUpdate, isConnected, isRejected, logMap }
}
