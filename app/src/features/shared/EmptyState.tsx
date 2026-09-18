import type { LucideIcon } from 'lucide-react'
import type { ReactNode } from 'react'
import { cn } from '@/lib/utils'

interface EmptyStateProps {
  icon?: LucideIcon
  title: string
  description?: string
  /** Primary call to action (button/link). */
  action?: ReactNode
  /** Optional secondary line under the action. */
  hint?: string
  className?: string
}

/**
 * One consistent empty state for lists and panels, so "you have nothing yet"
 * and "your filter matched nothing" can be presented deliberately instead of
 * reusing the same stray copy in every page.
 */
export default function EmptyState({
  icon: Icon,
  title,
  description,
  action,
  hint,
  className,
}: EmptyStateProps) {
  return (
    <div className={cn('flex flex-col items-center justify-center px-6 py-14 text-center', className)}>
      {Icon && (
        <div className="mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-white/[0.04]">
          <Icon size={22} className="text-white/50" />
        </div>
      )}
      <h3 className="text-[15px] font-semibold text-white/85">{title}</h3>
      {description && <p className="mt-1 max-w-md text-[13px] text-white/55">{description}</p>}
      {action && <div className="mt-4">{action}</div>}
      {hint && <p className="mt-3 text-[11px] text-white/50">{hint}</p>}
    </div>
  )
}
