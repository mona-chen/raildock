import { useEffect, useRef, useState, useCallback } from 'react'
import { getCable, isCableAvailable } from '@/lib/cable'
import { debugLog, debugWarn } from '@/lib/debug'
import { useRealtimeState } from './useRealtimeState'

interface LogLine {
  timestamp: string
  process_type: string
  message: string
}

export function useWebSocketLogs(serviceId: string) {
  const [logState, setLogState] = useState<{ serviceId: string; lines: LogLine[] }>({ serviceId, lines: [] })
  const { state, expectConnection, markLive, markFallback, markUnavailable } = useRealtimeState()
  const subscriptionRef = useRef<{ unsubscribe: () => void } | null>(null)

  const clear = useCallback(() => setLogState({ serviceId, lines: [] }), [serviceId])

  useEffect(() => {
    if (!isCableAvailable() || !serviceId) {
      markUnavailable()
      return
    }
    expectConnection()

    const subscription = getCable().subscriptions.create(
      { channel: 'LogsChannel', service_id: serviceId },
      {
        connected() {
          debugLog('[WebSocket] LogsChannel connected for', serviceId)
          expectConnection()
        },
        disconnected() {
          debugLog('[WebSocket] LogsChannel disconnected for', serviceId)
          expectConnection('reconnecting')
        },
        rejected() {
          debugWarn('[WebSocket] LogsChannel rejected for', serviceId)
          markFallback()
        },
        received(data: { type?: string; state?: string; timestamp?: string; process_type?: string; line?: string; message?: string }) {
          if (data.type === 'stream_state') {
            if (data.state === 'live') markLive()
            else markFallback()
            return
          }
          const message = data.line || data.message || ''
          if (!message) return
          markLive()
          setLogState((current) => ({
            serviceId,
            lines: [
              ...(current.serviceId === serviceId ? current.lines : []),
              {
              timestamp: data.timestamp || new Date().toISOString(),
              process_type: data.process_type || 'app',
              message,
              },
            ],
          }))
        },
      }
    )

    subscriptionRef.current = subscription

    return () => {
      subscription.unsubscribe()
      subscriptionRef.current = null
    }
  }, [serviceId, expectConnection, markFallback, markLive, markUnavailable])

  const lines = logState.serviceId === serviceId ? logState.lines : []
  return { lines, connectionState: state, isConnected: state === 'live', clear }
}
