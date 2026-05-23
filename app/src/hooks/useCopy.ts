import { useState, useCallback } from 'react'
import { copyToClipboard } from '@/lib/clipboard'

export function useCopy(timeout = 1500) {
  const [copiedKey, setCopiedKey] = useState<string | null>(null)

  const copy = useCallback(async (text: string, key: string) => {
    const success = await copyToClipboard(text)
    if (success) {
      setCopiedKey(key)
      setTimeout(() => setCopiedKey((current) => (current === key ? null : current)), timeout)
    }
  }, [timeout])

  return { copiedKey, copy }
}
