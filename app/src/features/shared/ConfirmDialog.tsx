import { useEffect, useState } from 'react'
import { AlertTriangle, Loader2 } from 'lucide-react'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { cn, confirmationFieldTone } from '@/lib/utils'

interface ConfirmDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  title: string
  description?: React.ReactNode
  confirmLabel?: string
  cancelLabel?: string
  /** Style the confirm button as a destructive (red) action. */
  destructive?: boolean
  /**
   * When set, the user must type this exact string before confirming. Used for
   * destructive actions where the impact should be acknowledged, replacing the
   * native `window.confirm()` popups that give no impact detail.
   */
  confirmWord?: string
  confirmWordLabel?: React.ReactNode
  /** Extra caution copy shown above the confirm button. */
  warning?: React.ReactNode
  onConfirm: () => void | Promise<void>
  pending?: boolean
  error?: string | null
}

/**
 * App-styled confirmation built on the shadcn Dialog primitive, so focus
 * trapping, Escape and ARIA come from Radix instead of being re-implemented per
 * screen. Replaces `window.confirm()` and the hand-rolled overlays.
 */
export default function ConfirmDialog({
  open,
  onOpenChange,
  title,
  description,
  confirmLabel = 'Confirm',
  cancelLabel = 'Cancel',
  destructive = false,
  confirmWord,
  confirmWordLabel,
  warning,
  onConfirm,
  pending = false,
  error,
}: ConfirmDialogProps) {
  const [typed, setTyped] = useState('')

  useEffect(() => {
    if (!open) setTyped('')
  }, [open])

  const requiresWord = typeof confirmWord === 'string' && confirmWord.length > 0
  const wordSatisfied = !requiresWord || typed === confirmWord
  const canConfirm = wordSatisfied && !pending

  const handleConfirm = async () => {
    if (!canConfirm) return
    await onConfirm()
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !pending && onOpenChange(next)}>
      <DialogContent className="bg-[#161618] border-[rgba(255,255,255,0.08)] text-[#F0F1F3] sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-[15px]">
            {destructive && <AlertTriangle size={16} className="text-red-400" />}
            {title}
          </DialogTitle>
          {description && (
            <DialogDescription className="text-[12px] leading-relaxed text-white/60">
              {description}
            </DialogDescription>
          )}
        </DialogHeader>

        {warning && (
          <div className="rounded-lg border border-amber-500/20 bg-amber-500/10 p-2.5 text-[11px] leading-relaxed text-amber-200">
            {warning}
          </div>
        )}

        {requiresWord && (
          <div>
            <label className="mb-1.5 block text-[11px] text-white/50" htmlFor="confirm-dialog-word">
              {confirmWordLabel ?? (
                <>
                  Type <span className="font-mono font-medium text-white">{confirmWord}</span> to confirm
                </>
              )}
            </label>
            <input
              id="confirm-dialog-word"
              value={typed}
              onChange={(e) => setTyped(e.target.value)}
              autoComplete="off"
              spellCheck={false}
              disabled={pending}
              aria-invalid={typed.length > 0 && !wordSatisfied}
              className={cn(
                'w-full rounded-lg border bg-[#0B0B0D] px-3 py-2.5 text-sm text-white outline-none transition-colors',
                confirmationFieldTone(typed, wordSatisfied)
              )}
            />
          </div>
        )}

        {error && (
          <div role="alert" className="rounded-lg border border-red-500/20 bg-red-500/10 p-2.5 text-[11px] text-red-300">
            {error}
          </div>
        )}

        <DialogFooter className="gap-2 sm:gap-2">
          <button
            type="button"
            onClick={() => onOpenChange(false)}
            disabled={pending}
            className="rounded-lg border border-[rgba(255,255,255,0.08)] px-4 py-2.5 text-[13px] text-[#A0A0B0] transition-colors hover:bg-[rgba(255,255,255,0.04)] disabled:opacity-50"
          >
            {cancelLabel}
          </button>
          <button
            type="button"
            onClick={handleConfirm}
            disabled={!canConfirm}
            className={cn(
              'inline-flex items-center justify-center gap-1.5 rounded-lg px-4 py-2.5 text-[13px] font-medium text-white transition-colors disabled:cursor-not-allowed disabled:opacity-40',
              destructive ? 'bg-red-500 hover:bg-red-600' : 'bg-[#8b5cf6] hover:bg-[#7c3aed]'
            )}
          >
            {pending && <Loader2 size={13} className="animate-spin" />}
            {confirmLabel}
          </button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
