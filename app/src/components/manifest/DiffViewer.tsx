import { Plus, Minus, Pencil } from 'lucide-react'
import ChangeBadge from './ChangeBadge'
import type { ManifestChange } from '@/lib/api'

interface DiffViewerProps {
  changes: ManifestChange[]
  severity?: 'reload' | 'restart' | 'redeploy'
  warnings?: string[]
}

function ChangeRow({ change }: { change: ManifestChange }) {
  const iconMap = {
    added: { icon: Plus, color: 'text-emerald-400', bg: 'bg-emerald-500/10' },
    removed: { icon: Minus, color: 'text-rose-400', bg: 'bg-rose-500/10' },
    modified: { icon: Pencil, color: 'text-amber-400', bg: 'bg-amber-500/10' },
  }

  const { icon: Icon, color, bg } = iconMap[change.changeType] || iconMap.modified

  const formatValue = (val: unknown): string => {
    if (val === null || val === undefined) return 'null'
    if (typeof val === 'string') return val
    if (typeof val === 'number' || typeof val === 'boolean') return String(val)
    return JSON.stringify(val, null, 2)
  }

  return (
    <div className="flex items-start gap-3 py-2.5 border-b border-white/[0.04] last:border-0">
      <div className={`mt-0.5 w-5 h-5 rounded flex items-center justify-center flex-shrink-0 ${bg}`}>
        <Icon size={12} className={color} />
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 mb-1">
          <span className="text-[13px] text-white/70 font-medium">{change.serviceName}</span>
          <span className="text-[11px] text-white/30">·</span>
          <span className="text-[11px] text-white/40 font-mono">{change.field}</span>
          <ChangeBadge severity={change.severity} size="sm" />
        </div>
        {change.changeType === 'modified' && (
          <div className="space-y-1">
            <div className="text-[11px] text-white/30 line-through">{formatValue(change.oldValue)}</div>
            <div className="text-[11px] text-white/60">{formatValue(change.newValue)}</div>
          </div>
        )}
        {change.changeType === 'added' && (
          <div className="text-[11px] text-emerald-400/70">{formatValue(change.newValue)}</div>
        )}
        {change.changeType === 'removed' && (
          <div className="text-[11px] text-rose-400/70 line-through">{formatValue(change.oldValue)}</div>
        )}
      </div>
    </div>
  )
}

export default function DiffViewer({ changes, severity, warnings }: DiffViewerProps) {
  if (changes.length === 0) {
    return (
      <div className="text-center py-8">
        <div className="text-[13px] text-white/40">No changes detected</div>
        <div className="text-[11px] text-white/25 mt-1">Your manifest is in sync with the current state</div>
      </div>
    )
  }

  const byService = changes.reduce<Record<string, ManifestChange[]>>((acc, c) => {
    acc[c.serviceName] = acc[c.serviceName] || []
    acc[c.serviceName].push(c)
    return acc
  }, {})

  const severityCounts = changes.reduce<Record<string, number>>((acc, c) => {
    acc[c.severity] = (acc[c.severity] || 0) + 1
    return acc
  }, {})

  return (
    <div className="space-y-3">
      {warnings && warnings.length > 0 && (
        <div className="bg-amber-500/5 border border-amber-500/15 rounded-lg p-3">
          <div className="text-[11px] text-amber-400/70 font-medium mb-1">Warnings</div>
          {warnings.map((w, i) => (
            <div key={i} className="text-[11px] text-amber-400/50">· {w}</div>
          ))}
        </div>
      )}

      <div className="flex items-center gap-3">
        <div className="text-[12px] text-white/50">
          {changes.length} change{changes.length !== 1 ? 's' : ''}
        </div>
        {severity && (
          <ChangeBadge severity={severity} size="md" />
        )}
        <div className="flex-1" />
        {severityCounts.reload && severityCounts.reload > 0 && (
          <span className="text-[10px] text-emerald-400/50">{severityCounts.reload} reload</span>
        )}
        {severityCounts.restart && severityCounts.restart > 0 && (
          <span className="text-[10px] text-amber-400/50">{severityCounts.restart} restart</span>
        )}
        {severityCounts.redeploy && severityCounts.redeploy > 0 && (
          <span className="text-[10px] text-rose-400/50">{severityCounts.redeploy} redeploy</span>
        )}
      </div>

      <div className="bg-white/[0.02] border border-white/[0.06] rounded-lg">
        {Object.entries(byService).map(([serviceName, serviceChanges]) => (
          <div key={serviceName} className="px-3">
            <div className="text-[11px] text-white/30 uppercase tracking-wider py-2 border-b border-white/[0.04]">
              {serviceName}
            </div>
            <div>
              {serviceChanges.map((change, idx) => (
                <ChangeRow key={idx} change={change} />
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
