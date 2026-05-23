import { useState, useRef, useEffect, useMemo, useCallback } from 'react'
import {
  Pause, Play, Search, X, Copy, Check, WrapText, UnfoldVertical,
  Download, Filter, Terminal, ClipboardCopy, Maximize2, Minimize2
} from 'lucide-react'
import { copyToClipboard } from '@/lib/clipboard'
import { useServiceLogs } from '@/hooks/useServices'
import { useWebSocketLogs } from '@/hooks/useWebSocketLogs'

interface LogLine {
  timestamp: string
  process_type: string
  message: string
}

type LogLevel = 'error' | 'warn' | 'info' | 'debug' | 'trace' | 'fatal' | 'unknown'

const LEVEL_COLORS: Record<LogLevel, { text: string; bg: string; border: string; dot: string; selectedBg: string }> = {
  error:   { text: 'text-red-400',      bg: 'bg-red-500/5',      border: 'border-red-500/10',      dot: 'bg-red-400',      selectedBg: 'bg-red-500/15' },
  warn:    { text: 'text-amber-400',    bg: 'bg-amber-500/5',    border: 'border-amber-500/10',    dot: 'bg-amber-400',    selectedBg: 'bg-amber-500/15' },
  info:    { text: 'text-blue-400',     bg: 'bg-blue-500/5',     border: 'border-blue-500/10',     dot: 'bg-blue-400',     selectedBg: 'bg-blue-500/15' },
  debug:   { text: 'text-emerald-400',  bg: 'bg-emerald-500/5',  border: 'border-emerald-500/10',  dot: 'bg-emerald-400',  selectedBg: 'bg-emerald-500/15' },
  trace:   { text: 'text-gray-400',     bg: 'bg-gray-500/5',     border: 'border-gray-500/10',     dot: 'bg-gray-400',     selectedBg: 'bg-gray-500/15' },
  fatal:   { text: 'text-rose-500',     bg: 'bg-rose-500/10',    border: 'border-rose-500/20',     dot: 'bg-rose-500',     selectedBg: 'bg-rose-500/20' },
  unknown: { text: 'text-white/60',     bg: 'bg-transparent',    border: 'border-transparent',     dot: 'bg-white/30',     selectedBg: 'bg-white/[0.08]' },
}

const LEVEL_ORDER: LogLevel[] = ['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'unknown']

function detectLevel(message: string): LogLevel {
  const upper = message.toUpperCase()
  if (upper.includes('FATAL') || upper.includes('PANIC')) return 'fatal'
  if (upper.includes('ERROR') || upper.includes('ERR') || upper.includes('EXCEPTION')) return 'error'
  if (upper.includes('WARN') || upper.includes('WARNING')) return 'warn'
  if (upper.includes('DEBUG')) return 'debug'
  if (upper.includes('TRACE')) return 'trace'
  if (upper.includes('INFO') || upper.includes('LOG')) return 'info'
  return 'unknown'
}

function stripAnsi(str: string): string {
  // eslint-disable-next-line no-control-regex
  return str.replace(/\x1B\[[0-9;]*m/g, '')
}

function tryPrettyJson(message: string): string | null {
  const trimmed = message.trim()
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null
  try {
    const parsed = JSON.parse(trimmed)
    return JSON.stringify(parsed, null, 2)
  } catch {
    return null
  }
}

function formatRelativeTime(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime()
  const sec = Math.floor(diff / 1000)
  if (sec < 1) return 'now'
  if (sec < 60) return `${sec}s ago`
  const min = Math.floor(sec / 60)
  if (min < 60) return `${min}m ago`
  const hr = Math.floor(min / 60)
  if (hr < 24) return `${hr}h ago`
  return `${Math.floor(hr / 24)}d ago`
}

function formatAbsoluteTime(iso: string): string {
  const d = new Date(iso)
  return d.toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' }) +
         '.' + String(d.getMilliseconds()).padStart(3, '0')
}

function formatFullLine(line: LogLine & { cleanMessage: string }): string {
  return `[${line.process_type}] ${line.timestamp} ${line.cleanMessage}`
}

export default function LogsTab({ serviceId }: { serviceId: string }) {
  const { data: historicalLogs } = useServiceLogs(serviceId)
  const { lines: liveLines, isConnected, clear } = useWebSocketLogs(serviceId)
  const scrollRef = useRef<HTMLDivElement>(null)
  const [hasCleared, setHasCleared] = useState(false)
  const [isPaused, setIsPaused] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')
  const [levelFilter, setLevelFilter] = useState<LogLevel | 'all'>('all')
  const [processFilter, setProcessFilter] = useState<string>('all')
  const [wrapLines, setWrapLines] = useState(false)
  const [showFilters, setShowFilters] = useState(false)
  const [copiedId, setCopiedId] = useState<number | null>(null)
  const [copiedAll, setCopiedAll] = useState(false)
  const [expandedLines, setExpandedLines] = useState<Set<number>>(new Set())
  const [isExpanded, setIsExpanded] = useState(false)
  const wasAtBottomRef = useRef(true)
  const newLogsCountRef = useRef(0)
  const [newLogsIndicator, setNewLogsIndicator] = useState(false)

  // Multi-line selection
  const [selectionAnchor, setSelectionAnchor] = useState<number | null>(null)
  const [selectedRange, setSelectedRange] = useState<{ start: number; end: number } | null>(null)

  // Build full log list
  const allLines: LogLine[] = useMemo(() => {
    if (hasCleared) return liveLines
    const historical = (historicalLogs || []).map((l) => ({
      timestamp: l.timestamp,
      process_type: l.processType,
      message: l.message,
    }))
    return [...historical, ...liveLines]
  }, [historicalLogs, liveLines, hasCleared])

  // Enrich with level detection
  const enrichedLines = useMemo(() => {
    return allLines.map((line, idx) => ({
      ...line,
      id: idx,
      level: detectLevel(line.message),
      cleanMessage: stripAnsi(line.message),
    }))
  }, [allLines])

  // Filtered lines
  const filteredLines = useMemo(() => {
    let result = enrichedLines
    if (levelFilter !== 'all') {
      result = result.filter((l) => l.level === levelFilter)
    }
    if (processFilter !== 'all') {
      result = result.filter((l) => l.process_type === processFilter)
    }
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase()
      result = result.filter((l) =>
        l.cleanMessage.toLowerCase().includes(q) ||
        l.process_type.toLowerCase().includes(q)
      )
    }
    return result
  }, [enrichedLines, levelFilter, processFilter, searchQuery])

  // Unique process types for filter dropdown
  const processTypes = useMemo(() => {
    const types = new Set(enrichedLines.map((l) => l.process_type))
    return Array.from(types).sort()
  }, [enrichedLines])

  // Level counts
  const levelCounts = useMemo(() => {
    const counts: Record<string, number> = {}
    enrichedLines.forEach((l) => {
      counts[l.level] = (counts[l.level] || 0) + 1
    })
    return counts
  }, [enrichedLines])

  // Check if a display index is in the selected range
  const isSelected = useCallback((displayIdx: number) => {
    if (!selectedRange) return false
    return displayIdx >= selectedRange.start && displayIdx <= selectedRange.end
  }, [selectedRange])

  // Smart auto-scroll: only scroll if user was at bottom and not paused
  useEffect(() => {
    if (!scrollRef.current || isPaused) {
      if (isPaused && allLines.length > 0) {
        newLogsCountRef.current += 1
        setNewLogsIndicator(true)
      }
      return
    }
    const el = scrollRef.current
    const isAtBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 50
    if (isAtBottom || wasAtBottomRef.current) {
      el.scrollTop = el.scrollHeight
      wasAtBottomRef.current = true
    }
  }, [allLines.length, isPaused])

  // Track scroll position
  const handleScroll = useCallback(() => {
    if (!scrollRef.current) return
    const el = scrollRef.current
    wasAtBottomRef.current = el.scrollHeight - el.scrollTop - el.clientHeight < 50
    if (wasAtBottomRef.current) {
      newLogsCountRef.current = 0
      setNewLogsIndicator(false)
    }
  }, [])

  // Close expanded view on Escape
  useEffect(() => {
    if (!isExpanded) return
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setIsExpanded(false)
    }
    window.addEventListener('keydown', handleKey)
    return () => window.removeEventListener('keydown', handleKey)
  }, [isExpanded])

  const handleClear = () => {
    clear()
    setHasCleared(true)
    setExpandedLines(new Set())
    setSelectedRange(null)
    setSelectionAnchor(null)
  }

  const handleResume = () => {
    setIsPaused(false)
    newLogsCountRef.current = 0
    setNewLogsIndicator(false)
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight
    }
  }

  const toggleExpand = (id: number) => {
    setExpandedLines((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  // Multi-line selection handler
  const handleLineClick = (displayIdx: number, e: React.MouseEvent) => {
    if (e.shiftKey && selectionAnchor !== null) {
      const start = Math.min(selectionAnchor, displayIdx)
      const end = Math.max(selectionAnchor, displayIdx)
      setSelectedRange({ start, end })
    } else {
      setSelectionAnchor(displayIdx)
      setSelectedRange({ start: displayIdx, end: displayIdx })
    }
  }

  const clearSelection = () => {
    setSelectedRange(null)
    setSelectionAnchor(null)
  }

  const copyLine = async (line: LogLine & { id: number; level: LogLevel; cleanMessage: string }) => {
    const text = formatFullLine(line)
    const success = await copyToClipboard(text)
    if (success) {
      setCopiedId(line.id)
      setTimeout(() => setCopiedId(null), 1500)
    }
  }

  const copySelection = async () => {
    if (!selectedRange) return
    const lines = filteredLines.slice(selectedRange.start, selectedRange.end + 1)
    const text = lines.map(formatFullLine).join('\n')
    const success = await copyToClipboard(text)
    if (success) {
      setCopiedAll(true)
      setTimeout(() => setCopiedAll(false), 1500)
    }
  }

  const copyAll = async () => {
    const text = filteredLines.map(formatFullLine).join('\n')
    const success = await copyToClipboard(text)
    if (success) {
      setCopiedAll(true)
      setTimeout(() => setCopiedAll(false), 1500)
    }
  }

  const exportLogs = () => {
    const text = filteredLines.map(formatFullLine).join('\n')
    const blob = new Blob([text], { type: 'text/plain' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `logs-${serviceId}-${new Date().toISOString()}.txt`
    a.click()
    URL.revokeObjectURL(url)
  }

  const selectedCount = selectedRange ? selectedRange.end - selectedRange.start + 1 : 0

  const logView = (
    <div className={`flex flex-col h-full bg-[#131318] ${isExpanded ? 'fixed inset-0 z-[100]' : ''}`}>
      {/* Toolbar */}
      <div className="flex flex-col border-b border-white/[0.06] flex-shrink-0">
        {/* Top row: status + actions */}
        <div className="flex items-center justify-between px-4 py-2">
          <div className="flex items-center gap-3">
            <div className="flex items-center gap-1.5">
              <span className={`w-2 h-2 rounded-full ${isConnected ? 'bg-[#22c55e] animate-pulse' : 'bg-white/20'}`} />
              <span className="text-[11px] text-white/40">{isConnected ? 'Live' : 'Polling'}</span>
            </div>
            {isPaused && (
              <span className="text-[10px] px-1.5 py-0.5 bg-amber-500/10 text-amber-400 rounded-full">
                Paused
              </span>
            )}
            <span className="text-[10px] text-white/20">
              {filteredLines.length.toLocaleString()} lines
            </span>
            {selectedRange && (
              <span className="text-[10px] px-1.5 py-0.5 bg-[#8b5cf6]/10 text-[#8b5cf6] rounded-full">
                {selectedCount} selected
              </span>
            )}
          </div>
          <div className="flex items-center gap-1">
            {selectedRange && (
              <>
                <button
                  type="button"
                  onClick={copySelection}
                  className="flex items-center gap-1 px-2 py-1 rounded bg-[#8b5cf6]/10 text-[#8b5cf6] text-[11px] hover:bg-[#8b5cf6]/15 transition-colors"
                  title="Copy selection"
                >
                  {copiedAll ? <Check size={11} /> : <Copy size={11} />}
                  Copy {selectedCount}
                </button>
                <button
                  type="button"
                  onClick={clearSelection}
                  className="p-1.5 rounded hover:bg-white/[0.06] text-white/30 hover:text-white/60 transition-colors"
                  title="Clear selection"
                >
                  <X size={13} />
                </button>
                <div className="w-px h-4 bg-white/[0.08] mx-0.5" />
              </>
            )}
            {isExpanded && (
              <>
                <button
                  type="button"
                  onClick={() => setIsExpanded(false)}
                  className="flex items-center gap-1 px-2 py-1 rounded bg-white/[0.06] text-white/50 text-[11px] hover:bg-white/[0.1] transition-colors"
                  title="Minimize"
                >
                  <Minimize2 size={11} />
                  Esc to close
                </button>
                <div className="w-px h-4 bg-white/[0.08] mx-0.5" />
              </>
            )}
            <button
              type="button"
              onClick={copyAll}
              className="p-1.5 rounded hover:bg-white/[0.06] text-white/30 hover:text-white/60 transition-colors"
              title="Copy all logs"
            >
              {copiedAll && !selectedRange ? <Check size={13} className="text-emerald-400" /> : <ClipboardCopy size={13} />}
            </button>
            <button
              type="button"
              onClick={() => setIsPaused((p) => !p)}
              className="p-1.5 rounded hover:bg-white/[0.06] text-white/30 hover:text-white/60 transition-colors"
              title={isPaused ? 'Resume' : 'Pause'}
            >
              {isPaused ? <Play size={13} /> : <Pause size={13} />}
            </button>
            <button
              type="button"
              onClick={() => setWrapLines((w) => !w)}
              className={`p-1.5 rounded transition-colors ${wrapLines ? 'bg-white/[0.08] text-white/60' : 'hover:bg-white/[0.06] text-white/30 hover:text-white/60'}`}
              title="Wrap lines"
            >
              <WrapText size={13} />
            </button>
            <button
              type="button"
              onClick={() => setShowFilters((s) => !s)}
              className={`p-1.5 rounded transition-colors ${showFilters ? 'bg-white/[0.08] text-white/60' : 'hover:bg-white/[0.06] text-white/30 hover:text-white/60'}`}
              title="Filters"
            >
              <Filter size={13} />
            </button>
            <button
              type="button"
              onClick={exportLogs}
              className="p-1.5 rounded hover:bg-white/[0.06] text-white/30 hover:text-white/60 transition-colors"
              title="Export logs"
            >
              <Download size={13} />
            </button>
            <button
              type="button"
              onClick={handleClear}
              className="p-1.5 rounded hover:bg-white/[0.06] text-white/30 hover:text-white/60 transition-colors"
              title="Clear"
            >
              <X size={13} />
            </button>
            <div className="w-px h-4 bg-white/[0.08] mx-0.5" />
            <button
              type="button"
              onClick={() => setIsExpanded(true)}
              className="p-1.5 rounded hover:bg-white/[0.06] text-white/30 hover:text-white/60 transition-colors"
              title="Expand logs"
            >
              <Maximize2 size={13} />
            </button>
          </div>
        </div>

        {/* Search bar */}
        <div className="px-4 pb-2">
          <div className="relative">
            <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-white/20" />
            <input
              type="text"
              placeholder="Search logs..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pl-8 pr-7 py-1.5 bg-black/30 border border-white/[0.06] rounded-lg text-[12px] text-white/70 placeholder:text-white/20 focus:outline-none focus:border-[#8b5cf6]/30"
            />
            {searchQuery && (
              <button
                type="button"
                onClick={() => setSearchQuery('')}
                className="absolute right-2 top-1/2 -translate-y-1/2 text-white/20 hover:text-white/40"
              >
                <X size={12} />
              </button>
            )}
          </div>
        </div>

        {/* Filter row */}
        {showFilters && (
          <div className="px-4 pb-2 flex items-center gap-2 flex-wrap">
            <select
              value={levelFilter}
              onChange={(e) => setLevelFilter(e.target.value as LogLevel | 'all')}
              className="bg-black/30 border border-white/[0.06] rounded px-2 py-1 text-[11px] text-white/60 focus:outline-none focus:border-[#8b5cf6]/30"
            >
              <option value="all">All levels</option>
              {LEVEL_ORDER.map((lvl) => (
                <option key={lvl} value={lvl}>
                  {lvl.charAt(0).toUpperCase() + lvl.slice(1)} ({levelCounts[lvl] || 0})
                </option>
              ))}
            </select>
            <select
              value={processFilter}
              onChange={(e) => setProcessFilter(e.target.value)}
              className="bg-black/30 border border-white/[0.06] rounded px-2 py-1 text-[11px] text-white/60 focus:outline-none focus:border-[#8b5cf6]/30"
            >
              <option value="all">All processes</option>
              {processTypes.map((pt) => (
                <option key={pt} value={pt}>{pt}</option>
              ))}
            </select>
            {(levelFilter !== 'all' || processFilter !== 'all' || searchQuery) && (
              <button
                type="button"
                onClick={() => { setLevelFilter('all'); setProcessFilter('all'); setSearchQuery('') }}
                className="text-[11px] text-white/30 hover:text-white/50"
              >
                Reset filters
              </button>
            )}
          </div>
        )}
      </div>

      {/* New logs indicator */}
      {isPaused && newLogsIndicator && (
        <button
          type="button"
          onClick={handleResume}
          className="flex-shrink-0 py-1.5 bg-[#8b5cf6]/10 border-b border-[#8b5cf6]/20 text-[11px] text-[#8b5cf6] hover:bg-[#8b5cf6]/15 transition-colors text-center"
        >
          <UnfoldVertical size={11} className="inline mr-1" />
          New logs available — click to resume
        </button>
      )}

      {/* Log lines */}
      <div
        ref={scrollRef}
        onScroll={handleScroll}
        className="flex-1 overflow-y-auto font-mono text-[12px] leading-relaxed select-none"
        onClick={(e) => {
          // Clear selection when clicking empty area
          if (e.target === e.currentTarget) clearSelection()
        }}
      >
        {filteredLines.length > 0 ? (
          <div className="py-2">
            {filteredLines.map((line, displayIdx) => {
              const colors = LEVEL_COLORS[line.level]
              const isExpanded = expandedLines.has(line.id)
              const prettyJson = isExpanded ? tryPrettyJson(line.cleanMessage) : null
              const hasJson = !isExpanded && !!tryPrettyJson(line.cleanMessage)
              const sel = isSelected(displayIdx)

              return (
                <div
                  key={`${line.id}-${line.timestamp}`}
                  className={`group flex items-start gap-1 px-3 py-0.5 hover:bg-white/[0.03] border-l-2 ${sel ? 'border-[#8b5cf6] ' + colors.selectedBg : colors.border + ' ' + colors.bg} transition-colors cursor-pointer`}
                  onClick={(e) => handleLineClick(displayIdx, e)}
                >
                  {/* Line number */}
                  <span className={`select-none w-10 text-right shrink-0 text-[11px] pt-0.5 ${sel ? 'text-[#8b5cf6]/60' : 'text-white/10'}`}>
                    {displayIdx + 1}
                  </span>

                  {/* Level dot */}
                  <span className={`w-1.5 h-1.5 rounded-full mt-1.5 shrink-0 ${colors.dot}`} />

                  {/* Timestamp */}
                  <span
                    className="text-white/20 shrink-0 text-[11px] pt-0.5 w-[72px] text-right"
                    title={new Date(line.timestamp).toLocaleString()}
                  >
                    {formatRelativeTime(line.timestamp)}
                  </span>

                  {/* Process type */}
                  <span className="text-[#8b5cf6]/50 shrink-0 text-[11px] pt-0.5 w-12 text-right">
                    {line.process_type}
                  </span>

                  {/* Message */}
                  <div className={`flex-1 min-w-0 ${colors.text} ${wrapLines ? 'whitespace-pre-wrap break-all' : 'truncate'}`}>
                    {isExpanded && prettyJson ? (
                      <pre className="whitespace-pre-wrap break-all text-[11px] text-white/50 bg-black/20 rounded p-2 mt-0.5">
                        {prettyJson}
                      </pre>
                    ) : (
                      <span>{line.cleanMessage}</span>
                    )}
                    {hasJson && !isExpanded && (
                      <span className="ml-1 text-[10px] text-[#8b5cf6]/40">{'{...}'}</span>
                    )}
                  </div>

                  {/* Actions (visible on hover) */}
                  <div className="flex items-center gap-0.5 opacity-0 group-hover:opacity-100 shrink-0 transition-opacity">
                    <button
                      type="button"
                      onClick={(e) => { e.stopPropagation(); copyLine(line) }}
                      className="p-1 rounded hover:bg-white/[0.08] text-white/20 hover:text-white/50"
                      title="Copy line"
                    >
                      {copiedId === line.id ? <Check size={11} className="text-emerald-400" /> : <Copy size={11} />}
                    </button>
                    {hasJson && (
                      <button
                        type="button"
                        onClick={(e) => { e.stopPropagation(); toggleExpand(line.id) }}
                        className="p-1 rounded hover:bg-white/[0.08] text-white/20 hover:text-[#8b5cf6]/60"
                        title="Format JSON"
                      >
                        <Terminal size={11} />
                      </button>
                    )}
                  </div>
                </div>
              )
            })}
          </div>
        ) : (
          <div className="flex flex-col items-center justify-center h-full text-white/20">
            <Terminal size={32} className="mb-3 opacity-30" />
            <p className="text-sm">
              {allLines.length === 0 ? 'Waiting for logs...' : 'No logs match your filters'}
            </p>
            {allLines.length > 0 && (
              <button
                type="button"
                onClick={() => { setLevelFilter('all'); setProcessFilter('all'); setSearchQuery('') }}
                className="mt-2 text-[12px] text-[#8b5cf6]/60 hover:text-[#8b5cf6]"
              >
                Clear filters
              </button>
            )}
          </div>
        )}
      </div>
    </div>
  )

  return logView
}
