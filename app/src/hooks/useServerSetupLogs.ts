import { useEffect, useRef, useState } from 'react'
import { getCable, isCableAvailable } from '@/lib/cable'
import { api } from '@/lib/api'
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
    if (!setupId) {
      setState('idle')
      return
    }

    setState('connecting')
    setError(null)
    setServerId(null)
    setLogs([])

    let cancelled = false

    if (isCableAvailable()) {
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
    }

    // Polling fallback: the WebSocket may be blocked or slow to connect, so
    // mirror the setup state from the backend cache every few seconds.
    let intervalId: ReturnType<typeof setInterval> | null = null

    const applyPayload = (payload: {
      state?: 'connecting' | 'live' | 'completed' | 'failed'
      logs?: SetupLog[]
      error?: string
      serverId?: string
    }) => {
      if (payload.logs?.length) setLogs(payload.logs)
      if (payload.state) setState(payload.state)
      if (payload.error) setError(payload.error)
      if (payload.serverId) setServerId(payload.serverId)
    }

    const poll = async () => {
      try {
        const data = await api.servers.provisionStatus(setupId)
        if (cancelled) return

        applyPayload({
          state: data.state,
          logs: data.logs,
          error: data.error,
          serverId: data.serverId,
        })

        if (data.state === 'completed' || data.state === 'failed') {
          if (intervalId) clearInterval(intervalId)
        }
      } catch (e) {
        debugWarn('[SetupProgress] poll failed for', setupId, e)
      }
    }

    poll()
    intervalId = setInterval(poll, 2000)

    return () => {
      cancelled = true
      if (intervalId) clearInterval(intervalId)
      subscriptionRef.current?.unsubscribe()
      subscriptionRef.current = null
    }
  }, [setupId])

  return { logs, state, error, serverId }
}
