import { useState, useCallback } from 'react'
import { Copy, Check } from 'lucide-react'
import { copyToClipboard } from '@/lib/clipboard'

interface CopyButtonProps {
  text: string
  size?: number
  className?: string
  title?: string
}

export function CopyButton({ text, size = 12, className = '', title = 'Copy' }: CopyButtonProps) {
  const [copied, setCopied] = useState(false)

  const handleCopy = useCallback(async (e: React.MouseEvent) => {
    e.stopPropagation()
    const success = await copyToClipboard(text)
    if (success) {
      setCopied(true)
      setTimeout(() => setCopied(false), 1500)
    }
  }, [text])

  return (
    <button
      onClick={handleCopy}
      className={`p-1 rounded hover:bg-white/[0.06] text-white/20 hover:text-white/50 transition-all ${className}`}
      title={title}
      type="button"
    >
      {copied ? (
        <Check size={size} className="text-emerald-400" />
      ) : (
        <Copy size={size} />
      )}
    </button>
  )
}
