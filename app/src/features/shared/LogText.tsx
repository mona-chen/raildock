import { memo } from 'react'

const colors = ['#a0a0b0', '#f87171', '#86efac', '#fde047', '#93c5fd', '#c4b5fd', '#67e8f9', '#e5e7eb']

export function stripLogFormatting(text: string): string {
  // Terminal controls are data, never HTML or executable links.
  // eslint-disable-next-line no-control-regex
  return text.replace(/\x1b\][^\x07]*(?:\x07|\x1b\\)/g, '').replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, '')
}

function tone(text: string): string {
  const plain = stripLogFormatting(text)
  if (/^\s*(?:#\d+\s+)?(?:error\b|fatal\b)/i.test(plain)) return '#f87171'
  if (/\b(?:warning|warn)\b/i.test(plain)) return '#fde047'
  if (/^#\d+\s+(?:DONE|CACHED)\b|successfully (?:built|tagged)|^Build succeeded/i.test(plain)) return '#86efac'
  if (/^#\d+\s+\[|^----->/.test(plain)) return '#93c5fd'
  return '#c3c3cf'
}

export default memo(function LogText({ text }: { text: string }) {
  const chunks: React.ReactNode[] = []
  // Only the fixed 16-color SGR palette and bold are applied. All text is escaped by React.
  // eslint-disable-next-line no-control-regex
  const pattern = /\x1b\[([0-9;]*)m/g
  let color = tone(text)
  let bold = false
  let offset = 0
  const append = (part: string, key: number) => {
    if (part) chunks.push(<span key={key} style={{ color, fontWeight: bold ? 600 : undefined }}>{stripLogFormatting(part)}</span>)
  }
  for (const match of text.matchAll(pattern)) {
    append(text.slice(offset, match.index), offset)
    for (const code of (match[1] || '0').split(';').map(Number)) {
      if (code === 0) { color = tone(text); bold = false }
      if (code === 1) bold = true
      if (code === 22) bold = false
      if (code === 39) color = tone(text)
      if (code >= 30 && code <= 37) color = colors[code - 30]
      if (code >= 90 && code <= 97) color = colors[code - 90]
    }
    offset = match.index! + match[0].length
  }
  append(text.slice(offset), offset)
  return <>{chunks}</>
})
