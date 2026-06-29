import { useEffect, useRef, useState } from 'react'
import { getCable, isCableAvailable } from '@/lib/cable'
import { debugLog, debugWarn } from '@/lib/debug'

interface SetupLog {
  line: string
  stream?: string
  timestamp: string
}

export function useServerSetupLogs(setupId: string | null) {
  const [logs, setLogs] = useState<SetupLog[]>([])
  const [state, setState] = useState<'idle' | 'connecting' | 'live' | 'completed' | 'failed'>('idle')
  const [error, setError] = useState<string | null>(null)
  const [serverId, setServerId] = useState<string | null>(null)
  const subscriptionRef = useRef<{ unsubscribe: () => void } | null>(null)

  useEffect(() => {
    if (!setupId || !isCableAvailable()) {
      if (!setupId) setState('idle')
      return
    }

    setState('connecting')
    setError(null)
    setServerId(null)

    const subscription = getCable().subscriptions.create(
      { channel: 'ServerSetupChannel', setup_id: setupId },
      {
        connected() {
          debugLog('[WebSocket] ServerSetupChannel connected for', setupId)
          setState('live')
        },
        disconnected() {
          debugLog('[WebSocket] ServerSetupChannel disconnected for', setupId)
        },
        rejected() {
          debugWarn('[WebSocket] ServerSetupChannel rejected for', setupId)
          setState('failed')
          setError('WebSocket connection rejected')
        },
        received(data: { type?: string; line?: string; stream?: string; error?: string; server_id?: string; host?: string }) {
          if (data.type === 'log') {
            setLogs((current) => [
              ...current,
              { line: data.line || '', stream: data.stream, timestamp: new Date().toISOString() },
            ])
          } else if (data.type === 'error') {
            setLogs((current) => [
              ...current,
              { line: data.error || data.line || 'Error', stream: 'stderr', timestamp: new Date().toISOString() },
            ])
          } else if (data.type === 'failed') {
            setState('failed')
            setError(data.error || 'Provisioning failed')
          } else if (data.type === 'completed') {
            setState('completed')
            if (data.server_id) setServerId(data.server_id)
          }
        },
      }
    )

    subscriptionRef.current = subscription

    return () => {
      subscription.unsubscribe()
      subscriptionRef.current = null
    }
  }, [setupId])

  return { logs, state, error, serverId }
}
