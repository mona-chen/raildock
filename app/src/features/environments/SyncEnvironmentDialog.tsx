import { useMemo, useState } from 'react'
import { ArrowRight, Check, Loader2, MinusCircle, PlusCircle, RefreshCw, PencilLine, ShieldAlert } from 'lucide-react'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { useEnvironmentSyncPlan, useSyncEnvironment } from '@/hooks/useEnvironments'
import type { Environment, EnvironmentSyncChange } from '@/types'

interface SyncEnvironmentDialogProps {
  projectId: string
  target: Environment | null
  environments: Environment[]
  open: boolean
  onOpenChange: (open: boolean) => void
}

/**
 * Railway's staged-change review, applied to environments.
 *
 * The dialog is deliberately two-step: pick the environment to pull from, read
 * the diff (`Added` / `Edited` / `Removed`), and only then apply. The diff is a
 * *query* — opening and closing the dialog writes nothing.
 *
 * The one rule the UI has to state plainly is that a sync never deletes. A
 * service can own a database, a volume and a set of backup artifacts, and the
 * only sanctioned way to remove one is the guarded destroy flow that snapshots
 * first and asks for the service name back. Services listed under "Removed"
 * are reported so the operator can deal with them deliberately.
 */
export default function SyncEnvironmentDialog({
  projectId,
  target,
  environments,
  open,
  onOpenChange,
}: SyncEnvironmentDialogProps) {
  const candidates = useMemo(
    () => environments.filter((environment) => environment.id !== target?.id),
    [environments, target],
  )
  const [selectedSourceId, setSelectedSourceId] = useState('')

  // Derived rather than stored: the picker defaults to the project's default
  // environment (it is the one an operator usually pulls from), and a selection
  // that no longer belongs to this project falls back instead of silently
  // pointing at an environment the dialog does not list.
  const fallbackSource = candidates.find((environment) => environment.isDefault) ?? candidates[0]
  const sourceId = candidates.some((environment) => environment.id === selectedSourceId)
    ? selectedSourceId
    : (fallbackSource?.id ?? '')

  const plan = useEnvironmentSyncPlan(projectId, target?.id, sourceId)
  const syncEnvironment = useSyncEnvironment()

  if (!target) return null

  const summary = plan.data?.summary
  const nothingToDo = summary ? summary.inSync : false

  const apply = () => {
    if (!sourceId) return
    syncEnvironment.mutate({ projectId, id: target.id, sourceId })
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        // Drop the picker so the next opening re-derives its default.
        if (!next) setSelectedSourceId('')
        onOpenChange(next)
      }}
    >
      <DialogContent className="max-w-[560px]">
        <DialogHeader>
          <DialogTitle>Sync into {target.name}</DialogTitle>
          <DialogDescription>
            Copy the services and configuration of another environment into{' '}
            <span className="text-white/60">{target.name}</span>. Additions and edits only — nothing is ever
            deleted, and nothing deploys.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="space-y-1.5">
            <span className="text-[11px] text-[#8a8a99]">Pull from</span>
            <div className="flex flex-wrap gap-1.5">
              {candidates.map((environment) => {
                const isActive = environment.id === sourceId
                return (
                  <button
                    key={environment.id}
                    type="button"
                    onClick={() => setSelectedSourceId(environment.id)}
                    aria-pressed={isActive}
                    className={`flex items-center gap-1.5 rounded-lg border px-2.5 py-1.5 text-[11px] transition-colors ${
                      isActive
                        ? 'border-rail-purple/50 bg-rail-purple/10 text-white'
                        : 'border-white/[0.08] text-white/50 hover:border-white/[0.16] hover:text-white/80'
                    }`}
                  >
                    {isActive && <Check size={11} className="text-rail-purple" />}
                    {environment.name}
                    <span className="text-white/30">{environment.serviceCount ?? 0}</span>
                  </button>
                )
              })}
              {candidates.length === 0 && (
                <p className="text-[11px] text-white/35">
                  This project has no other environment to sync from yet.
                </p>
              )}
            </div>
          </div>

          {plan.isLoading && sourceId && (
            <div className="flex items-center gap-2 rounded-lg border border-white/[0.06] bg-black/20 p-3 text-[11px] text-white/40">
              <Loader2 size={12} className="animate-spin" /> Comparing environments…
            </div>
          )}

          {plan.isError && (
            <button
              type="button"
              onClick={() => plan.refetch()}
              className="w-full rounded-lg border border-red-500/20 bg-red-500/[0.06] p-3 text-left text-[11px] text-red-300"
            >
              Could not compare these environments — retry
            </button>
          )}

          {plan.data && (
            <div className="max-h-[280px] space-y-2 overflow-y-auto rounded-lg border border-white/[0.06] bg-black/20 p-3">
              {nothingToDo ? (
                <div className="flex items-center gap-2 text-[11px] text-emerald-300/80">
                  <Check size={13} className="text-emerald-400" />
                  Already in sync with {plan.data.sourceEnvironmentName}.
                </div>
              ) : (
                <>
                  <ChangeGroup
                    icon={<PlusCircle size={12} className="text-emerald-400" />}
                    tone="text-emerald-400"
                    label="Added"
                    changes={plan.data.added}
                  />
                  <ChangeGroup
                    icon={<PencilLine size={12} className="text-amber-400" />}
                    tone="text-amber-400"
                    label="Edited"
                    changes={plan.data.edited}
                  />
                  <ChangeGroup
                    icon={<MinusCircle size={12} className="text-white/40" />}
                    tone="text-white/40"
                    label="Removed"
                    changes={plan.data.removed}
                    footnote="Left alone — remove these individually from the canvas."
                  />
                </>
              )}
            </div>
          )}

          {plan.data && plan.data.removed.length > 0 && (
            <p className="flex items-start gap-2 text-[10px] leading-relaxed text-white/35">
              <ShieldAlert size={12} className="mt-0.5 shrink-0 text-white/30" />
              A service can own a database, a volume and backups, so a sync never destroys one. The
              {` ${plan.data.removed.length} `}
              service{plan.data.removed.length === 1 ? '' : 's'} under Removed stay exactly as they are.
            </p>
          )}
        </div>

        <DialogFooter>
          <button
            type="button"
            onClick={() => onOpenChange(false)}
            className="rounded-lg border border-[rgba(255,255,255,0.08)] px-3 py-2 text-[12px] text-[#A0A0B0] transition-colors hover:bg-[rgba(255,255,255,0.04)]"
          >
            Close
          </button>
          <button
            type="button"
            onClick={apply}
            disabled={!sourceId || nothingToDo || syncEnvironment.isPending || !plan.data}
            className="flex items-center gap-1.5 rounded-lg bg-rail-purple px-3 py-2 text-[12px] font-medium text-white transition-colors hover:bg-rail-purple-dark disabled:cursor-not-allowed disabled:opacity-40"
          >
            {syncEnvironment.isPending ? (
              <Loader2 size={12} className="animate-spin" />
            ) : (
              <RefreshCw size={12} />
            )}
            {syncEnvironment.isPending ? 'Applying…' : `Apply to ${target.name}`}
          </button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function ChangeGroup({
  icon,
  tone,
  label,
  changes,
  footnote,
}: {
  icon: React.ReactNode
  tone: string
  label: string
  changes: EnvironmentSyncChange[]
  footnote?: string
}) {
  if (changes.length === 0) return null

  return (
    <div className="space-y-1">
      <div className={`flex items-center gap-1.5 text-[10px] font-medium uppercase tracking-[0.1em] ${tone}`}>
        {icon}
        {label}
        <span className="text-white/25">{changes.length}</span>
      </div>
      <ul className="space-y-0.5">
        {changes.map((change) => (
          <li key={`${label}-${change.name}`} className="flex items-start gap-1.5 pl-4 text-[11px]">
            <ArrowRight size={10} className="mt-1 shrink-0 text-white/20" />
            <span className="min-w-0">
              <span className="text-white/70">{change.name}</span>
              {label === 'Edited' && change.changes.length > 0 && (
                <span className="text-white/35"> — {change.changes.join(', ')}</span>
              )}
            </span>
          </li>
        ))}
      </ul>
      {footnote && <p className="pl-4 text-[10px] text-white/25">{footnote}</p>}
    </div>
  )
}
