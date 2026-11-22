import { useState, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import {
  AlertCircle,
  Archive,
  Clock3,
  Download,
  FileCheck2,
  FlaskConical,
  Loader2,
  Pencil,
  RotateCcw,
  Trash2,
} from 'lucide-react'
import {
  useDeleteBackup,
  useDestroyBackupSchedule,
  useRestoreBackup,
  useRunRestoreDrill,
  useUpdateBackupSchedule,
  type ForceRequiredOptions,
} from '@/hooks/useServices'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Switch } from '@/components/ui/switch'
import { IconButton } from '@/components/ui/icon-button'
import ConfirmDialog from '@/features/shared/ConfirmDialog'
import { api } from '@/lib/api'
import type { Backup, BackupDestination, BackupSchedule, RestoreDrill, Service, StorageMount } from '@/types'
import { DEFAULT_RETENTION, FREQUENCY_LABEL, MAX_RETENTION, artifactFilename, triggerLabel, formatDate, formatRelative, formatSize, toggleId } from './lib'

// ── Layout primitives ─────────────────────────────────────────────────────

export function SectionHeading({ title, description, action }: { title: string; description?: ReactNode; action?: ReactNode }) {
  return (
    <div className="mb-3 flex items-start justify-between gap-3">
      <div>
        <h3 className="text-[12px] font-medium text-white/70">{title}</h3>
        {description && <p className="mt-0.5 text-[11px] text-white/35">{description}</p>}
      </div>
      {action}
    </div>
  )
}

/**
 * A recovery endpoint may refuse to act until an irreversible consequence is
 * acknowledged (no safety snapshot, last remaining backup). This renders that
 * acknowledgement as an app dialog instead of `window.confirm()`.
 */
export function useForceDialog(): { options: ForceRequiredOptions; dialog: ReactNode } {
  const [pending, setPending] = useState<{ message: string; proceed: () => void } | null>(null)
  const options: ForceRequiredOptions = { onForceRequired: (message, proceed) => setPending({ message, proceed }) }
  const dialog = (
    <ConfirmDialog
      open={pending !== null}
      onOpenChange={(open) => { if (!open) setPending(null) }}
      title="Continue without a safety net?"
      description={pending?.message}
      warning="This cannot be undone. Nothing will be kept that could bring the current data back."
      confirmLabel="Continue anyway"
      destructive
      onConfirm={() => { pending?.proceed(); setPending(null) }}
    />
  )
  return { options, dialog }
}

// ── Destinations ──────────────────────────────────────────────────────────

export function DestinationChecklist({
  destinations,
  selected,
  onToggle,
  emptyHint = true,
}: {
  destinations: BackupDestination[]
  selected: string[]
  onToggle: (id: string) => void
  emptyHint?: boolean
}) {
  if (destinations.length === 0) {
    return emptyHint ? (
      <p className="text-[11px] text-white/35">
        Only a copy on this host.{' '}
        <Link to="/dashboard/settings?tab=backup-destinations" className="text-rail-purple-light hover:underline">
          Add an off-site destination
        </Link>{' '}
        so it survives a disk failure.
      </p>
    ) : null
  }

  return (
    <div className="flex flex-wrap gap-2">
      {destinations.map((destination) => {
        const verified = destination.status === 'verified'
        return (
          <label
            key={destination.id}
            title={verified ? undefined : 'This destination has not passed verification; uploads to it may fail.'}
            className="flex cursor-pointer items-center gap-1.5 rounded border border-white/[0.07] px-2 py-1 text-[11px] text-white/65 hover:bg-white/3"
          >
            <input
              type="checkbox"
              checked={selected.includes(destination.id)}
              onChange={() => onToggle(destination.id)}
              className="rounded border-white/20 bg-[#17171b]"
            />
            {destination.name}
            {!verified && <span className="text-[10px] text-amber-400">{destination.status}</span>}
          </label>
        )
      })}
    </div>
  )
}


function destinationNames(ids: string[], destinations: BackupDestination[]) {
  if (ids.length === 0) return 'this host only'
  return ids.map((id) => destinations.find((d) => d.id === id)?.name ?? 'removed destination').join(', ')
}

// ── Schedules ─────────────────────────────────────────────────────────────

export interface ScheduleDraft {
  frequency: string
  retentionCount: number
  destinationIds: string[]
  storageMountId?: string
}

/** Create/edit form shared by database and volume schedules. */
export function ScheduleForm({
  initial,
  destinations,
  mounts,
  pending,
  submitLabel,
  onSubmit,
  onCancel,
}: {
  initial: ScheduleDraft
  destinations: BackupDestination[]
  /** Present for volume schedules: the mount to snapshot. */
  mounts?: StorageMount[]
  pending?: boolean
  submitLabel: string
  onSubmit: (draft: ScheduleDraft) => void
  onCancel: () => void
}) {
  const [draft, setDraft] = useState<ScheduleDraft>(initial)
  // Once the operator picks a retention window by hand, changing the frequency
  // must not silently overwrite it.
  const [retentionTouched, setRetentionTouched] = useState(false)
  const retentionValid = Number.isInteger(draft.retentionCount) && draft.retentionCount >= 1 && draft.retentionCount <= MAX_RETENTION
  const mountValid = !mounts || Boolean(draft.storageMountId)

  return (
    <form
      className="mb-3 space-y-3 rounded-lg border border-white/[0.07] bg-white/2 p-3"
      onSubmit={(event) => {
        event.preventDefault()
        if (retentionValid && mountValid) onSubmit(draft)
      }}
    >
      {mounts && (
        <label className="block text-[11px] text-white/45">
          Volume
          <Select value={draft.storageMountId ?? ''} onValueChange={(value) => setDraft({ ...draft, storageMountId: value })}>
            <SelectTrigger className="mt-1 block w-full rounded-md border border-white/8 bg-[#17171b] px-2 py-1.5 text-[12px] text-white/70">
              <SelectValue placeholder="Choose a mounted path" />
            </SelectTrigger>
            <SelectContent>
              {mounts.map((mount) => (
                <SelectItem key={mount.id} value={mount.id}>{mount.containerPath}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </label>
      )}
      <div className="flex items-end gap-2">
        <label className="flex-1 text-[11px] text-white/45">
          Frequency
          <Select
            value={draft.frequency}
            onValueChange={(value) => setDraft({
              ...draft,
              frequency: value,
              retentionCount: retentionTouched ? draft.retentionCount : DEFAULT_RETENTION[value] ?? 7,
            })}
          >
            <SelectTrigger className="mt-1 block w-full rounded-md border border-white/8 bg-[#17171b] px-2 py-1.5 text-[12px] text-white/70">
              <SelectValue placeholder="Frequency" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="daily">Daily</SelectItem>
              <SelectItem value="weekly">Weekly</SelectItem>
              <SelectItem value="monthly">Monthly</SelectItem>
            </SelectContent>
          </Select>
        </label>
        <label className="w-28 text-[11px] text-white/45">
          Keep latest
          <input
            type="number"
            min={1}
            max={MAX_RETENTION}
            value={Number.isFinite(draft.retentionCount) ? draft.retentionCount : ''}
            aria-invalid={!retentionValid}
            onChange={(event) => {
              setRetentionTouched(true)
              setDraft({ ...draft, retentionCount: Number(event.target.value) })
            }}
            className="mt-1 block w-full rounded-md border border-white/8 bg-[#17171b] px-2 py-1.5 text-[12px] text-white/70 aria-invalid:border-red-400/50"
          />
        </label>
      </div>
      {!retentionValid && <p className="text-[11px] text-red-300">Keep between 1 and {MAX_RETENTION} copies.</p>}
      <div>
        <div className="mb-1 text-[11px] text-white/45">Send to</div>
        <DestinationChecklist
          destinations={destinations}
          selected={draft.destinationIds}
          onToggle={(id) => setDraft({ ...draft, destinationIds: toggleId(draft.destinationIds, id) })}
        />
      </div>
      <p className="text-[11px] text-white/30">
        Retention never removes the newest copy, or a safety snapshot taken before a delete or restore.
      </p>
      <div className="flex justify-end gap-2">
        <button type="button" onClick={onCancel} className="rounded-md px-3 py-1.5 text-[11px] text-white/50 hover:bg-white/5">
          Cancel
        </button>
        <button
          type="submit"
          disabled={pending || !retentionValid || !mountValid}
          className="inline-flex items-center gap-1.5 rounded-md bg-rail-purple px-3 py-1.5 text-[11px] font-medium text-white hover:bg-rail-purple-dark disabled:opacity-40"
        >
          {pending && <Loader2 size={12} className="animate-spin" />}
          {submitLabel}
        </button>
      </div>
    </form>
  )
}

export function ScheduleList({
  serviceId,
  schedules,
  destinations,
  emptyTitle,
  emptyHint,
}: {
  serviceId: string
  schedules: BackupSchedule[]
  destinations: BackupDestination[]
  emptyTitle: string
  emptyHint: string
}) {
  const updateSchedule = useUpdateBackupSchedule()
  const destroySchedule = useDestroyBackupSchedule()
  const [editingId, setEditingId] = useState<string | null>(null)
  const [deleting, setDeleting] = useState<BackupSchedule | null>(null)

  if (schedules.length === 0) {
    return (
      <div className="rounded-lg border border-dashed border-white/8 py-6 text-center">
        <Clock3 size={18} className="mx-auto mb-2 text-white/15" />
        <div className="text-[12px] text-white/50">{emptyTitle}</div>
        <div className="mt-1 text-[11px] text-white/30">{emptyHint}</div>
      </div>
    )
  }

  return (
    <>
      <div className="divide-y divide-white/5 rounded-lg border border-white/5">
        {schedules.map((schedule) => {
          const isVolume = schedule.backupKind === 'volume'
          return (
            <div key={schedule.id} className="px-3 py-2.5">
              <div className={`flex items-center gap-2 ${schedule.enabled ? '' : 'opacity-55'}`}>
                <Clock3 size={14} className={schedule.enabled ? 'text-rail-purple' : 'text-white/25'} />
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2 text-[12px] text-white/75">
                    <span className="font-medium">{FREQUENCY_LABEL[schedule.frequency] || schedule.frequency}</span>
                    {isVolume && schedule.storageMount?.containerPath && (
                      <span className="truncate font-mono text-[11px] text-white/45">{schedule.storageMount.containerPath}</span>
                    )}
                    <span className="text-white/40">keeps {schedule.retentionCount}</span>
                  </div>
                  <div className="mt-0.5 text-[11px] text-white/35">
                    {schedule.enabled ? `Next ${formatRelative(schedule.nextRunAt)}` : 'Paused'}
                    {' · '}
                    {schedule.lastRunAt ? `last ran ${formatRelative(schedule.lastRunAt)}` : 'never run'}
                    {' · '}
                    to {destinationNames(schedule.destinationIds ?? [], destinations)}
                  </div>
                </div>
                <Switch
                  checked={Boolean(schedule.enabled)}
                  aria-label={schedule.enabled ? 'Pause schedule' : 'Resume schedule'}
                  onCheckedChange={(checked) =>
                    updateSchedule.mutate({ id: serviceId, scheduleId: schedule.id, data: { enabled: checked } })
                  }
                />
                <IconButton title="Edit schedule" onClick={() => setEditingId(editingId === schedule.id ? null : schedule.id)}>
                  <Pencil />
                </IconButton>
                <IconButton title="Delete schedule" className="hover:bg-red-500/10 hover:text-red-400" onClick={() => setDeleting(schedule)}>
                  <Trash2 />
                </IconButton>
              </div>
              {editingId === schedule.id && (
                <div className="mt-2">
                  <ScheduleForm
                    initial={{
                      frequency: schedule.frequency,
                      retentionCount: schedule.retentionCount,
                      destinationIds: schedule.destinationIds ?? [],
                    }}
                    destinations={destinations}
                    pending={updateSchedule.isPending}
                    submitLabel="Save changes"
                    onCancel={() => setEditingId(null)}
                    onSubmit={(draft) =>
                      updateSchedule.mutate(
                        { id: serviceId, scheduleId: schedule.id, data: draft },
                        { onSuccess: () => setEditingId(null) },
                      )
                    }
                  />
                </div>
              )}
            </div>
          )
        })}
      </div>
      <ConfirmDialog
        open={deleting !== null}
        onOpenChange={(open) => { if (!open) setDeleting(null) }}
        title="Delete this schedule?"
        description="No more automatic copies will be made on this schedule. Copies it already made are kept until you delete them."
        confirmLabel="Delete schedule"
        destructive
        pending={destroySchedule.isPending}
        onConfirm={() => {
          if (!deleting) return
          destroySchedule.mutate({ id: serviceId, scheduleId: deleting.id }, { onSettled: () => setDeleting(null) })
        }}
      />
    </>
  )
}

// ── Artifacts ─────────────────────────────────────────────────────────────

function latestDrillFor(backupId: string, drills: RestoreDrill[]) {
  return drills.find((drill) => drill.backupId === backupId)
}

export function ArtifactList({
  svc,
  serviceId,
  backups,
  drills,
  isLoading,
  isError,
  refetch,
  emptyTitle,
  emptyHint,
  describe,
}: {
  svc: Service
  serviceId: string
  backups: Backup[]
  drills: RestoreDrill[]
  isLoading: boolean
  isError: boolean
  refetch: () => void
  emptyTitle: string
  emptyHint: string
  /** Short label for what the artifact covers (engine, mount path). */
  describe: (backup: Backup) => string
}) {
  const force = useForceDialog()
  const restoreBackup = useRestoreBackup(force.options)
  const deleteBackup = useDeleteBackup(force.options)
  const runDrill = useRunRestoreDrill()
  const [restoring, setRestoring] = useState<Backup | null>(null)
  const [deleting, setDeleting] = useState<Backup | null>(null)
  const [downloadError, setDownloadError] = useState<string | null>(null)

  const download = async (backup: Backup) => {
    setDownloadError(null)
    try {
      const blob = await api.services.downloadBackup(serviceId, backup.id)
      const url = URL.createObjectURL(blob)
      const anchor = document.createElement('a')
      anchor.href = url
      anchor.download = artifactFilename(svc, backup)
      anchor.click()
      URL.revokeObjectURL(url)
    } catch (error) {
      setDownloadError(error instanceof Error ? error.message : 'Download failed')
    }
  }

  if (isLoading) {
    return <div className="flex items-center justify-center gap-2 py-10 text-[12px] text-white/50"><Loader2 size={14} className="animate-spin" /> Loading…</div>
  }
  if (isError) {
    return (
      <button type="button" onClick={() => refetch()} className="flex w-full items-center justify-center gap-2 py-10 text-[12px] text-red-400">
        <AlertCircle size={14} /> Could not load the list · Retry
      </button>
    )
  }
  if (backups.length === 0) {
    return (
      <div className="rounded-lg border border-dashed border-white/8 py-10 text-center">
        <Archive size={20} className="mx-auto mb-2 text-white/15" />
        <div className="text-[12px] text-white/50">{emptyTitle}</div>
        <div className="mt-1 text-[11px] text-white/30">{emptyHint}</div>
      </div>
    )
  }

  return (
    <>
      {downloadError && (
        <div role="alert" className="mb-2 rounded-md border border-red-400/20 bg-red-400/5 px-3 py-2 text-[11px] text-red-300">{downloadError}</div>
      )}
      <div className="divide-y divide-white/5 rounded-lg border border-white/5">
        {backups.map((backup) => {
          const ready = backup.status === 'completed' && Boolean(backup.metadata?.verifiedAt)
          const failed = backup.status === 'failed'
          const restorable = ready && (backup.backupKind === 'database' || backup.backupKind === 'volume' || backup.backupKind === undefined)
          const testable = ready && backup.backupKind !== 'wal'
          const drill = latestDrillFor(backup.id, drills)
          const trigger = triggerLabel(backup)
          return (
            <article key={backup.id} className="flex items-center gap-3 px-3 py-2.5">
              {ready ? <FileCheck2 size={15} className="shrink-0 text-emerald-400" /> : failed ? <AlertCircle size={15} className="shrink-0 text-red-400" /> : <Loader2 size={15} className="shrink-0 animate-spin text-amber-400" />}
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-2 text-[12px] text-white/75">
                  <span>{formatDate(backup.createdAt)}</span>
                  <span className="text-white/40">{describe(backup)}</span>
                  {trigger && <span className="rounded bg-white/5 px-1.5 py-0.5 text-[10px] text-white/45">{trigger}</span>}
                  {!ready && !failed && <span className="text-[11px] text-amber-300">{backup.status === 'completed' ? 'verifying' : backup.status}</span>}
                  {drill?.status === 'succeeded' && <span className="rounded bg-emerald-500/10 px-1.5 py-0.5 text-[10px] text-emerald-300">restore tested</span>}
                  {drill?.status === 'failed' && <span title={drill.log} className="rounded bg-red-500/10 px-1.5 py-0.5 text-[10px] text-red-300">restore test failed</span>}
                  {(drill?.status === 'pending' || drill?.status === 'running') && <span className="text-[10px] text-white/40">testing restore…</span>}
                </div>
                <div className="mt-0.5 flex flex-wrap items-center gap-x-2 text-[11px] text-white/35">
                  <span>{formatSize(backup.size)}</span>
                  <span>· {backup.metadata?.destination || 'this host'}</span>
                  {backup.encrypted && <span>· encrypted</span>}
                  {backup.metadata?.checksum && <span className="font-mono">· sha256:{backup.metadata.checksum.slice(0, 10)}</span>}
                </div>
                {failed && backup.metadata?.error && (
                  <div className="mt-1 line-clamp-2 text-[11px] text-red-300/80" title={backup.metadata.error}>{backup.metadata.error}</div>
                )}
              </div>
              <div className="flex items-center">
                <IconButton title="Download" disabled={!ready} onClick={() => download(backup)}><Download /></IconButton>
                <IconButton
                  title="Test restore in an isolated copy"
                  disabled={!testable || runDrill.isPending}
                  className="hover:bg-emerald-500/10 hover:text-emerald-300"
                  onClick={() => runDrill.mutate({ id: serviceId, backupId: backup.id })}
                >
                  <FlaskConical />
                </IconButton>
                <IconButton
                  title={restorable || !ready ? 'Restore' : 'Physical base backups are restored through point-in-time recovery'}
                  disabled={!restorable}
                  className="hover:bg-amber-500/10 hover:text-amber-300"
                  onClick={() => setRestoring(backup)}
                >
                  <RotateCcw />
                </IconButton>
                <IconButton title="Delete" className="hover:bg-red-500/10 hover:text-red-400" onClick={() => setDeleting(backup)}>
                  <Trash2 />
                </IconButton>
              </div>
            </article>
          )
        })}
      </div>

      <ConfirmDialog
        open={restoring !== null}
        onOpenChange={(open) => { if (!open) setRestoring(null) }}
        title={`Restore ${restoring?.backupKind === 'volume' ? 'this snapshot' : 'this backup'}?`}
        description={
          restoring && (
            <>
              {restoring.backupKind === 'volume' ? 'The files in ' : 'The data in '}
              <span className="text-white/80">{describe(restoring)}</span> will be replaced with the copy from{' '}
              {formatDate(restoring.createdAt)}.
            </>
          )
        }
        warning="A safety snapshot of the current data is taken first, so this restore can itself be undone. Anything written after the copy was made is replaced."
        confirmWord={svc.name}
        confirmLabel="Restore"
        pending={restoreBackup.isPending}
        onConfirm={() => {
          if (!restoring) return
          restoreBackup.mutate({ id: serviceId, backupId: restoring.id, confirm: svc.name }, { onSettled: () => setRestoring(null) })
        }}
      />
      <ConfirmDialog
        open={deleting !== null}
        onOpenChange={(open) => { if (!open) setDeleting(null) }}
        title="Delete this copy?"
        description={deleting && <>The copy from {formatDate(deleting.createdAt)} is removed from this host and every destination.</>}
        confirmLabel="Delete"
        destructive
        pending={deleteBackup.isPending}
        onConfirm={() => {
          if (!deleting) return
          deleteBackup.mutate({ id: serviceId, backupId: deleting.id }, { onSettled: () => setDeleting(null) })
        }}
      />
      {force.dialog}
    </>
  )
}
