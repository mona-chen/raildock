import { useEffect, useRef, useState, useCallback } from 'react'
import { getCable, isCableAvailable } from '@/lib/cable'
import { Terminal } from '@xterm/xterm'
import { FitAddon } from '@xterm/addon-fit'
import { WebLinksAddon } from '@xterm/addon-web-links'
import { SearchAddon } from '@xterm/addon-search'

interface TerminalMessage {
  type: 'data' | 'connected' | 'closed' | 'error'
  data?: string
}

export function useTerminal(
  serviceId: string,
  terminalRef: React.RefObject<HTMLDivElement | null>,
  shell: string = '/bin/sh'
) {
  const [isConnected, setIsConnected] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const termRef = useRef<Terminal | null>(null)
  const fitAddonRef = useRef<FitAddon | null>(null)
  const searchAddonRef = useRef<SearchAddon | null>(null)
  const subscriptionRef = useRef<{ unsubscribe: () => void; perform: (action: string, data?: Record<string, unknown>) => void } | null>(null)

  const sendData = useCallback((data: string) => {
    subscriptionRef.current?.perform('input', { data })
  }, [])

  const sendResize = useCallback((cols: number, rows: number) => {
    subscriptionRef.current?.perform('resize', { cols, rows })
  }, [])

  const findNext = useCallback((query: string) => {
    searchAddonRef.current?.findNext(query)
  }, [])

  const findPrevious = useCallback((query: string) => {
    searchAddonRef.current?.findPrevious(query)
  }, [])

  const clearSearch = useCallback(() => {
    searchAddonRef.current?.clearDecorations()
  }, [])

  useEffect(() => {
    if (!isCableAvailable() || !serviceId || !terminalRef.current) return

    // Create terminal with WebGL renderer if available
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
      scrollback: 10000,
    })

    const fitAddon = new FitAddon()
    const searchAddon = new SearchAddon()
    const webLinksAddon = new WebLinksAddon()

    term.loadAddon(fitAddon)
    term.loadAddon(searchAddon)
    term.loadAddon(webLinksAddon)

    term.open(terminalRef.current)

    // Try WebGL renderer for better performance (async load)
    import('@xterm/addon-webgl')
      .then(({ WebglAddon }) => term.loadAddon(new WebglAddon()))
      .catch(() => { /* Fall back to DOM renderer */ })
    fitAddon.fit()
    term.focus()

    termRef.current = term
    fitAddonRef.current = fitAddon
    searchAddonRef.current = searchAddon

    term.write('\r\n[Connecting...]\r\n')

    // Subscribe to ActionCable
    const subscription = getCable().subscriptions.create(
      { channel: 'TerminalChannel', service_id: serviceId, shell },
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
            term.clear()
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
      searchAddonRef.current = null
      subscriptionRef.current = null
      setIsConnected(false)
    }
  }, [serviceId, shell, terminalRef, sendData, sendResize])

  return { isConnected, error, term: termRef.current, findNext, findPrevious, clearSearch }
}
