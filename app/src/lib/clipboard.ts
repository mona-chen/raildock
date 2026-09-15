import { toast } from 'sonner'

/**
 * Copy text to the clipboard, reporting honestly whether it worked.
 *
 * The async Clipboard API only exists in secure contexts, so an HTTP-served
 * RailDock has to fall back to `execCommand`. That fallback is also tried when
 * `navigator.clipboard` exists but the write is rejected — some browsers expose
 * the API on an insecure origin and only fail once it is used.
 */
export async function copyToClipboard(text: string): Promise<boolean> {
  const copied = (await writeWithClipboardApi(text)) || writeWithSelection(text)

  if (copied) {
    toast.success('Copied to clipboard')
  } else {
    toast.error('Could not copy automatically — select the text and copy it manually')
  }

  return copied
}

async function writeWithClipboardApi(text: string): Promise<boolean> {
  if (!navigator.clipboard?.writeText) return false

  try {
    await navigator.clipboard.writeText(text)
    return true
  } catch {
    return false
  }
}

/**
 * Legacy fallback for insecure contexts.
 *
 * The command copies whatever is selected at the moment it runs, so the
 * scratch element has to stay in the document, be focused, and hold its
 * selection — otherwise `execCommand` reports success while copying nothing.
 */
function writeWithSelection(text: string): boolean {
  if (typeof document.execCommand !== 'function') return false

  const textarea = document.createElement('textarea')
  textarea.value = text
  textarea.setAttribute('readonly', '')
  textarea.setAttribute('aria-hidden', 'true')
  textarea.setAttribute('tabindex', '-1')

  // On-screen but visually invisible: browsers may refuse to copy from an
  // element parked off-screen, and may scroll it into view if it is merely
  // hidden behind overflow.
  Object.assign(textarea.style, {
    position: 'fixed',
    top: '0',
    left: '0',
    width: '1px',
    height: '1px',
    padding: '0',
    border: 'none',
    outline: 'none',
    boxShadow: 'none',
    background: 'transparent',
    opacity: '0',
    pointerEvents: 'none',
  })

  const previouslyFocused = document.activeElement as HTMLElement | null
  document.body.appendChild(textarea)

  try {
    textarea.focus({ preventScroll: true })
    textarea.select()
    textarea.setSelectionRange(0, text.length)
    return document.execCommand('copy')
  } catch {
    return false
  } finally {
    document.body.removeChild(textarea)
    previouslyFocused?.focus?.({ preventScroll: true })
  }
}
