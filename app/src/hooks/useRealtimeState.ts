import { useCallback, useEffect, useRef, useState } from 'react'

export type RealtimeState = 'connecting' | 'live' | 'reconnecting' | 'fallback' | 'unavailable'

export function useRealtimeState(fallbackDelay = 8000) {
  const [state, setState] = useState<RealtimeState>('connecting')
  const timerRef = useRef<number | null>(null)

  const clearTimer = useCallback(() => {
    if (timerRef.current !== null) window.clearTimeout(timerRef.current)
    timerRef.current = null
  }, [])

  const expectConnection = useCallback((next: 'connecting' | 'reconnecting' = 'connecting') => {
    clearTimer()
    setState(next)
    timerRef.current = window.setTimeout(() => setState('fallback'), fallbackDelay)
  }, [clearTimer, fallbackDelay])

  const markLive = useCallback(() => {
    clearTimer()
    setState('live')
  }, [clearTimer])

  const markFallback = useCallback(() => {
    clearTimer()
    setState('fallback')
  }, [clearTimer])

  const markUnavailable = useCallback(() => {
    clearTimer()
    setState('unavailable')
  }, [clearTimer])

  useEffect(() => clearTimer, [clearTimer])

  return { state, expectConnection, markLive, markFallback, markUnavailable }
}

export function realtimeStateLabel(state: RealtimeState) {
  switch (state) {
    case 'live': return 'Live'
    case 'connecting': return 'Connecting'
    case 'reconnecting': return 'Reconnecting'
    case 'fallback': return 'Auto-refresh'
    case 'unavailable': return 'Updates unavailable'
  }
}
