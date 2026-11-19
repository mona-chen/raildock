import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { copyToClipboard } from '@/lib/clipboard'

vi.mock('sonner', () => ({
  toast: { success: vi.fn(), error: vi.fn() },
}))

import { toast } from 'sonner'

describe('copyToClipboard', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    document.body.innerHTML = ''
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('uses the async clipboard API when the context is secure', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined)
    vi.stubGlobal('navigator', { clipboard: { writeText } })

    await expect(copyToClipboard('secret')).resolves.toBe(true)
    expect(writeText).toHaveBeenCalledWith('secret')
    expect(toast.error).not.toHaveBeenCalled()
  })

  // An HTTP-served instance has no navigator.clipboard at all.
  it('falls back to execCommand when the clipboard API is unavailable', async () => {
    vi.stubGlobal('navigator', {})
    const execCommand = vi.fn().mockReturnValue(true)
    document.execCommand = execCommand

    await expect(copyToClipboard('secret')).resolves.toBe(true)
    expect(execCommand).toHaveBeenCalledWith('copy')
  })

  it('selects the whole value before copying', async () => {
    vi.stubGlobal('navigator', {})
    document.execCommand = vi.fn().mockReturnValue(true)

    await copyToClipboard('0123456789abcdef')

    // The scratch element must be gone afterwards — it is added to the document
    // only for the duration of the copy.
    expect(document.querySelectorAll('textarea')).toHaveLength(0)
  })

  it('keeps the scratch element inside an open dialog so its focus trap cannot steal it', async () => {
    vi.stubGlobal('navigator', {})
    document.body.innerHTML = '<div data-slot="dialog-content"><button type="button">Copy</button></div>'
    const dialog = document.querySelector('[data-slot="dialog-content"]')!
    let activeParent = ''
    let activeValue = ''
    document.execCommand = vi.fn(() => {
      const active = document.activeElement as HTMLTextAreaElement
      activeParent = active.parentElement?.getAttribute('data-slot') ?? ''
      activeValue = active.value
      return true
    })

    await expect(copyToClipboard('secret')).resolves.toBe(true)

    expect(activeParent).toBe('dialog-content')
    expect(activeValue).toBe('secret')
    expect(dialog.querySelectorAll('textarea')).toHaveLength(0)
  })

  it('uses the synchronous fallback in an insecure context even with a clipboard shim', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined)
    vi.stubGlobal('navigator', { clipboard: { writeText } })
    const execCommand = vi.fn().mockReturnValue(true)
    document.execCommand = execCommand
    const previous = Object.getOwnPropertyDescriptor(window, 'isSecureContext')
    Object.defineProperty(window, 'isSecureContext', { configurable: true, value: false })

    try {
      await expect(copyToClipboard('secret')).resolves.toBe(true)
    } finally {
      if (previous) Object.defineProperty(window, 'isSecureContext', previous)
      else delete (window as { isSecureContext?: boolean }).isSecureContext
    }

    expect(execCommand).toHaveBeenCalledWith('copy')
    expect(writeText).not.toHaveBeenCalled()
  })

  it('falls back when the clipboard API is present but rejects', async () => {
    const writeText = vi.fn().mockRejectedValue(new Error('Document is not focused'))
    vi.stubGlobal('navigator', { clipboard: { writeText } })
    const execCommand = vi.fn().mockReturnValue(true)
    document.execCommand = execCommand

    await expect(copyToClipboard('secret')).resolves.toBe(true)
    expect(execCommand).toHaveBeenCalled()
  })

  // The bug being fixed: the button claimed success while nothing was copied.
  it('reports failure instead of claiming success when both paths fail', async () => {
    vi.stubGlobal('navigator', {})
    document.execCommand = vi.fn().mockReturnValue(false)

    await expect(copyToClipboard('secret')).resolves.toBe(false)
    expect(toast.success).not.toHaveBeenCalled()
    expect(toast.error).toHaveBeenCalled()
  })

  it('reports failure when execCommand throws', async () => {
    vi.stubGlobal('navigator', {})
    document.execCommand = vi.fn().mockImplementation(() => {
      throw new Error('not supported')
    })

    await expect(copyToClipboard('secret')).resolves.toBe(false)
    expect(toast.success).not.toHaveBeenCalled()
  })
})
