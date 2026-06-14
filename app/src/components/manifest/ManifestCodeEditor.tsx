import { useMemo, useRef, type UIEvent } from 'react'

interface ManifestCodeEditorProps {
  value: string
  onChange: (value: string) => void
}

type TokenKind = 'plain' | 'comment' | 'table' | 'key' | 'string' | 'number' | 'boolean' | 'punctuation'

interface Token {
  kind: TokenKind
  value: string
}

const TOKEN_COLORS: Record<TokenKind, string> = {
  plain: 'text-white/70',
  comment: 'text-[#697386]',
  table: 'text-[#c4a7ff]',
  key: 'text-[#7dd3fc]',
  string: 'text-[#a7f3d0]',
  number: 'text-[#fbbf8a]',
  boolean: 'text-[#f0abfc]',
  punctuation: 'text-white/35',
}

function tokenizeValue(value: string): Token[] {
  const tokens: Token[] = []
  let remaining = value

  while (remaining) {
    const match = remaining.match(
      /^(#[^\n]*|"(?:\\.|[^"\\])*"|'[^']*'|\b(?:true|false)\b|\b[-+]?(?:0x[\da-fA-F]+|0o[0-7]+|0b[01]+|\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)\b|(?:\[|\]|[{},.])|\s+|[^#"'{}[\],.\s]+)/,
    )
    const token = match?.[0] || remaining[0]

    let kind: TokenKind = 'plain'
    if (token.startsWith('#')) kind = 'comment'
    else if (token.startsWith('"') || token.startsWith("'")) kind = 'string'
    else if (/^(true|false)$/.test(token)) kind = 'boolean'
    else if (/^[-+]?(?:0x[\da-fA-F]+|0o[0-7]+|0b[01]+|\d)/.test(token)) kind = 'number'
    else if (/^(?:\[|\]|[{},.])$/.test(token)) kind = 'punctuation'

    tokens.push({ kind, value: token })
    remaining = remaining.slice(token.length)
  }

  return tokens
}

export function tokenizeTomlLine(line: string): Token[] {
  if (/^\s*#/.test(line)) return [{ kind: 'comment', value: line }]

  const tableMatch = line.match(/^(\s*)(\[\[?[^\]]+\]?\])(\s*)(#.*)?$/)
  if (tableMatch) {
    return [
      { kind: 'plain', value: tableMatch[1] },
      { kind: 'table', value: tableMatch[2] },
      { kind: 'plain', value: tableMatch[3] },
      ...(tableMatch[4] ? [{ kind: 'comment' as const, value: tableMatch[4] }] : []),
    ]
  }

  const assignmentMatch = line.match(/^(\s*)([A-Za-z0-9_.-]+)(\s*=\s*)(.*)$/)
  if (assignmentMatch) {
    return [
      { kind: 'plain', value: assignmentMatch[1] },
      { kind: 'key', value: assignmentMatch[2] },
      { kind: 'punctuation', value: assignmentMatch[3] },
      ...tokenizeValue(assignmentMatch[4]),
    ]
  }

  return tokenizeValue(line)
}

export default function ManifestCodeEditor({ value, onChange }: ManifestCodeEditorProps) {
  const highlightRef = useRef<HTMLPreElement>(null)
  const highlightedLines = useMemo(() => value.split('\n').map(tokenizeTomlLine), [value])

  const syncScroll = (event: UIEvent<HTMLTextAreaElement>) => {
    if (!highlightRef.current) return
    highlightRef.current.scrollTop = event.currentTarget.scrollTop
    highlightRef.current.scrollLeft = event.currentTarget.scrollLeft
  }

  return (
    <div className="relative flex-1 min-h-0 overflow-hidden bg-[#0b0b10]">
      <pre
        ref={highlightRef}
        aria-hidden="true"
        className="pointer-events-none absolute inset-0 overflow-hidden whitespace-pre p-4 text-[13px] font-mono leading-relaxed"
        style={{ tabSize: 2 }}
      >
        {highlightedLines.map((tokens, lineIndex) => (
          <span key={lineIndex}>
            {tokens.map((token, tokenIndex) => (
              <span key={tokenIndex} className={TOKEN_COLORS[token.kind]}>
                {token.value}
              </span>
            ))}
            {lineIndex < highlightedLines.length - 1 ? '\n' : null}
          </span>
        ))}
      </pre>
      <textarea
        value={value}
        onChange={(event) => onChange(event.target.value)}
        onScroll={syncScroll}
        spellCheck={false}
        aria-label="RailDock manifest"
        className="absolute inset-0 h-full w-full resize-none overflow-auto whitespace-pre bg-transparent p-4 text-[13px] font-mono leading-relaxed text-transparent caret-white selection:bg-[#8b5cf6]/35 focus:outline-none"
        style={{ tabSize: 2 }}
      />
    </div>
  )
}
