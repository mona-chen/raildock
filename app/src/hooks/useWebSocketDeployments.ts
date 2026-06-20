import { useEffect, useState, useCallback, useRef } from 'react'
import { getCable, isCableAvailable } from '@/lib/cable'
import { useQueryClient } from '@tanstack/react-query'
import { debugLog, debugWarn } from '@/lib/debug'
import { useRealtimeState } from './useRealtimeState'

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
  const [updateState, setUpdateState] = useState<{ serviceId: string; update: DeploymentUpdate | null }>({ serviceId, update: null })
  const { state, expectConnection, markLive, markFallback, markUnavailable } = useRealtimeState()
  const logMapRef = useRef<Record<string, string>>({})
  const sequenceRef = useRef<Record<string, number>>({})
  const [logState, setLogState] = useState<{ serviceId: string; logs: Record<string, string> }>({ serviceId, logs: {} })
  const queryClient = useQueryClient()

  const invalidate = useCallback(() => {
    queryClient.invalidateQueries({ queryKey: ['services', serviceId, 'deployments'] })
    queryClient.invalidateQueries({ queryKey: ['services', serviceId] })
  }, [queryClient, serviceId])

  useEffect(() => {
    if (!isCableAvailable() || !serviceId) {
      markUnavailable()
      return
    }

    logMapRef.current = {}
    sequenceRef.current = {}
    expectConnection()

    const subscription = getCable().subscriptions.create(
      { channel: 'DeploymentsChannel', service_id: serviceId },
      {
        connected() {
          debugLog('[WebSocket] DeploymentsChannel connected for', serviceId)
          markLive()
        },
        disconnected() {
          debugLog('[WebSocket] DeploymentsChannel disconnected for', serviceId)
          expectConnection('reconnecting')
        },
        rejected() {
          debugWarn('[WebSocket] DeploymentsChannel rejected for', serviceId)
          markFallback()
        },
        received(data: DeploymentUpdate) {
          debugLog('[WebSocket] DeploymentsChannel received:', data)
          setUpdateState({ serviceId, update: data })
          if (data.log_chunk && data.deployment_id) {
            const cached = queryClient.getQueryData<Record<string, unknown>>(['deployments', data.deployment_id])
            const previousSequence = sequenceRef.current[data.deployment_id] || Number(cached?.eventSequence || 0)
            if (data.sequence && data.sequence <= previousSequence) return
            if (data.sequence && previousSequence && data.sequence > previousSequence + 1) {
              sequenceRef.current[data.deployment_id] = data.sequence
              queryClient.invalidateQueries({ queryKey: ['deployments', data.deployment_id] })
              invalidate()
              return
            }
            if (data.sequence) sequenceRef.current[data.deployment_id] = data.sequence
            logMapRef.current[data.deployment_id] = (logMapRef.current[data.deployment_id] || '') + data.log_chunk
            setLogState({ serviceId, logs: { ...logMapRef.current } })
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
    }
  }, [serviceId, invalidate, queryClient, expectConnection, markFallback, markLive, markUnavailable])

  const lastUpdate = updateState.serviceId === serviceId ? updateState.update : null
  const logMap = logState.serviceId === serviceId ? logState.logs : {}
  return { lastUpdate, connectionState: state, isConnected: state === 'live', isRejected: state === 'fallback', logMap }
}
