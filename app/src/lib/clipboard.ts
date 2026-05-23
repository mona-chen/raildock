import { toast } from 'sonner'

/**
 * Copy text to clipboard with a fallback for non-secure contexts (HTTP).
 * Shows a toast on success/error.
 */
export async function copyToClipboard(text: string): Promise<boolean> {
  try {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      await navigator.clipboard.writeText(text)
    } else {
      // Fallback for non-secure contexts (HTTP) or missing clipboard API
      const textarea = document.createElement('textarea')
      textarea.value = text
      textarea.style.position = 'fixed'
      textarea.style.left = '-9999px'
      textarea.style.top = '-9999px'
      document.body.appendChild(textarea)
      textarea.focus()
      textarea.select()
      const success = document.execCommand('copy')
      document.body.removeChild(textarea)
      if (!success) throw new Error('execCommand copy failed')
    }
    toast.success('Copied to clipboard')
    return true
  } catch (err) {
    toast.error('Failed to copy')
    return false
  }
}
