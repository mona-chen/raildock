import { useEffect, useRef, useState, useCallback } from 'react'
import { getCable, isCableAvailable } from '@/lib/cable'

interface LogLine {
  timestamp: string
  process_type: string
  message: string
}

export function useWebSocketLogs(serviceId: string) {
  const [lines, setLines] = useState<LogLine[]>([])
  const [isConnected, setIsConnected] = useState(false)
  const subscriptionRef = useRef<{ unsubscribe: () => void } | null>(null)

  const clear = useCallback(() => setLines([]), [])

  useEffect(() => {
    if (!isCableAvailable() || !serviceId) return

    const subscription = getCable().subscriptions.create(
      { channel: 'LogsChannel', service_id: serviceId },
      {
        connected() {
          console.log('[WebSocket] LogsChannel connected for', serviceId)
          setIsConnected(true)
        },
        disconnected() {
          console.log('[WebSocket] LogsChannel disconnected for', serviceId)
          setIsConnected(false)
        },
        rejected() {
          console.warn('[WebSocket] LogsChannel rejected for', serviceId)
          setIsConnected(false)
        },
        received(data: { timestamp?: string; process_type?: string; line?: string; message?: string }) {
          const message = data.line || data.message || ''
          if (!message) return
          setLines((prev) => [
            ...prev,
            {
              timestamp: data.timestamp || new Date().toISOString(),
              process_type: data.process_type || 'app',
              message,
            },
          ])
        },
      }
    )

    subscriptionRef.current = subscription

    return () => {
      subscription.unsubscribe()
      subscriptionRef.current = null
      setIsConnected(false)
    }
  }, [serviceId])

  return { lines, isConnected, clear }
}
