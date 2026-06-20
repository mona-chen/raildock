import { useRef, useState, useEffect, useCallback } from 'react'
import { useTerminal } from '@/hooks/useTerminal'
import { reconnectCable } from '@/lib/cable'
import {
  Loader2, Monitor, AlertCircle, Power,
  Search, ChevronUp, ChevronDown, X, Shell,
  Maximize2, Minimize2
} from 'lucide-react'
import '@xterm/xterm/css/xterm.css'

const SHELL_OPTIONS = [
  { value: '/bin/sh', label: '/bin/sh' },
  { value: '/bin/bash', label: '/bin/bash' },
  { value: '/bin/zsh', label: '/bin/zsh' },
  { value: '/bin/ash', label: '/bin/ash' },
]

interface InteractiveTerminalProps {
  serviceId: string
  serviceName: string
}

export default function InteractiveTerminal({ serviceId, serviceName }: InteractiveTerminalProps) {
  const [shell, setShell] = useState('/bin/sh')
  const [retryToken, setRetryToken] = useState(0)
  const terminalRef = useRef<HTMLDivElement>(null)
  const { isConnected, error, findNext, findPrevious, clearSearch } = useTerminal(serviceId, terminalRef, shell, retryToken)
  const [showInfo, setShowInfo] = useState(true)
  const [showSearch, setShowSearch] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')
  const [isExpanded, setIsExpanded] = useState(false)

  // Ctrl+F toggles search; Escape closes search or expanded mode
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'f') {
        e.preventDefault()
        setShowSearch((prev) => !prev)
      }
      if (e.key === 'Escape') {
        if (isExpanded) {
          setIsExpanded(false)
          return
        }
        setShowSearch(false)
        clearSearch()
      }
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [clearSearch, isExpanded])

  const handleSearchChange = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value
    setSearchQuery(value)
    if (value) {
      findNext(value)
    } else {
      clearSearch()
    }
  }, [findNext, clearSearch])

  const handleFindNext = useCallback(() => {
    if (searchQuery) findNext(searchQuery)
  }, [searchQuery, findNext])

  const handleFindPrev = useCallback(() => {
    if (searchQuery) findPrevious(searchQuery)
  }, [searchQuery, findPrevious])

  const handleRetry = useCallback(() => {
    // Force a fresh ActionCable consumer so a stale connection state can't
    // block the next subscribe attempt. This is what unsticks the
    // 'connection timed out' state after a server restart.
    reconnectCable()
    setRetryToken((attempt) => attempt + 1)
  }, [])

  return (
    <div className={`flex flex-col h-full bg-[#0B0B0D] ${isExpanded ? 'fixed inset-0 z-[100]' : ''}`}>
      {/* Toolbar */}
      <div className="flex items-center justify-between px-4 py-2 border-b border-white/[0.06] bg-[#0f0f13]">
        <div className="flex items-center gap-2">
          <Monitor size={14} className="text-white/40" />
          <span className="text-[12px] text-white/60 font-medium">
            {serviceName}
          </span>
          <span className="text-[10px] text-white/30">
            — Interactive Shell
          </span>
        </div>
        <div className="flex items-center gap-3">
          {error && (
            <div className="flex items-center gap-1.5 text-[11px] text-red-400">
              <AlertCircle size={12} />
              {error}
            </div>
          )}

          {/* Shell selector */}
          <div className="flex items-center gap-1.5">
            <Shell size={12} className="text-white/30" />
            <select
              value={shell}
              onChange={(e) => setShell(e.target.value)}
              className="bg-transparent text-[11px] text-white/50 hover:text-white/70 cursor-pointer outline-none border border-white/10 rounded px-1.5 py-0.5 appearance-none pr-4"
              style={{
                backgroundImage: `url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='8' height='8' viewBox='0 0 24 24' fill='none' stroke='rgba(255,255,255,0.3)' stroke-width='3' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='m6 9 6 6 6-6'/%3E%3C/svg%3E")`,
                backgroundRepeat: 'no-repeat',
                backgroundPosition: 'right 4px center',
              }}
            >
              {SHELL_OPTIONS.map((opt) => (
                <option key={opt.value} value={opt.value} className="bg-[#0f0f13] text-white/70">
                  {opt.label}
                </option>
              ))}
            </select>
          </div>

          <button
            onClick={() => setShowSearch((s) => !s)}
            className="text-white/30 hover:text-white/60 transition-colors"
            title="Search (Ctrl+F)"
          >
            <Search size={14} />
          </button>

          {isExpanded ? (
            <button
              onClick={() => setIsExpanded(false)}
              className="flex items-center gap-1 px-2 py-1 rounded bg-white/[0.06] text-white/50 text-[11px] hover:bg-white/[0.1] transition-colors"
              title="Minimize"
            >
              <Minimize2 size={11} />
              Esc to close
            </button>
          ) : (
            <button
              onClick={() => setIsExpanded(true)}
              className="p-1.5 rounded hover:bg-white/[0.06] text-white/30 hover:text-white/60 transition-colors"
              title="Expand terminal"
            >
              <Maximize2 size={13} />
            </button>
          )}

          <div className="flex items-center gap-1.5">
            <div className={`w-1.5 h-1.5 rounded-full ${isConnected ? 'bg-emerald-500' : error ? 'bg-red-400' : 'bg-amber-500'}`} />
            <span className="text-[10px] text-white/40">
              {isConnected ? 'Connected' : error ? 'Unavailable' : 'Connecting...'}
            </span>
          </div>
        </div>
      </div>

      {/* Search bar */}
      {showSearch && (
        <div className="flex items-center gap-2 px-4 py-1.5 border-b border-white/[0.06] bg-[#131318]">
          <Search size={12} className="text-white/30" />
          <input
            type="text"
            value={searchQuery}
            onChange={handleSearchChange}
            placeholder="Find in terminal..."
            autoFocus
            className="flex-1 bg-transparent text-[12px] text-white/70 placeholder:text-white/20 outline-none"
          />
          <button
            onClick={handleFindPrev}
            className="text-white/30 hover:text-white/60 transition-colors p-0.5"
            title="Previous match"
          >
            <ChevronUp size={14} />
          </button>
          <button
            onClick={handleFindNext}
            className="text-white/30 hover:text-white/60 transition-colors p-0.5"
            title="Next match"
          >
            <ChevronDown size={14} />
          </button>
          <button
            onClick={() => { setShowSearch(false); clearSearch() }}
            className="text-white/30 hover:text-white/60 transition-colors p-0.5"
            title="Close search"
          >
            <X size={14} />
          </button>
        </div>
      )}

      {/* Info banner — dismissible */}
      {showInfo && (
        <div className="px-4 py-2 border-b border-white/[0.06] bg-[#131318] flex items-center justify-between">
          <div className="flex items-center gap-2 text-[11px] text-white/40">
            <Power size={12} className="text-[#8b5cf6]" />
            <span>
              Type commands directly. Supports <code className="text-white/60">vim</code>,{' '}
              <code className="text-white/60">top</code>, <code className="text-white/60">nano</code>, and TUI apps.
              Click the terminal to focus. <kbd className="text-white/60">Ctrl+F</kbd> to search.
              Select a different shell from the toolbar if the default doesn't work.
            </span>
          </div>
          <button
            onClick={() => setShowInfo(false)}
            className="text-[10px] text-white/30 hover:text-white/60 transition-colors"
          >
            Dismiss
          </button>
        </div>
      )}

      {/* Terminal container */}
      <div className="flex-1 relative overflow-hidden">
        {!isConnected && !error && (
          <div className="absolute inset-0 flex items-center justify-center bg-[#0B0B0D]/80 z-10">
            <div className="flex flex-col items-center gap-2 text-white/30">
              <Loader2 size={20} className="animate-spin" />
              <span className="text-[12px]">Opening terminal session...</span>
            </div>
          </div>
        )}
        {error && (
          <div className="absolute inset-0 flex items-center justify-center bg-[#0B0B0D]/90 z-10 px-6">
            <div className="flex max-w-sm flex-col items-center gap-3 text-center">
              <div className="flex h-9 w-9 items-center justify-center rounded-full border border-red-400/20 bg-red-400/10 text-red-300">
                <AlertCircle size={17} />
              </div>
              <div>
                <p className="text-[13px] font-medium text-white/80">Couldn’t open the terminal</p>
                <p className="mt-1 text-[11px] leading-relaxed text-white/40">{error}</p>
              </div>
              <button
                type="button"
                onClick={handleRetry}
                className="rounded-md border border-white/10 bg-white/[0.06] px-3 py-1.5 text-[11px] font-medium text-white/70 transition-colors hover:bg-white/[0.1] hover:text-white"
              >
                Try again
              </button>
            </div>
          </div>
        )}
        <div
          ref={terminalRef}
          className="absolute inset-0 p-2"
          style={{ background: '#0B0B0D' }}
        />
      </div>
    </div>
  )
}
