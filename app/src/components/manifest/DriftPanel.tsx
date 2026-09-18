import { useMemo, useState } from 'react'
import { ArrowRight, CheckCircle2, GitCompareArrows, Info, Loader2, Sparkles } from 'lucide-react'
import { useManifestDrift, useManifestMerge } from '@/hooks/useManifest'
import ErrorState from '@/features/shared/ErrorState'
import EmptyState from '@/features/shared/EmptyState'
import type { ManifestDriftService, ManifestMergeResult } from '@/lib/api'

const STATUS_META: Record<ManifestDriftService['status'], { label: string; className: string }> = {
  drifted: { label: 'Drifted', className: 'bg-amber-500/10 text-amber-300' },
  missing_from_manifest: { label: 'Not in manifest', className: 'bg-sky-500/10 text-sky-300' },
  missing_from_host: { label: 'Not deployed', className: 'bg-red-500/10 text-red-300' },
}

function formatValue(value: unknown): string {
  if (value === null || value === undefined || value === '') return '—'
  if (typeof value === 'object') return JSON.stringify(value)
  return String(value)
}

interface DriftPanelProps {
  projectId: string
  enabled: boolean
  onMerge: (content: string, result: ManifestMergeResult) => void
}

/**
 * Read-only view of how the stored manifest differs from the live services,
 * with an explicit "merge live values back in" step. Merging never saves: it
 * loads the proposed content into the editor so the operator reviews it, then
 * goes through the normal Preview/Apply path.
 */
export default function DriftPanel({ projectId, enabled, onMerge }: DriftPanelProps) {
  const { data, isLoading, isError, refetch } = useManifestDrift(projectId, enabled)
  const merge = useManifestMerge()
  const [selected, setSelected] = useState<string[]>([])

  const services = useMemo(() => data?.services ?? [], [data])
  const mergeable = useMemo(() => services.filter((service) => service.mergeable), [services])

  // Selection is never pre-filled, and stale names (a service that drifted
  // back into line) are pruned here rather than reset with an effect.
  const activeSelection = selected.filter((name) => mergeable.some((service) => service.name === name))

  const toggle = (name: string) =>
    setSelected((prev) => (prev.includes(name) ? prev.filter((entry) => entry !== name) : [ ...prev, name ]))

  const handleMerge = async () => {
    if (activeSelection.length === 0) return
    const result = await merge.mutateAsync({ projectId, services: activeSelection })
    onMerge(result.content, result)
  }

  if (isLoading) {
    return (
      <div className="flex h-full items-center justify-center gap-2 text-[13px] text-white/50">
        <Loader2 size={15} className="animate-spin" />
        Comparing manifest with live services…
      </div>
    )
  }

  if (isError) {
    return (
      <div className="p-4">
        <ErrorState
          title="Couldn't load manifest drift"
          message="The drift report failed to load. Check the connection and try again."
          onRetry={() => refetch()}
        />
      </div>
    )
  }

  if (data && !data.supported) {
    return (
      <EmptyState
        icon={Info}
        title={`Merging is unavailable for ${data.format}`}
        description="Compatibility manifests (railway.toml, app.json) map lossily onto RailDock's format, so live values cannot be folded back automatically. Convert this project to raildock.toml to enable merging."
      />
    )
  }

  if (services.length === 0) {
    return (
      <EmptyState
        icon={CheckCircle2}
        title="No drift detected"
        description="Every running service matches this manifest."
      />
    )
  }

  return (
    <div className="flex h-full flex-col">
      <div className="flex-1 space-y-3 overflow-y-auto p-4">
        <div className="flex items-start gap-2 rounded-lg border border-[#8b5cf6]/20 bg-[#8b5cf6]/[0.06] px-3 py-2 text-[11px] text-white/60">
          <GitCompareArrows size={14} className="mt-0.5 shrink-0 text-[#a78bfa]" />
          <span>
            These services differ from the manifest. Merging rewrites the manifest with the selected
            live values and loads it into the editor for review — nothing is saved until you Preview and Apply.
          </span>
        </div>

        {services.map((service) => {
          const meta = STATUS_META[service.status]
          const isSelected = activeSelection.includes(service.name)
          return (
            <div
              key={service.name}
              className="rounded-lg border border-white/[0.06] bg-white/[0.015] p-3"
            >
              <div className="flex items-center justify-between gap-2">
                <div className="flex items-center gap-2">
                  {service.mergeable ? (
                    <input
                      type="checkbox"
                      aria-label={`Merge ${service.name}`}
                      checked={isSelected}
                      onChange={() => toggle(service.name)}
                      className="h-3.5 w-3.5 cursor-pointer accent-[#8b5cf6]"
                    />
                  ) : (
                    <span className="h-3.5 w-3.5" />
                  )}
                  <span className="font-mono text-[12px] text-white/80">{service.name}</span>
                </div>
                <span className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${meta.className}`}>
                  {meta.label}
                </span>
              </div>

              {service.reason && (
                <p className="mt-1.5 pl-5 text-[11px] text-white/50">{service.reason}</p>
              )}

              {service.changes.length > 0 && (
                <div className="mt-2 space-y-1 pl-5">
                  {service.changes.map((change, index) => (
                    <div key={`${change.field}-${index}`} className="flex items-center gap-1.5 font-mono text-[11px]">
                      <span className="text-white/60">{change.field}</span>
                      {change.changeType === 'added_to_manifest' ? (
                        <span className="text-sky-300">add to manifest</span>
                      ) : (
                        <>
                          <span className="max-w-[160px] truncate text-white/60">{formatValue(change.manifestValue)}</span>
                          <ArrowRight size={10} className="shrink-0 text-white/40" />
                          <span className="max-w-[160px] truncate text-emerald-300">{formatValue(change.liveValue)}</span>
                        </>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>
          )
        })}
      </div>

      <div className="flex items-center justify-between gap-3 border-t border-white/[0.06] px-4 py-3">
        <button
          type="button"
          onClick={() => setSelected(mergeable.map((service) => service.name))}
          disabled={mergeable.length === 0}
          className="text-[11px] text-white/50 transition-colors hover:text-white/70 disabled:opacity-40"
        >
          Select all mergeable ({mergeable.length})
        </button>
        <button
          type="button"
          onClick={handleMerge}
          disabled={activeSelection.length === 0 || merge.isPending}
          className="flex items-center gap-1.5 rounded-lg bg-[#8b5cf6]/15 px-3 py-1.5 text-[12px] font-medium text-[#c4b5fd] transition-colors hover:bg-[#8b5cf6]/25 disabled:opacity-40"
        >
          {merge.isPending ? <Loader2 size={13} className="animate-spin" /> : <Sparkles size={13} />}
          {activeSelection.length > 0 ? `Merge ${activeSelection.length} into editor` : 'Merge into editor'}
        </button>
      </div>
    </div>
  )
}
