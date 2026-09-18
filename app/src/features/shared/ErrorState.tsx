import { AlertTriangle, RefreshCw } from 'lucide-react'
import { cn } from '@/lib/utils'

interface ErrorStateProps {
  /** Short headline, e.g. "Couldn't load projects". */
  title?: string
  /** What happened / what to do about it. */
  message?: string
  /** Called when the user clicks retry. Omit to hide the button. */
  onRetry?: () => void
  className?: string
}

/**
 * Rendered when a query fails, so a failed request is never mistaken for an
 * empty list. Pages used to destructure `{ data = [], isLoading }` and show
 * "Nothing here yet" even when the request had simply errored.
 */
export default function ErrorState({
  title = 'Something went wrong',
  message = 'We could not load this. Check your connection and try again.',
  onRetry,
  className,
}: ErrorStateProps) {
  return (
    <div
      role="alert"
      className={cn(
        'flex flex-col items-center justify-center rounded-xl border border-red-500/20 bg-red-500/[0.06] px-6 py-10 text-center',
        className
      )}
    >
      <div className="mb-3 flex h-11 w-11 items-center justify-center rounded-full bg-red-500/10">
        <AlertTriangle size={20} className="text-red-400" />
      </div>
      <h3 className="text-[15px] font-semibold text-white/90">{title}</h3>
      <p className="mt-1 max-w-md text-[13px] text-white/60">{message}</p>
      {onRetry && (
        <button
          type="button"
          onClick={onRetry}
          className="mt-4 inline-flex items-center gap-1.5 rounded-lg bg-[#8b5cf6]/15 px-3 py-1.5 text-[13px] font-medium text-[#c4b5fd] transition-colors hover:bg-[#8b5cf6]/25 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#a78bfa]"
        >
          <RefreshCw size={13} />
          Try again
        </button>
      )}
    </div>
  )
}
