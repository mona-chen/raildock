import { useEffect, useRef, useState, useCallback } from 'react'
import { getCable, isCableAvailable } from '@/lib/cable'
import { Terminal } from '@xterm/xterm'
import { FitAddon } from '@xterm/addon-fit'

interface TerminalMessage {
  type: 'data' | 'connected' | 'closed' | 'error'
  data?: string
}

export function useTerminal(serviceId: string, terminalRef: React.RefObject<HTMLDivElement | null>) {
  const [isConnected, setIsConnected] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const termRef = useRef<Terminal | null>(null)
  const fitAddonRef = useRef<FitAddon | null>(null)
  const subscriptionRef = useRef<{ unsubscribe: () => void; perform: (action: string, data?: Record<string, unknown>) => void } | null>(null)

  const sendData = useCallback((data: string) => {
    subscriptionRef.current?.perform('input', { data })
  }, [])

  const sendResize = useCallback((cols: number, rows: number) => {
    subscriptionRef.current?.perform('resize', { cols, rows })
  }, [])

  useEffect(() => {
    if (!isCableAvailable() || !serviceId || !terminalRef.current) return

    // Create terminal
    const term = new Terminal({
      cursorBlink: true,
      cursorStyle: 'block',
      fontSize: 13,
      fontFamily: 'monospace',
      theme: {
        background: '#0B0B0D',
        foreground: '#F0F1F3',
        cursor: '#8b5cf6',
        selectionBackground: 'rgba(139, 92, 246, 0.3)',
        black: '#1a1a1e',
        red: '#ef4444',
        green: '#22c55e',
        yellow: '#eab308',
        blue: '#3b82f6',
        magenta: '#8b5cf6',
        cyan: '#06b6d4',
        white: '#F0F1F3',
        brightBlack: '#4A4A55',
        brightRed: '#f87171',
        brightGreen: '#4ade80',
        brightYellow: '#facc15',
        brightBlue: '#60a5fa',
        brightMagenta: '#a78bfa',
        brightCyan: '#22d3ee',
        brightWhite: '#ffffff',
      },
      allowProposedApi: true,
    })

    const fitAddon = new FitAddon()
    term.loadAddon(fitAddon)
    term.open(terminalRef.current)
    fitAddon.fit()

    termRef.current = term
    fitAddonRef.current = fitAddon

    // Subscribe to ActionCable
    const subscription = getCable().subscriptions.create(
      { channel: 'TerminalChannel', service_id: serviceId },
      {
        connected() {
          setIsConnected(true)
          setError(null)
        },
        disconnected() {
          setIsConnected(false)
        },
        rejected() {
          setError('Terminal connection rejected')
          setIsConnected(false)
        },
        received(msg: TerminalMessage) {
          if (msg.type === 'data' && msg.data) {
            try {
              const decoded = atob(msg.data)
              term.write(decoded)
            } catch {
              term.write(msg.data)
            }
          } else if (msg.type === 'connected') {
            setIsConnected(true)
            setError(null)
          } else if (msg.type === 'closed') {
            setIsConnected(false)
            term.write('\r\n\r\n[Session closed]\r\n')
          } else if (msg.type === 'error' && msg.data) {
            setError(msg.data)
            term.write(`\r\n\r\n[Error: ${msg.data}]\r\n`)
          }
        },
      }
    )

    subscriptionRef.current = subscription as any

    // Forward keystrokes to backend
    const disposable = term.onData((data) => {
      sendData(data)
    })

    // Handle resize
    const resizeObserver = new ResizeObserver(() => {
      fitAddon.fit()
      const { cols, rows } = term
      sendResize(cols, rows)
    })
    resizeObserver.observe(terminalRef.current)

    // Initial resize
    const { cols, rows } = term
    sendResize(cols, rows)

    return () => {
      disposable.dispose()
      resizeObserver.disconnect()
      subscription.unsubscribe()
      term.dispose()
      termRef.current = null
      fitAddonRef.current = null
      subscriptionRef.current = null
      setIsConnected(false)
    }
  }, [serviceId, terminalRef, sendData, sendResize])

  return { isConnected, error, term: termRef.current }
}
