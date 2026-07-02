import { useMemo, useRef, useState } from 'react'
import {
  AlertCircle,
  Archive,
  Check,
  Clock3,
  Cloud,
  DatabaseBackup,
  Download,
  ExternalLink,
  FileCheck2,
  FlaskConical,
  Loader2,
  Plus,
  RotateCcw,
  ShieldCheck,
  Trash2,
  Upload,
} from 'lucide-react'
import {
  useBackups,
  useBackupSchedules,
  useBackupService,
  useCreateBackupSchedule,
  useDeleteBackup,
  useDestroyBackupSchedule,
  useRestoreBackup,
  useRestoreService,
  useConfigurePitr,
  useRecovery,
  useRunRestoreDrill,
  useSnapshotVolume,
} from '@/hooks/useServices'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { api } from '@/lib/api'
import type { Service, BackupDestination } from '@/types'

function formatSize(bytes = 0) {
  if (!bytes) return '—'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  const unit = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1)
  return `${(bytes / 1024 ** unit).toFixed(unit ? 1 : 0)} ${units[unit]}`
}

function formatDate(value?: string) {
  return value ? new Date(value).toLocaleString() : 'Not yet run'
}

function DestinationBadge({ name, kind }: { name: string; kind?: string }) {
  const color = kind === 'local' ? 'text-white/45' : kind === 'r2' ? 'text-orange-300' : 'text-emerald-300'
  return <span className={`rounded bg-white/[0.05] px-1.5 py-0.5 text-[9px] ${color}`}>{name}</span>
}

export default function BackupsTab({ svc, serviceId }: { svc: Service; serviceId: string }) {
  const { data: backups = [], isLoading, isError, refetch } = useBackups(serviceId)
  const { data: schedules = [] } = useBackupSchedules(serviceId)
  const { data: recovery } = useRecovery(serviceId)
  const createBackup = useBackupService()
  const createSchedule = useCreateBackupSchedule()
  const destroySchedule = useDestroyBackupSchedule()
  const restoreUpload = useRestoreService()
  const restoreBackup = useRestoreBackup()
  const deleteBackup = useDeleteBackup()
  const configurePitr = useConfigurePitr()
  const runDrill = useRunRestoreDrill()
  const snapshotVolume = useSnapshotVolume()
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [showSchedule, setShowSchedule] = useState(false)
  const [frequency, setFrequency] = useState('daily')
  const [retentionCount, setRetentionCount] = useState(7)
  const [scheduleDestinations, setScheduleDestinations] = useState<string[]>([])
  const [confirmRestore, setConfirmRestore] = useState<string | null>(null)
  const [showSnapshot, setShowSnapshot] = useState(false)
  const [snapshotMountId, setSnapshotMountId] = useState('')
  const [snapshotDestinations, setSnapshotDestinations] = useState<string[]>([])
  const [selectedDestinations, setSelectedDestinations] = useState<string[]>([])

  const destinations = recovery?.destinations || []
  const hasDestinations = destinations.length > 0

  const latestVerified = useMemo(
    () => backups.find((backup) => backup.status === 'completed' && backup.metadata?.verifiedAt),
    [backups],
  )
  const restoreTarget = backups.find((backup) => backup.id === confirmRestore)

  const toggleDestination = (id: string, current: string[], setter: (ids: string[]) => void) => {
    if (current.includes(id)) {
      setter(current.filter((item) => item !== id))
    } else {
      setter([...current, id])
    }
  }

  const destinationOptions = (includeLocal = true) => (
    <>
      {includeLocal && (
        <label className="flex items-center gap-2 rounded px-2 py-1.5 text-[11px] text-white/70 hover:bg-white/[0.05] cursor-pointer">
          <input
            type="checkbox"
            checked={false}
            disabled
            className="rounded border-white/20 bg-[#17171b]"
          />
          <span>Local encrypted host (always included)</span>
        </label>
      )}
      {destinations.map((destination: BackupDestination) => (
        <label
          key={destination.id}
          className="flex items-center gap-2 rounded px-2 py-1.5 text-[11px] text-white/70 hover:bg-white/[0.05] cursor-pointer"
        >
          <input
            type="checkbox"
            checked={selectedDestinations.includes(destination.id)}
            onChange={() => toggleDestination(destination.id, selectedDestinations, setSelectedDestinations)}
            className="rounded border-white/20 bg-[#17171b]"
          />
          <span>{destination.name}</span>
          <span className={`ml-auto text-[9px] ${destination.status === 'verified' ? 'text-emerald-400' : 'text-amber-400'}`}>
            {destination.status}
          </span>
        </label>
      ))}
    </>
  )

  const snapshotDestinationOptions = (
    <>
      <label className="flex items-center gap-2 rounded px-2 py-1.5 text-[11px] text-white/70 hover:bg-white/[0.05] cursor-pointer">
        <input
          type="checkbox"
          checked={false}
          disabled
          className="rounded border-white/20 bg-[#17171b]"
        />
        <span>Local encrypted host</span>
      </label>
      {destinations.map((destination: BackupDestination) => (
        <label
          key={destination.id}
          className="flex items-center gap-2 rounded px-2 py-1.5 text-[11px] text-white/70 hover:bg-white/[0.05] cursor-pointer"
        >
          <input
            type="checkbox"
            checked={snapshotDestinations.includes(destination.id)}
            onChange={() => toggleDestination(destination.id, snapshotDestinations, setSnapshotDestinations)}
            className="rounded border-white/20 bg-[#17171b]"
          />
          <span>{destination.name}</span>
        </label>
      ))}
    </>
  )

  const download = async (backupId: string) => {
    const blob = await api.services.downloadBackup(serviceId, backupId)
    const url = URL.createObjectURL(blob)
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = `${svc.name}-${backupId}.dump`
    anchor.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="min-h-full bg-[#111114]">
      <header className="border-b border-white/[0.06] px-5 py-4">
        <div className="flex items-start justify-between gap-4">
          <div>
            <div className="flex items-center gap-2 text-[14px] font-medium text-white/85">
              <DatabaseBackup size={15} className="text-[#8b5cf6]" />
              Recovery
            </div>
            <p className="mt-1 text-[12px] text-white/35">Verified database artifacts, retention, and restore history.</p>
          </div>
          <div className="flex items-center gap-2">
            <button type="button" onClick={() => fileInputRef.current?.click()} className="inline-flex items-center gap-1.5 rounded-md border border-white/[0.08] px-2.5 py-1.5 text-[11px] text-white/55 hover:bg-white/[0.05] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#8b5cf6]">
              <Upload size={12} /> Import
            </button>
            <input ref={fileInputRef} type="file" accept=".sql,.dump,.gz" className="hidden" onChange={(event) => {
              const file = event.target.files?.[0]
              if (file) restoreUpload.mutate({ id: serviceId, file })
              event.target.value = ''
            }} />

            <div className="relative group">
              <button type="button" className="inline-flex items-center gap-1.5 rounded-md border border-white/[0.08] bg-[#17171b] px-2.5 py-1.5 text-[11px] text-white/70 hover:bg-white/[0.05]">
                <Cloud size={12} />
                {selectedDestinations.length === 0 ? 'Local only' : `${selectedDestinations.length} destination${selectedDestinations.length === 1 ? '' : 's'}`}
              </button>
              <div className="absolute right-0 top-full z-20 mt-1 hidden w-56 rounded-md border border-white/[0.08] bg-[#17171b] p-1 shadow-xl group-hover:block group-focus-within:block">
                {destinationOptions()}
                <a
                  href="/dashboard/settings?tab=backup-destinations"
                  className="mt-1 flex items-center gap-1.5 border-t border-white/[0.06] px-2 py-1.5 text-[10px] text-[#a78bfa] hover:text-[#c4b5fd]"
                >
                  <ExternalLink size={10} />
                  Manage destinations
                </a>
              </div>
            </div>

            {svc.storageMounts.length > 0 && (
              <button
                type="button"
                onClick={() => {
                  setSnapshotMountId(svc.storageMounts[0]?.id || '')
                  setShowSnapshot(true)
                }}
                disabled={snapshotVolume.isPending}
                className="inline-flex items-center gap-1.5 rounded-md border border-white/[0.08] bg-[#17171b] px-3 py-1.5 text-[11px] text-white/70 hover:bg-white/[0.05] disabled:opacity-50"
              >
                {snapshotVolume.isPending ? <Loader2 size={12} className="animate-spin" /> : <DatabaseBackup size={12} />}
                Snapshot volume
              </button>
            )}
            <button type="button" onClick={() => createBackup.mutate({ id: serviceId, backupDestinationIds: selectedDestinations })} disabled={createBackup.isPending} className="inline-flex items-center gap-1.5 rounded-md bg-[#8b5cf6] px-3 py-1.5 text-[11px] font-medium text-white hover:bg-[#7c4fe0] disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#a78bfa]">
              {createBackup.isPending ? <Loader2 size={12} className="animate-spin" /> : <Plus size={12} />}
              Create backup
            </button>
          </div>
        </div>
      </header>

      {!hasDestinations && (
        <div className="mx-5 mt-4 rounded-lg border border-amber-400/20 bg-amber-400/[0.04] px-3 py-2 text-[11px] text-amber-300">
          No shared backup destinations configured.
          <a href="/dashboard/settings?tab=backup-destinations" className="ml-1 underline hover:text-amber-200">
            Add an S3 or R2 destination
          </a>
          {' '}so backups can survive disk failure.
        </div>
      )}

      <div className="grid grid-cols-3 border-b border-white/[0.06]">
        <div className="px-5 py-3">
          <div className="text-[10px] uppercase tracking-[0.14em] text-white/25">Latest recovery point</div>
          <div className="mt-1 text-[12px] text-white/70">{latestVerified ? formatDate(latestVerified.createdAt) : 'No verified backup'}</div>
        </div>
        <div className="border-x border-white/[0.06] px-5 py-3">
          <div className="text-[10px] uppercase tracking-[0.14em] text-white/25">Integrity</div>
          <div className="mt-1 flex items-center gap-1.5 text-[12px] text-white/70">
            <ShieldCheck size={13} className={latestVerified ? 'text-emerald-400' : 'text-white/20'} />
            {latestVerified ? 'SHA-256 verified' : 'Awaiting verification'}
          </div>
        </div>
        <div className="px-5 py-3">
          <div className="text-[10px] uppercase tracking-[0.14em] text-white/25">Retention policy</div>
          <div className="mt-1 text-[12px] text-white/70">{schedules[0] ? `Keep ${schedules[0].retentionCount} · ${schedules[0].frequency}` : 'Manual only'}</div>
        </div>
      </div>

      <section className="border-b border-white/[0.06] px-5 py-4">
        <div className="flex items-center justify-between">
          <div>
            <h3 className="flex items-center gap-2 text-[11px] font-medium uppercase tracking-[0.12em] text-white/35">
              <Cloud size={13} /> Off-site destinations
            </h3>
            <p className="mt-1 text-[10px] text-white/20">Shared across this organization. AES-256-GCM before upload.</p>
          </div>
          <a
            href="/dashboard/settings?tab=backup-destinations"
            className="text-[11px] text-[#a78bfa] hover:text-[#c4b5fd] flex items-center gap-1"
          >
            <ExternalLink size={10} />
            Manage
          </a>
        </div>
        <div className="mt-3 flex flex-wrap gap-2">
          {destinations.length === 0 ? (
            <span className="text-[10px] text-white/25">No destinations configured.</span>
          ) : (
            destinations.map((item: BackupDestination) => (
              <div key={item.id} className="rounded-md border border-white/[0.07] px-2.5 py-1.5 text-[10px] text-white/45">
                <span className={item.status === 'verified' ? 'text-emerald-400' : 'text-red-400'}>●</span>
                {' '}{item.name} · {item.bucket}
              </div>
            ))
          )}
        </div>
        {svc.subtype === 'postgres' && (
          <div className="mt-3 rounded-lg border border-white/[0.07] bg-white/[0.02] p-3">
            <div className="flex flex-col gap-3">
              <div>
                <div className="text-[11px] font-medium text-white/65">PostgreSQL point-in-time recovery</div>
                <div className="mt-1 text-[10px] text-white/25">Daily physical base backup + continuous WAL archiving</div>
              </div>
              {recovery?.pitr?.enabled ? (
                <div className="text-[10px] text-emerald-400">
                  <div>Active</div>
                  <div className="text-white/25">WAL {formatDate(recovery.pitr.lastWalArchivedAt)}</div>
                </div>
              ) : (
                <div className="flex justify-start sm:justify-end">
                  <Select
                    value=""
                    onValueChange={(value) => {
                      if (value) configurePitr.mutate({ id: serviceId, destinationId: value, retentionDays: 7 })
                    }}
                  >
                    <SelectTrigger className="w-full rounded-md border-0 bg-emerald-500/10 px-3 py-1.5 text-[10px] text-emerald-300 h-auto sm:w-auto sm:min-w-[160px]">
                      <SelectValue placeholder="Enable PITR" />
                    </SelectTrigger>
                    <SelectContent>
                      {destinations.map((destination: BackupDestination) => (
                        <SelectItem key={destination.id} value={destination.id}>{destination.name}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              )}
            </div>
          </div>
        )}
      </section>

      <section className="px-5 py-4">
        <div className="mb-2 flex items-center justify-between">
          <h3 className="text-[11px] font-medium uppercase tracking-[0.12em] text-white/35">Schedule</h3>
          <button type="button" onClick={() => setShowSchedule((value) => !value)} className="text-[11px] text-[#a78bfa] hover:text-[#c4b5fd]">{showSchedule ? 'Cancel' : 'Configure'}</button>
        </div>
        {showSchedule && (
          <form className="mb-3 rounded-lg border border-white/[0.07] bg-white/[0.02] p-3" onSubmit={(event) => {
            event.preventDefault()
            createSchedule.mutate(
              { id: serviceId, data: { frequency, retentionCount, destinationIds: scheduleDestinations } },
              { onSuccess: () => { setShowSchedule(false); setScheduleDestinations([]) } }
            )
          }}>
            <div className="flex items-end gap-2">
              <label className="flex-1 text-[10px] text-white/35">
                Frequency
                <Select value={frequency} onValueChange={(value) => setFrequency(value)}>
                  <SelectTrigger className="mt-1 block w-full rounded-md border border-white/[0.08] bg-[#17171b] px-2 py-1.5 text-[12px] text-white/70 focus:outline-none focus:ring-1 focus:ring-[#8b5cf6]">
                    <SelectValue placeholder="Frequency" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="daily">Daily</SelectItem>
                    <SelectItem value="weekly">Weekly</SelectItem>
                    <SelectItem value="monthly">Monthly</SelectItem>
                  </SelectContent>
                </Select>
              </label>
              <label className="w-28 text-[10px] text-white/35">
                Keep latest
                <input type="number" min={1} max={30} value={retentionCount} onChange={(event) => setRetentionCount(Number(event.target.value))} className="mt-1 block w-full rounded-md border border-white/[0.08] bg-[#17171b] px-2 py-1.5 text-[12px] text-white/70 focus:outline-none focus:ring-1 focus:ring-[#8b5cf6]" />
              </label>
              <button className="rounded-md bg-white/[0.08] px-3 py-1.5 text-[11px] text-white/70 hover:bg-white/[0.12]">Save</button>
            </div>
            {destinations.length > 0 && (
              <div className="mt-3">
                <div className="mb-1 text-[10px] text-white/35">Also send scheduled backups to</div>
                <div className="flex flex-wrap gap-2">
                  {destinations.map((destination: BackupDestination) => (
                    <label key={destination.id} className="flex items-center gap-1.5 rounded border border-white/[0.07] px-2 py-1 text-[10px] text-white/60 cursor-pointer hover:bg-white/[0.03]">
                      <input
                        type="checkbox"
                        checked={scheduleDestinations.includes(destination.id)}
                        onChange={() => toggleDestination(destination.id, scheduleDestinations, setScheduleDestinations)}
                        className="rounded border-white/20 bg-[#17171b]"
                      />
                      {destination.name}
                    </label>
                  ))}
                </div>
              </div>
            )}
          </form>
        )}
        {schedules.map((schedule) => (
          <div key={schedule.id} className="flex items-center gap-3 border-y border-white/[0.05] py-2.5 text-[12px]">
            <Clock3 size={13} className="text-white/25" />
            <span className="capitalize text-white/65">{schedule.frequency}</span>
            <span className="text-white/25">Next {formatDate(schedule.nextRunAt)}</span>
            <span className="ml-auto text-white/25">Keep {schedule.retentionCount}</span>
            <button type="button" aria-label="Delete schedule" onClick={() => destroySchedule.mutate({ id: serviceId, scheduleId: schedule.id })} className="rounded p-1 text-white/25 hover:bg-red-500/10 hover:text-red-400"><Trash2 size={12} /></button>
          </div>
        ))}
      </section>

      <section className="px-5 pb-5">
        <div className="mb-2 flex items-center justify-between">
          <h3 className="text-[11px] font-medium uppercase tracking-[0.12em] text-white/35">Artifacts</h3>
          <span className="text-[10px] text-white/20">{backups.length} total</span>
        </div>
        {isLoading ? <div className="py-10 text-center text-[12px] text-white/30">Loading recovery history…</div> : isError ? (
          <button onClick={() => refetch()} className="flex w-full items-center justify-center gap-2 py-10 text-[12px] text-red-400"><AlertCircle size={14} /> Could not load backups · Retry</button>
        ) : backups.length === 0 ? (
          <div className="border-y border-dashed border-white/[0.08] py-12 text-center">
            <Archive size={22} className="mx-auto mb-2 text-white/15" />
            <div className="text-[12px] text-white/45">No recovery points yet</div>
            <div className="mt-1 text-[11px] text-white/20">Create one before your next risky change.</div>
          </div>
        ) : (
          <div className="divide-y divide-white/[0.05] border-y border-white/[0.05]">
            {backups.map((backup) => {
              const ready = backup.status === 'completed' && Boolean(backup.metadata?.verifiedAt)
              const destinationNames = (backup.metadata?.destination || 'local').split(', ').filter(Boolean)
              return (
                <article key={backup.id} className="group grid grid-cols-[1fr_auto_auto] items-center gap-4 py-3">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      {ready ? <FileCheck2 size={14} className="text-emerald-400" /> : backup.status === 'failed' ? <AlertCircle size={14} className="text-red-400" /> : <Loader2 size={14} className="animate-spin text-amber-400" />}
                      <span className="font-mono text-[11px] text-white/65">{String(backup.id).slice(0, 8)}</span>
                      <span className={`rounded px-1.5 py-0.5 text-[9px] uppercase tracking-wider ${ready ? 'bg-emerald-500/10 text-emerald-400' : backup.status === 'failed' ? 'bg-red-500/10 text-red-400' : 'bg-amber-500/10 text-amber-300'}`}>{ready ? 'verified' : backup.status}</span>
                      <span className="rounded bg-white/[0.05] px-1.5 py-0.5 text-[9px] text-white/35 capitalize">{backup.backupKind === 'volume' ? 'volume' : backup.backupKind}</span>
                    </div>
                    <div className="mt-1 flex flex-wrap items-center gap-2 pl-[22px] text-[10px] text-white/25">
                      <span>{formatDate(backup.createdAt)}</span>
                      <span>·</span>
                      <span>{formatSize(backup.size)}</span>
                      {backup.metadata?.checksum && <><span>·</span><span className="font-mono">sha256:{backup.metadata.checksum.slice(0, 10)}</span></>}
                      {backup.encrypted && <><span>·</span><span className="text-emerald-400/70">encrypted</span></>}
                      {destinationNames.length > 0 && (
                        <>
                          <span>·</span>
                          <span className="flex flex-wrap gap-1">
                            {destinationNames.map((name) => (
                              <DestinationBadge key={name} name={name} kind={name === 'local' ? 'local' : 's3'} />
                            ))}
                          </span>
                        </>
                      )}
                    </div>
                  </div>
                  <div className="text-[10px] text-white/20">{backup.metadata?.destination || 'local'}</div>
                  <div className="flex items-center gap-1">
                    <button type="button" disabled={!ready} onClick={() => download(backup.id)} aria-label="Download backup" className="rounded p-1.5 text-white/30 hover:bg-white/[0.06] hover:text-white/70 disabled:opacity-20"><Download size={13} /></button>
                    <button type="button" disabled={!ready} onClick={() => setConfirmRestore(backup.id)} aria-label="Restore backup" className="rounded p-1.5 text-white/30 hover:bg-amber-500/10 hover:text-amber-300 disabled:opacity-20"><RotateCcw size={13} /></button>
                    <button type="button" disabled={!ready || backup.backupKind === 'wal'} onClick={() => runDrill.mutate({ id: serviceId, backupId: backup.id })} aria-label="Run isolated restore drill" className="rounded p-1.5 text-white/30 hover:bg-emerald-500/10 hover:text-emerald-300 disabled:opacity-20"><FlaskConical size={13} /></button>
                    <button type="button" onClick={() => deleteBackup.mutate({ id: serviceId, backupId: backup.id })} aria-label="Delete backup" className="rounded p-1.5 text-white/20 hover:bg-red-500/10 hover:text-red-400"><Trash2 size={13} /></button>
                  </div>
                </article>
              )
            })}
          </div>
        )}
      </section>

      {confirmRestore && (
        <div className="fixed inset-0 z-[90] flex items-center justify-center bg-black/70 p-4" role="dialog" aria-modal="true" aria-labelledby="restore-title">
          <div className="w-full max-w-sm rounded-xl border border-white/[0.09] bg-[#19191d] p-5 shadow-2xl">
            <div className="flex items-center gap-2 text-amber-300"><RotateCcw size={16} /><h3 id="restore-title" className="text-[14px] font-medium">Restore this recovery point?</h3></div>
            {restoreTarget && (
              <div className="mt-3 space-y-1.5 rounded-lg border border-white/[0.06] bg-white/[0.02] p-3 text-[11px]">
                <div className="flex justify-between"><span className="text-white/30">Type</span><span className="text-white/65 capitalize">{restoreTarget.backupKind === 'volume' ? 'Volume snapshot' : restoreTarget.backupKind}</span></div>
                <div className="flex justify-between"><span className="text-white/30">Created</span><span className="text-white/65">{formatDate(restoreTarget.createdAt)}</span></div>
                <div className="flex justify-between"><span className="text-white/30">Size</span><span className="text-white/65">{formatSize(restoreTarget.size)}</span></div>
                {restoreTarget.metadata?.checksum && <div className="flex justify-between"><span className="text-white/30">Checksum</span><span className="font-mono text-white/65">sha256:{restoreTarget.metadata.checksum.slice(0, 10)}…</span></div>}
              </div>
            )}
            <p className="mt-3 text-[12px] leading-5 text-white/40">
              Current {restoreTarget?.backupKind === 'volume' ? 'volume files' : 'database contents'} will be replaced.
              This operation cannot be undone. Create a fresh backup first if you may need to reverse it.
            </p>
            <div className="mt-5 flex justify-end gap-2">
              <button onClick={() => setConfirmRestore(null)} className="rounded-md px-3 py-1.5 text-[11px] text-white/45 hover:bg-white/[0.05]">Cancel</button>
              <button onClick={() => restoreBackup.mutate({ id: serviceId, backupId: confirmRestore }, { onSuccess: () => setConfirmRestore(null) })} className="inline-flex items-center gap-1.5 rounded-md bg-amber-500/15 px-3 py-1.5 text-[11px] text-amber-300 hover:bg-amber-500/25"><Check size={12} /> Restore</button>
            </div>
          </div>
        </div>
      )}

      {showSnapshot && (
        <div className="fixed inset-0 z-[90] flex items-center justify-center bg-black/70 p-4" role="dialog" aria-modal="true">
          <div className="w-full max-w-sm rounded-xl border border-white/[0.09] bg-[#19191d] p-5 shadow-2xl">
            <div className="flex items-center gap-2 text-emerald-300"><DatabaseBackup size={16} /><h3 className="text-[14px] font-medium">Snapshot volume</h3></div>
            <p className="mt-3 text-[12px] leading-5 text-white/40">Create an encrypted point-in-time snapshot of a mounted volume.</p>
            <div className="mt-4 space-y-3">
              <label className="text-[10px] text-white/35">Mount
                <Select value={snapshotMountId} onValueChange={(value) => setSnapshotMountId(value)}>
                  <SelectTrigger className="mt-1 block w-full rounded-md border border-white/[0.08] bg-[#17171b] px-2 py-1.5 text-[11px] text-white/70">
                    <SelectValue placeholder="Select mount" />
                  </SelectTrigger>
                  <SelectContent>
                    {svc.storageMounts.map((mount) => (
                      <SelectItem key={mount.id} value={mount.id}>{mount.containerPath} ({mount.hostPath})</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </label>
              {destinations.length > 0 && (
                <div>
                  <div className="text-[10px] text-white/35 mb-1">Also send to</div>
                  <div className="space-y-1 rounded-md border border-white/[0.07] bg-[#17171b] p-1.5">
                    {snapshotDestinationOptions}
                  </div>
                </div>
              )}
            </div>
            <div className="mt-5 flex justify-end gap-2">
              <button onClick={() => setShowSnapshot(false)} className="rounded-md px-3 py-1.5 text-[11px] text-white/45 hover:bg-white/[0.05]">Cancel</button>
              <button
                disabled={!snapshotMountId || snapshotVolume.isPending}
                onClick={() =>
                  snapshotVolume.mutate(
                    { id: serviceId, storageMountId: snapshotMountId, backupDestinationIds: snapshotDestinations },
                    { onSuccess: () => setShowSnapshot(false) }
                  )
                }
                className="inline-flex items-center gap-1.5 rounded-md bg-emerald-500/15 px-3 py-1.5 text-[11px] text-emerald-300 hover:bg-emerald-500/25 disabled:opacity-30"
              >
                {snapshotVolume.isPending ? <Loader2 size={12} className="animate-spin" /> : <Check size={12} />}
                Snapshot
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
