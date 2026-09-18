import { useMemo, useState } from 'react'
import { AlertTriangle, Check, Copy, Loader2 } from 'lucide-react'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { useDuplicateEnvironment } from '@/hooks/useEnvironments'
import type { Environment, EnvironmentDuplicateSummary } from '@/types'
import { duplicateHighlights, suggestEnvironmentName } from './duplicateEnvironment'

interface DuplicateEnvironmentDialogProps {
  projectId: string
  source: Environment | null
  environments: Environment[]
  open: boolean
  onOpenChange: (open: boolean) => void
  onDuplicated?: (environment: Environment) => void
}

interface StagedResult {
  environment: Environment
  summary: EnvironmentDuplicateSummary
}

/**
 * Railway's "Duplicate environment" flow: name the copy, then review what was
 * staged before anything is deployed.
 *
 * The staging part is the important one. A duplicate never touches the Dokku
 * host — every copied service starts `stopped` with no deployment — so the
 * dialog ends on a summary ("5 services · 12 variables · 1 new volume") and the
 * warnings that explain what deliberately did *not* travel, such as custom
 * domains (two apps cannot serve one hostname) and bind mounts that now share a
 * host directory.
 */
export default function DuplicateEnvironmentDialog({
  projectId,
  source,
  environments,
  open,
  onOpenChange,
  onDuplicated,
}: DuplicateEnvironmentDialogProps) {
  const duplicateEnvironment = useDuplicateEnvironment()
  const [draft, setDraft] = useState('')
  const [edited, setEdited] = useState(false)
  const [result, setResult] = useState<StagedResult | null>(null)

  const suggested = useMemo(
    () => (source ? suggestEnvironmentName(source.name, environments.map((environment) => environment.name)) : ''),
    [source, environments],
  )

  // The suggestion is derived, not copied into state by an effect: the
  // environment list can re-render underneath an open dialog (a fetch settling,
  // a live update) and an effect that re-seeded the field would wipe whatever
  // the operator had typed.
  const name = edited ? draft : suggested

  if (!source) return null

  const handleDuplicate = () => {
    const trimmed = name.trim()
    if (!trimmed) return
    duplicateEnvironment.mutate(
      { projectId, id: source.id, data: { name: trimmed } },
      { onSuccess: (response) => setResult(response) },
    )
  }

  const close = (notify: boolean) => {
    const duplicated = result
    setEdited(false)
    setDraft('')
    setResult(null)
    onOpenChange(false)
    if (notify && duplicated) onDuplicated?.(duplicated.environment)
  }

  return (
    <Dialog open={open} onOpenChange={(next) => (next ? onOpenChange(true) : close(false))}>
      <DialogContent className="max-w-[460px]">
        <DialogHeader>
          <DialogTitle>{result ? `${result.environment.name} created` : `Duplicate ${source.name}`}</DialogTitle>
          <DialogDescription>
            {result ? (
              <>
                Everything was copied and <span className="text-white/60">staged</span> — nothing has been
                deployed yet.
              </>
            ) : (
              <>
                Copies every service in <span className="text-white/60">{source.name}</span>, along with its
                variables, volumes and backup schedules, into a new environment. The copies are staged, not
                deployed.
              </>
            )}
          </DialogDescription>
        </DialogHeader>

        {result ? (
          <div className="space-y-3">
            <div className="flex items-start gap-2.5 rounded-lg border border-emerald-500/20 bg-emerald-500/[0.06] p-3">
              <Check size={14} className="mt-0.5 shrink-0 text-emerald-400" />
              <p className="text-[11px] leading-relaxed text-white/60">
                {duplicateHighlights(result.summary).join(' · ') || 'Nothing to copy — the environment is empty'}
              </p>
            </div>
            {result.summary.warnings.map((warning) => (
              <div key={warning} className="flex items-start gap-2.5 rounded-lg border border-amber-500/20 bg-amber-500/[0.06] p-3">
                <AlertTriangle size={13} className="mt-0.5 shrink-0 text-amber-400" />
                <p className="text-[11px] leading-relaxed text-amber-100/70">{warning}</p>
              </div>
            ))}
            <p className="text-[10px] leading-relaxed text-white/30">
              Deploy a copy from its service page when you are ready. Until then it holds no host resources.
            </p>
          </div>
        ) : (
          <div className="space-y-1.5">
            <label htmlFor="duplicate-environment-name" className="text-[11px] text-[#8a8a99]">
              New environment name
            </label>
            <input
              id="duplicate-environment-name"
              value={name}
              autoFocus
              onChange={(event) => { setEdited(true); setDraft(event.target.value) }}
              onKeyDown={(event) => { if (event.key === 'Enter') handleDuplicate() }}
              placeholder="staging"
              className="w-full rounded-lg border border-[rgba(255,255,255,0.08)] bg-[#0B0B0D] px-3 py-2.5 text-sm text-white outline-none transition-colors focus:border-[rgba(139,92,246,0.5)]"
            />
          </div>
        )}

        <DialogFooter>
          {result ? (
            <button
              type="button"
              onClick={() => close(true)}
              className="rounded-lg bg-rail-purple px-3 py-2 text-[12px] font-medium text-white transition-colors hover:bg-rail-purple-dark"
            >
              Review {result.environment.name}
            </button>
          ) : (
            <>
              <button
                type="button"
                onClick={() => close(false)}
                className="rounded-lg border border-[rgba(255,255,255,0.08)] px-3 py-2 text-[12px] text-[#A0A0B0] transition-colors hover:bg-[rgba(255,255,255,0.04)]"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleDuplicate}
                disabled={!name.trim() || duplicateEnvironment.isPending}
                className="flex items-center gap-1.5 rounded-lg bg-rail-purple px-3 py-2 text-[12px] font-medium text-white transition-colors hover:bg-rail-purple-dark disabled:cursor-not-allowed disabled:opacity-40"
              >
                {duplicateEnvironment.isPending ? (
                  <Loader2 size={12} className="animate-spin" />
                ) : (
                  <Copy size={12} />
                )}
                {duplicateEnvironment.isPending ? 'Copying…' : 'Duplicate'}
              </button>
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
