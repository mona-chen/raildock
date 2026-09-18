import { cn } from '@/lib/utils'
import { statusMeta } from '@/lib/status'

/**
 * Consistent status pill for services and deployments. Before this the same
 * pill was re-implemented inline (and disagreed) in OverviewTab and ServicePanel.
 */
export default function StatusBadge({ status, className }: { status: string; className?: string }) {
  const meta = statusMeta(status)

  return (
    <span
      className={cn('inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11px] font-medium', className)}
      style={{ backgroundColor: `${meta.color}1a`, color: meta.color }}
    >
      <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: meta.color }} />
      {meta.label}
    </span>
  )
}
