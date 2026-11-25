import { useDeferredValue, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { Check, Copy, Search, WrapText, X } from 'lucide-react'
import { detectLanguage, LANGUAGE_LABELS, tokenizeFileLine, type FileLanguage, type Token, type TokenKind } from '@/lib/fileViewer'

const TOKEN_COLORS: Record<TokenKind, string> = {
  plain: 'text-white/70',
  comment: 'text-[#697386] italic',
  string: 'text-[#a7f3d0]',
  number: 'text-[#fbbf8a]',
  keyword: 'text-[#c4b5fd]',
  literal: 'text-[#f0abfc]',
  function: 'text-[#7dd3fc]',
  type: 'text-[#93c5fd]',
  property: 'text-[#f9a8d4]',
  tag: 'text-[#f472b6]',
  attribute: 'text-[#fcd34d]',
  operator: 'text-[#94a3b8]',
  punctuation: 'text-white/30',
  heading: 'font-semibold text-[#f0abfc]',
  link: 'text-[#7dd3fc] underline decoration-[#7dd3fc]/30',
  variable: 'text-[#fcd34d]',
}

function formatBytes(bytes: number) {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 ** 2) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / 1024 ** 2).toFixed(1)} MB`
}

function countMatches(value: string, query: string) {
  if (!query) return 0
  const lowerValue = value.toLowerCase()
  const lowerQuery = query.toLowerCase()
  let count = 0
  let index = lowerValue.indexOf(lowerQuery)
  while (index >= 0) {
    count += 1
    index = lowerValue.indexOf(lowerQuery, index + lowerQuery.length)
  }
  return count
}

function splitMatches(value: string, query: string) {
  if (!query) return [ { text: value, match: false } ]
  const lowerValue = value.toLowerCase()
  const lowerQuery = query.toLowerCase()
  const parts: { text: string; match: boolean }[] = []
  let index = 0
  let found = lowerValue.indexOf(lowerQuery, index)
  while (found >= 0) {
    if (found > index) parts.push({ text: value.slice(index, found), match: false })
    parts.push({ text: value.slice(found, found + query.length), match: true })
    index = found + query.length
    found = lowerValue.indexOf(lowerQuery, index)
  }
  if (index < value.length) parts.push({ text: value.slice(index), match: false })
  return parts
}

function renderToken(token: Token, query: string, key: number): ReactNode {
  if (!query) return <span key={key} className={TOKEN_COLORS[token.kind]}>{token.value}</span>
  return (
    <span key={key} className={TOKEN_COLORS[token.kind]}>
      {splitMatches(token.value, query).map((part, index) => part.match
        ? <mark key={index} className="rounded-sm bg-amber-300/25 px-0.5 text-amber-100">{part.text}</mark>
        : <span key={index}>{part.text}</span>
      )}
    </span>
  )
}

export default function FileCodeViewer({ content, filename }: { content: string; filename: string }) {
  const language = useMemo(() => detectLanguage(filename), [filename])
  const [query, setQuery] = useState('')
  const deferredQuery = useDeferredValue(query.trim())
  const [wrap, setWrap] = useState(true)
  const [pretty, setPretty] = useState(false)
  const [copyState, setCopyState] = useState<'idle' | 'copied' | 'failed'>('idle')
  const codeRef = useRef<HTMLDivElement>(null)

  const formatted = useMemo(() => {
    if (language !== 'json') return null
    try {
      return JSON.stringify(JSON.parse(content), null, 2)
    } catch {
      return null
    }
  }, [content, language])

  const displayContent = pretty && formatted ? formatted : content
  const lines = useMemo(() => displayContent.split('\n'), [displayContent])
  const byteSize = useMemo(() => new Blob([displayContent]).size, [displayContent])
  const tokenizedLines = useMemo(() => {
    let embedded: FileLanguage | null = null
    const result: Token[][] = []
    for (const line of lines) {
      const lower = line.toLowerCase()
      if (embedded) {
        const closingTag = embedded === 'css' ? 'style' : 'script'
        if (lower.includes(`</${closingTag}`)) {
          embedded = null
          result.push(tokenizeFileLine(line, language))
          continue
        }
        result.push(tokenizeFileLine(line, embedded))
        continue
      }
      if (language === 'html' || language === 'xml') {
        if (/<style(?:\s|>)/.test(lower)) embedded = 'css'
        else if (/<script(?:\s|>)/.test(lower)) embedded = 'javascript'
      }
      result.push(tokenizeFileLine(line, language))
    }
    return result
  }, [lines, language])
  const matches = useMemo(() => countMatches(displayContent, deferredQuery), [displayContent, deferredQuery])

  useEffect(() => {
    if (!deferredQuery) return
    const mark = codeRef.current?.querySelector('mark')
    mark?.scrollIntoView({ block: 'nearest', inline: 'nearest' })
  }, [deferredQuery, displayContent])

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(displayContent)
      setCopyState('copied')
      window.setTimeout(() => setCopyState((state) => state === 'copied' ? 'idle' : state), 1800)
    } catch {
      setCopyState('failed')
    }
  }

  return (
    <div className="overflow-hidden rounded-lg border border-white/8 bg-[#0b0b10]">
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-white/7 px-3 py-2">
        <div className="flex flex-wrap items-center gap-2 text-[10px] text-white/35">
          <span className="rounded bg-rail-purple/12 px-2 py-0.5 font-medium text-rail-purple-light">{LANGUAGE_LABELS[language]}</span>
          <span>{lines.length.toLocaleString()} lines</span>
          <span>{formatBytes(byteSize)}</span>
        </div>
        <div className="flex flex-wrap items-center gap-1.5">
          <label className="flex h-7 items-center gap-1.5 rounded-md border border-white/8 bg-black/25 px-2 text-white/35 focus-within:border-rail-purple/50">
            <Search size={12} />
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              onKeyDown={(event) => { if (event.key === 'Escape') setQuery('') }}
              placeholder="Find"
              aria-label="Find in file"
              className="w-28 bg-transparent text-[11px] text-white/70 outline-hidden placeholder:text-white/25"
            />
            {query && (
              <button type="button" onClick={() => setQuery('')} aria-label="Clear search" className="text-white/25 hover:text-white/60">
                <X size={11} />
              </button>
            )}
          </label>
          {deferredQuery && <span className="text-[10px] tabular-nums text-white/35">{matches.toLocaleString()} {matches === 1 ? 'match' : 'matches'}</span>}
          {formatted && (
            <button type="button" onClick={() => setPretty((value) => !value)} className="h-7 rounded-md border border-white/8 px-2 text-[10px] text-white/45 hover:bg-white/6 hover:text-white/75">
              {pretty ? 'Raw' : 'Pretty'}
            </button>
          )}
          <button type="button" onClick={() => setWrap((value) => !value)} aria-pressed={wrap} className={`flex h-7 items-center gap-1 rounded-md border px-2 text-[10px] ${wrap ? 'border-rail-purple/30 bg-rail-purple/10 text-rail-purple-light' : 'border-white/8 text-white/45 hover:bg-white/6 hover:text-white/75'}`}>
            <WrapText size={12} /> {wrap ? 'Wrap' : 'No wrap'}
          </button>
          <button type="button" onClick={() => void copy()} className="flex h-7 items-center gap-1 rounded-md border border-white/8 px-2 text-[10px] text-white/45 hover:bg-white/6 hover:text-white/75">
            {copyState === 'copied' ? <Check size={12} className="text-emerald-300" /> : <Copy size={12} />}
            {copyState === 'copied' ? 'Copied' : copyState === 'failed' ? 'Copy failed' : 'Copy'}
          </button>
        </div>
      </div>

      <div ref={codeRef} className="max-h-[58vh] overflow-auto font-mono text-[11px] leading-5" role="region" aria-label={`${filename} source`}>
        <div className={wrap ? 'min-w-0' : 'min-w-max'}>
          {tokenizedLines.map((tokens, index) => (
            <div key={index} className="flex hover:bg-white/[0.025]">
              <span className="sticky left-0 z-10 w-12 shrink-0 select-none border-r border-white/5 bg-[#0b0b10] pr-3 text-right text-white/20">{index + 1}</span>
              <span className={`flex-1 px-3 text-white/70 ${wrap ? 'whitespace-pre-wrap break-words' : 'whitespace-pre'}`} style={{ tabSize: 2 }}>
                {tokens.length ? tokens.map((token, tokenIndex) => renderToken(token, deferredQuery, tokenIndex)) : '\u00A0'}
              </span>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
