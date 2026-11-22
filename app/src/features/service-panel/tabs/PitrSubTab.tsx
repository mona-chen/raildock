import { useState } from 'react'
import { Link } from 'react-router-dom'
import { AlertCircle, Clock, Loader2, ShieldCheck, ShieldX } from 'lucide-react'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import ConfirmDialog from '@/features/shared/ConfirmDialog'
import { useRecovery, useConfigurePitr, useDisablePitr, useBackups, useRunRestoreDrill } from '@/hooks/useServices'
import type { Service, BackupDestination } from '@/types'
import { SectionHeading } from './recovery/shared'
import { formatDate, formatRelative, supportsPitr } from './recovery/lib'

const RETENTION_OPTIONS = [1, 3, 7, 14, 30, 90]

const STATUS_COPY: Record<string, { label: string; tone: string; Icon: typeof ShieldCheck }> = {
  active: { label: 'Archiving', tone: 'text-emerald-400', Icon: ShieldCheck },
  pending: { label: 'Waiting for the first base backup', tone: 'text-amber-300', Icon: Clock },
  paused: { label: 'Paused', tone: 'text-white/50', Icon: Clock },
  error: { label: 'Archiving needs attention', tone: 'text-red-400', Icon: AlertCircle },
}

export default function PitrSubTab({ svc, serviceId }: { svc: Service; serviceId: string }) {
  const { data: recovery, isLoading, isError, refetch } = useRecovery(serviceId)
  const { data: backups = [] } = useBackups(serviceId)
  const configurePitr = useConfigurePitr()
  const disablePitr = useDisablePitr()
  const runDrill = useRunRestoreDrill()
  const [destinationId, setDestinationId] = useState('')
  const [retentionDays, setRetentionDays] = useState(7)
  const [targetTime, setTargetTime] = useState('')
  const [confirmDisable, setConfirmDisable] = useState(false)

  if (!supportsPitr(svc)) {
    return <div className="py-16 text-center text-[13px] text-white/45">Point-in-time recovery is only available for PostgreSQL.</div>
  }
  if (isLoading) {
    return <div className="flex items-center justify-center gap-2 py-16 text-[12px] text-white/50"><Loader2 size={14} className="animate-spin" /> Loading…</div>
  }
  if (isError) {
    return (
      <button type="button" onClick={() => refetch()} className="flex w-full items-center justify-center gap-2 py-16 text-[12px] text-red-400">
        <AlertCircle size={14} /> Could not load recovery settings · Retry
      </button>
    )
  }

  const destinations: BackupDestination[] = recovery?.destinations ?? []
  // WAL is shipped every minute with nobody watching, so only a destination
  // that has proven it accepts writes can hold it (the API enforces this too).
  const verified = destinations.filter((destination) => destination.status === 'verified')
  const pitr = recovery?.pitr
  const enabled = Boolean(pitr?.enabled)
  const status = STATUS_COPY[pitr?.status ?? 'pending'] ?? STATUS_COPY.pending
  const currentDestination = destinations.find((destination) => destination.id === String(pitr?.backupDestinationId ?? ''))

  const bases = backups
    .filter((backup) => backup.backupKind === 'pitr_base' && backup.status === 'completed')
    .sort((a, b) => new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime())
  const earliest = bases[0]?.createdAt
  const target = targetTime ? new Date(targetTime) : null
  const targetValid = target === null || (Number.isFinite(target.getTime()) && target <= new Date() && (!earliest || target > new Date(earliest)))
  const base = [...bases].reverse().find((backup) => !target || new Date(backup.createdAt) < target)
  const pitrDrills = (recovery?.drills ?? []).filter((drill) => bases.some((backup) => backup.id === drill.backupId))
  const lastVerified = pitrDrills.find((drill) => drill.status === 'succeeded')

  const save = (nextDestination: string, nextRetention: number) =>
    configurePitr.mutate({ id: serviceId, destinationId: nextDestination, retentionDays: nextRetention })

  return (
    <div className="min-h-full bg-[#111114] px-5 py-4">
      <div className="mb-4">
        <h2 className="text-[14px] font-medium text-white/85">Point-in-time recovery</h2>
        <p className="mt-1 text-[12px] text-white/40">
          A daily physical base backup plus every WAL segment, shipped off-site each minute. Recover {svc.name} to any
          second inside the window, not just to the last nightly dump.
        </p>
      </div>

      {enabled && pitr ? (
        <div className="rounded-lg border border-white/[0.07] bg-white/2 p-4">
          <div className="flex items-start justify-between gap-4">
            <div className={`flex items-center gap-2 text-[13px] font-medium ${status.tone}`}>
              <status.Icon size={14} />
              {status.label}
            </div>
            <button type="button" onClick={() => setConfirmDisable(true)} className="text-[11px] text-white/45 hover:text-red-300">
              Turn off
            </button>
          </div>

          <dl className="mt-4 grid grid-cols-2 gap-x-6 gap-y-3 text-[12px] sm:grid-cols-4">
            <div>
              <dt className="text-[11px] text-white/35">Recoverable from</dt>
              <dd className="mt-0.5 text-white/75">{earliest ? formatDate(earliest) : 'After the first base backup'}</dd>
            </div>
            <div>
              <dt className="text-[11px] text-white/35">Last WAL shipped</dt>
              <dd className="mt-0.5 text-white/75">{pitr.lastWalArchivedAt ? formatRelative(pitr.lastWalArchivedAt) : 'Not yet'}</dd>
            </div>
            <div>
              <dt className="text-[11px] text-white/35">Last base backup</dt>
              <dd className="mt-0.5 text-white/75">{pitr.lastBaseBackupAt ? formatRelative(pitr.lastBaseBackupAt) : 'Not yet'}</dd>
            </div>
            <div>
              <dt className="text-[11px] text-white/35">Last recovery test</dt>
              <dd className="mt-0.5 text-white/75">{lastVerified?.completedAt ? formatRelative(lastVerified.completedAt) : 'Never'}</dd>
            </div>
          </dl>

          <div className="mt-4 flex flex-wrap items-end gap-3 border-t border-white/6 pt-4">
            <label className="text-[11px] text-white/45">
              Destination
              <Select value={currentDestination?.id ?? ''} onValueChange={(value) => save(value, pitr.retentionDays)} disabled={configurePitr.isPending}>
                <SelectTrigger className="mt-1 min-w-[180px] rounded-md border border-white/8 bg-[#17171b] px-2 py-1.5 text-[12px] text-white/70">
                  <SelectValue placeholder="Choose a destination" />
                </SelectTrigger>
                <SelectContent>
                  {verified.map((destination) => (
                    <SelectItem key={destination.id} value={destination.id}>{destination.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </label>
            <label className="text-[11px] text-white/45">
              Keep
              <Select
                value={String(pitr.retentionDays)}
                onValueChange={(value) => currentDestination && save(currentDestination.id, Number(value))}
                disabled={configurePitr.isPending || !currentDestination}
              >
                <SelectTrigger className="mt-1 min-w-[120px] rounded-md border border-white/8 bg-[#17171b] px-2 py-1.5 text-[12px] text-white/70">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {RETENTION_OPTIONS.map((days) => (
                    <SelectItem key={days} value={String(days)}>{days} day{days === 1 ? '' : 's'}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </label>
            {configurePitr.isPending && <Loader2 size={14} className="mb-2 animate-spin text-white/40" />}
          </div>

          {pitr.lastError && (
            <div role="alert" className="mt-4 rounded-md border border-red-400/20 bg-red-400/5 p-3 text-[11px] text-red-300">
              <div className="font-medium">Last error</div>
              <div className="mt-1 text-white/55">{pitr.lastError}</div>
            </div>
          )}
        </div>
      ) : (
        <div className="rounded-lg border border-white/[0.07] bg-white/2 p-4">
          <div className="flex items-center gap-2 text-[13px] font-medium text-white/70">
            <ShieldX size={14} className="text-white/35" />
            Off
          </div>
          {verified.length === 0 ? (
            <p className="mt-2 text-[12px] text-amber-300">
              {destinations.length === 0 ? 'Point-in-time recovery needs an off-site destination.' : 'None of your destinations has passed verification yet.'}{' '}
              <Link to="/dashboard/settings?tab=backup-destinations" className="underline hover:text-amber-200">
                {destinations.length === 0 ? 'Add one' : 'Verify one'}
              </Link>
            </p>
          ) : (
            <form
              className="mt-3 flex flex-wrap items-end gap-3"
              onSubmit={(event) => {
                event.preventDefault()
                if (destinationId) save(destinationId, retentionDays)
              }}
            >
              <label className="text-[11px] text-white/45">
                Destination
                <Select value={destinationId} onValueChange={setDestinationId}>
                  <SelectTrigger className="mt-1 min-w-[180px] rounded-md border border-white/8 bg-[#17171b] px-2 py-1.5 text-[12px] text-white/70">
                    <SelectValue placeholder="Choose a destination" />
                  </SelectTrigger>
                  <SelectContent>
                    {verified.map((destination) => (
                      <SelectItem key={destination.id} value={destination.id}>{destination.name}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </label>
              <label className="text-[11px] text-white/45">
                Keep
                <Select value={String(retentionDays)} onValueChange={(value) => setRetentionDays(Number(value))}>
                  <SelectTrigger className="mt-1 min-w-[120px] rounded-md border border-white/8 bg-[#17171b] px-2 py-1.5 text-[12px] text-white/70">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {RETENTION_OPTIONS.map((days) => (
                      <SelectItem key={days} value={String(days)}>{days} day{days === 1 ? '' : 's'}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </label>
              <button
                type="submit"
                disabled={!destinationId || configurePitr.isPending}
                className="inline-flex items-center gap-1.5 rounded-md bg-rail-purple px-3 py-1.5 text-[12px] font-medium text-white hover:bg-rail-purple-dark disabled:opacity-40"
              >
                {configurePitr.isPending && <Loader2 size={12} className="animate-spin" />}
                Turn on
              </button>
              <p className="w-full text-[11px] text-white/35">
                Turning this on enables WAL archiving, which restarts PostgreSQL once.
              </p>
            </form>
          )}
        </div>
      )}

      {enabled && (
        <section className="mt-4 rounded-lg border border-white/[0.07] p-4" aria-label="Test a point-in-time recovery">
          <SectionHeading
            title="Test a recovery"
            description="Starts a private PostgreSQL, replays WAL up to the moment you pick, checks it answers a query, then removes it. The live database is not touched."
          />
          <div className="flex flex-wrap items-end gap-3">
            <label className="text-[11px] text-white/45">
              Recover to (your local time, optional)
              <input
                type="datetime-local"
                value={targetTime}
                onChange={(event) => setTargetTime(event.target.value)}
                aria-invalid={!targetValid}
                className="mt-1 block rounded-md border border-white/8 bg-[#17171b] px-2 py-1.5 text-[12px] text-white/80 aria-invalid:border-red-400/50"
              />
            </label>
            <button
              type="button"
              disabled={!base || runDrill.isPending || !targetValid}
              onClick={() => base && runDrill.mutate({ id: serviceId, backupId: base.id, targetTime: target?.toISOString() })}
              className="inline-flex items-center gap-1.5 rounded-md border border-white/10 px-3 py-1.5 text-[12px] text-white/75 hover:bg-white/5 disabled:opacity-40"
            >
              {runDrill.isPending && <Loader2 size={12} className="animate-spin" />}
              Test recovery
            </button>
          </div>
          {!targetValid && <p className="mt-2 text-[11px] text-red-300">Pick a moment between {earliest ? formatDate(earliest) : 'the first base backup'} and now.</p>}
          {targetValid && !base && <p className="mt-2 text-[11px] text-amber-300">No base backup exists yet to recover from.</p>}
          {pitrDrills.length > 0 && (
            <ul className="mt-3 space-y-1.5">
              {pitrDrills.slice(0, 5).map((drill) => (
                <li key={drill.id} className="flex items-start gap-2 text-[11px]">
                  {drill.status === 'succeeded' ? <ShieldCheck size={12} className="mt-0.5 text-emerald-400" /> : drill.status === 'failed' ? <AlertCircle size={12} className="mt-0.5 text-red-400" /> : <Loader2 size={12} className="mt-0.5 animate-spin text-white/40" />}
                  <span className="text-white/60">
                    {drill.targetTime ? `To ${formatDate(drill.targetTime)}` : 'Latest'}
                    {' · '}
                    {drill.log || (drill.status === 'pending' ? 'Waiting for a backup worker' : drill.status)}
                  </span>
                </li>
              ))}
            </ul>
          )}
          <p className="mt-3 text-[11px] text-white/30">
            Recovering into the live database is not available from the dashboard yet; a tested recovery shows the data is there.
          </p>
        </section>
      )}

      <ConfirmDialog
        open={confirmDisable}
        onOpenChange={setConfirmDisable}
        title="Turn off point-in-time recovery?"
        description="WAL stops being shipped, so the recovery window stops moving forward. PostgreSQL restarts once to apply this. Base backups and WAL already stored are kept until retention expires them."
        confirmLabel="Turn off"
        destructive
        pending={disablePitr.isPending}
        onConfirm={() => disablePitr.mutate(serviceId, { onSettled: () => setConfirmDisable(false) })}
      />
    </div>
  )
}
