import { useRef, useState, useEffect, useCallback } from 'react'
import { useTerminal } from '@/hooks/useTerminal'
import {
  Loader2, Monitor, AlertCircle, Power,
  Search, ChevronUp, ChevronDown, X
} from 'lucide-react'
import '@xterm/xterm/css/xterm.css'

interface InteractiveTerminalProps {
  serviceId: string
  serviceName: string
}

export default function InteractiveTerminal({ serviceId, serviceName }: InteractiveTerminalProps) {
  const terminalRef = useRef<HTMLDivElement>(null)
  const { isConnected, error, findNext, findPrevious, clearSearch } = useTerminal(serviceId, terminalRef)
  const [showInfo, setShowInfo] = useState(true)
  const [showSearch, setShowSearch] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')

  // Ctrl+F toggles search
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'f') {
        e.preventDefault()
        setShowSearch((prev) => !prev)
      }
      if (e.key === 'Escape') {
        setShowSearch(false)
        clearSearch()
      }
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [clearSearch])

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

  return (
    <div className="flex flex-col h-full bg-[#0B0B0D]">
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
          <button
            onClick={() => setShowSearch((s) => !s)}
            className="text-white/30 hover:text-white/60 transition-colors"
            title="Search (Ctrl+F)"
          >
            <Search size={14} />
          </button>
          <div className="flex items-center gap-1.5">
            <div className={`w-1.5 h-1.5 rounded-full ${isConnected ? 'bg-emerald-500' : 'bg-amber-500'}`} />
            <span className="text-[10px] text-white/40">
              {isConnected ? 'Connected' : 'Connecting...'}
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
        <div
          ref={terminalRef}
          className="absolute inset-0 p-2"
          style={{ background: '#0B0B0D' }}
        />
      </div>
    </div>
  )
}
