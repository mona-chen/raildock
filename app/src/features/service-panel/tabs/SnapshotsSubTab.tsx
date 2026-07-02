import { useState } from 'react'
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
  Loader2,
  Plus,
  RotateCcw,
  Trash2,
} from 'lucide-react'
import {
  useVolumeSnapshots,
  useRecovery,
  useBackupSchedules,
  useSnapshotVolume,
  useCreateSnapshotSchedule,
  useDestroyBackupSchedule,
  useRestoreBackup,
  useDeleteBackup,
} from '@/hooks/useServices'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { api } from '@/lib/api'
import type { Service, BackupDestination, BackupSchedule, Backup } from '@/types'

function formatSize(bytes = 0) {
  if (!bytes) return '—'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  const unit = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1)
  return `${(bytes / 1024 ** unit).toFixed(unit ? 1 : 0)} ${units[unit]}`
}

function formatDate(value?: string) {
  return value ? new Date(value).toLocaleString() : 'Not yet run'
}

export default function SnapshotsSubTab({ svc, serviceId }: { svc: Service; serviceId: string }) {
  const { data: snapshots = [], isLoading, isError, refetch } = useVolumeSnapshots(serviceId)
  const { data: schedules = [] } = useBackupSchedules(serviceId)
  const { data: recovery } = useRecovery(serviceId)
  const snapshotVolume = useSnapshotVolume()
  const createSchedule = useCreateSnapshotSchedule()
  const destroySchedule = useDestroyBackupSchedule()
  const restoreBackup = useRestoreBackup()
  const deleteBackup = useDeleteBackup()

  const destinations = recovery?.destinations || []
  const [showSchedule, setShowSchedule] = useState(false)
  const [frequency, setFrequency] = useState('daily')
  const [retentionCount, setRetentionCount] = useState(3)
  const [snapshotMountId, setSnapshotMountId] = useState('')
  const [scheduleDestinations, setScheduleDestinations] = useState<string[]>([])
  const [confirmRestore, setConfirmRestore] = useState<string | null>(null)

  const restoreTarget = snapshots.find((backup) => backup.id === confirmRestore)
  const volumeSchedules = schedules.filter((s: BackupSchedule) => s.backupKind === 'volume')

  const toggleDestination = (id: string, current: string[], setter: (ids: string[]) => void) => {
    if (current.includes(id)) {
      setter(current.filter((item) => item !== id))
    } else {
      setter([...current, id])
    }
  }

  const download = async (backupId: string) => {
    const blob = await api.services.downloadBackup(serviceId, backupId)
    const url = URL.createObjectURL(blob)
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = `${svc.name}-${backupId}-volume.tar.gz`
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
              Volume snapshots
            </div>
            <p className="mt-1 text-[12px] text-white/35">Encrypted point-in-time copies of mounted volumes.</p>
          </div>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => {
                setSnapshotMountId(svc.storageMounts[0]?.id || '')
                setShowSchedule(true)
              }}
              disabled={snapshotVolume.isPending || svc.storageMounts.length === 0}
              className="inline-flex items-center gap-1.5 rounded-md border border-white/[0.08] bg-[#17171b] px-3 py-1.5 text-[11px] text-white/70 hover:bg-white/[0.05] disabled:opacity-50"
            >
              {snapshotVolume.isPending ? <Loader2 size={12} className="animate-spin" /> : <Plus size={12} />}
              Schedule snapshot
            </button>
            <button
              type="button"
              onClick={() => {
                setSnapshotMountId(svc.storageMounts[0]?.id || '')
                snapshotVolume.mutate({ id: serviceId, storageMountId: svc.storageMounts[0]?.id || '' })
              }}
              disabled={snapshotVolume.isPending || svc.storageMounts.length === 0}
              className="inline-flex items-center gap-1.5 rounded-md bg-[#8b5cf6] px-3 py-1.5 text-[11px] font-medium text-white hover:bg-[#7c4fe0] disabled:opacity-50"
            >
              {snapshotVolume.isPending ? <Loader2 size={12} className="animate-spin" /> : <DatabaseBackup size={12} />}
              Snapshot now
            </button>
          </div>
        </div>
      </header>

      {svc.storageMounts.length === 0 && (
        <div className="mx-5 mt-4 rounded-lg border border-amber-400/20 bg-amber-400/[0.04] px-3 py-2 text-[11px] text-amber-300">
          No storage mounts configured.
          <a href={`/dashboard/projects/${svc.projectId}?service=${svc.id}&tab=storage`} className="ml-1 underline hover:text-amber-200">
            Add a volume mount
          </a>
          {' '}before scheduling snapshots.
        </div>
      )}

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
      </section>

      <section className="border-b border-white/[0.06] px-5 py-4">
        <div className="mb-2 flex items-center justify-between">
          <h3 className="text-[11px] font-medium uppercase tracking-[0.12em] text-white/35">Snapshot schedules</h3>
          <span className="text-[10px] text-white/20">{volumeSchedules.length} total</span>
        </div>
        {volumeSchedules.length === 0 ? (
          <div className="border-y border-dashed border-white/[0.08] py-8 text-center">
            <Clock3 size={20} className="mx-auto mb-2 text-white/15" />
            <div className="text-[12px] text-white/45">No scheduled snapshots</div>
            <div className="mt-1 text-[11px] text-white/20">Pick a mount and frequency to automate volume backups.</div>
          </div>
        ) : (
          <div className="divide-y divide-white/[0.05] border-y border-white/[0.05]">
            {volumeSchedules.map((schedule) => (
              <div key={schedule.id} className="flex items-center gap-3 py-2.5 text-[12px]">
                <Clock3 size={13} className="text-white/25" />
                <span className="capitalize text-white/65">{schedule.frequency}</span>
                <span className="text-white/35">{schedule.storageMount?.containerPath || schedule.storageMountId}</span>
                <span className="text-white/25">Next {formatDate(schedule.nextRunAt)}</span>
                <span className="ml-auto text-white/25">Keep {schedule.retentionCount}</span>
                <button type="button" aria-label="Delete schedule" onClick={() => destroySchedule.mutate({ id: serviceId, scheduleId: schedule.id })} className="rounded p-1 text-white/25 hover:bg-red-500/10 hover:text-red-400"><Trash2 size={12} /></button>
              </div>
            ))}
          </div>
        )}
      </section>

      <section className="px-5 pb-5 pt-4">
        <div className="mb-2 flex items-center justify-between">
          <h3 className="text-[11px] font-medium uppercase tracking-[0.12em] text-white/35">Snapshots</h3>
          <span className="text-[10px] text-white/20">{snapshots.length} total</span>
        </div>
        {isLoading ? <div className="py-10 text-center text-[12px] text-white/30">Loading snapshots…</div> : isError ? (
          <button onClick={() => refetch()} className="flex w-full items-center justify-center gap-2 py-10 text-[12px] text-red-400"><AlertCircle size={14} /> Could not load snapshots · Retry</button>
        ) : snapshots.length === 0 ? (
          <div className="border-y border-dashed border-white/[0.08] py-12 text-center">
            <Archive size={22} className="mx-auto mb-2 text-white/15" />
            <div className="text-[12px] text-white/45">No snapshots yet</div>
            <div className="mt-1 text-[11px] text-white/20">Create one before your next risky change.</div>
          </div>
        ) : (
          <div className="divide-y divide-white/[0.05] border-y border-white/[0.05]">
            {snapshots.map((backup: Backup) => {
              const ready = backup.status === 'completed' && Boolean(backup.metadata?.verifiedAt)
              return (
                <article key={backup.id} className="group grid grid-cols-[1fr_auto_auto] items-center gap-4 py-3">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      {ready ? <FileCheck2 size={14} className="text-emerald-400" /> : backup.status === 'failed' ? <AlertCircle size={14} className="text-red-400" /> : <Loader2 size={14} className="animate-spin text-amber-400" />}
                      <span className="font-mono text-[11px] text-white/65">{String(backup.id).slice(0, 8)}</span>
                      <span className={`rounded px-1.5 py-0.5 text-[9px] uppercase tracking-wider ${ready ? 'bg-emerald-500/10 text-emerald-400' : backup.status === 'failed' ? 'bg-red-500/10 text-red-400' : 'bg-amber-500/10 text-amber-300'}`}>{ready ? 'verified' : backup.status}</span>
                      <span className="text-[10px] text-white/35">{backup.metadata?.containerPath || backup.metadata?.hostPath || 'volume'}</span>
                    </div>
                    <div className="mt-1 flex flex-wrap items-center gap-2 pl-[22px] text-[10px] text-white/25">
                      <span>{formatDate(backup.createdAt)}</span>
                      <span>·</span>
                      <span>{formatSize(backup.size)}</span>
                      {backup.metadata?.checksum && <><span>·</span><span className="font-mono">sha256:{backup.metadata.checksum.slice(0, 10)}</span></>}
                      {backup.encrypted && <><span>·</span><span className="text-emerald-400/70">encrypted</span></>}
                    </div>
                  </div>
                  <div className="text-[10px] text-white/20">{backup.metadata?.destination || 'local'}</div>
                  <div className="flex items-center gap-1">
                    <button type="button" disabled={!ready} onClick={() => download(backup.id)} aria-label="Download snapshot" className="rounded p-1.5 text-white/30 hover:bg-white/[0.06] hover:text-white/70 disabled:opacity-20"><Download size={13} /></button>
                    <button type="button" disabled={!ready} onClick={() => setConfirmRestore(backup.id)} aria-label="Restore snapshot" className="rounded p-1.5 text-white/30 hover:bg-amber-500/10 hover:text-amber-300 disabled:opacity-20"><RotateCcw size={13} /></button>
                    <button type="button" onClick={() => deleteBackup.mutate({ id: serviceId, backupId: backup.id })} aria-label="Delete snapshot" className="rounded p-1.5 text-white/20 hover:bg-red-500/10 hover:text-red-400"><Trash2 size={13} /></button>
                  </div>
                </article>
              )
            })}
          </div>
        )}
      </section>

      {showSchedule && (
        <div className="fixed inset-0 z-[90] flex items-center justify-center bg-black/70 p-4" role="dialog" aria-modal="true">
          <div className="w-full max-w-sm rounded-xl border border-white/[0.09] bg-[#19191d] p-5 shadow-2xl">
            <div className="flex items-center gap-2 text-emerald-300"><Clock3 size={16} /><h3 className="text-[14px] font-medium">Schedule volume snapshot</h3></div>
            <p className="mt-3 text-[12px] leading-5 text-white/40">Create an encrypted snapshot of a mounted volume on a recurring schedule.</p>
            <form className="mt-4 space-y-3" onSubmit={(event) => {
              event.preventDefault()
              createSchedule.mutate(
                { id: serviceId, data: { frequency, retentionCount, storageMountId: snapshotMountId, destinationIds: scheduleDestinations } },
                { onSuccess: () => { setShowSchedule(false); setScheduleDestinations([]) } }
              )
            }}>
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
              <div className="flex items-end gap-2">
                <label className="flex-1 text-[10px] text-white/35">
                  Frequency
                  <Select value={frequency} onValueChange={(value) => setFrequency(value)}>
                    <SelectTrigger className="mt-1 block w-full rounded-md border border-white/[0.08] bg-[#17171b] px-2 py-1.5 text-[12px] text-white/70">
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
                  <input type="number" min={1} max={30} value={retentionCount} onChange={(event) => setRetentionCount(Number(event.target.value))} className="mt-1 block w-full rounded-md border border-white/[0.08] bg-[#17171b] px-2 py-1.5 text-[12px] text-white/70" />
                </label>
              </div>
              {destinations.length > 0 && (
                <div>
                  <div className="text-[10px] text-white/35 mb-1">Also send to</div>
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
              <div className="mt-5 flex justify-end gap-2">
                <button type="button" onClick={() => setShowSchedule(false)} className="rounded-md px-3 py-1.5 text-[11px] text-white/45 hover:bg-white/[0.05]">Cancel</button>
                <button
                  type="submit"
                  disabled={!snapshotMountId || createSchedule.isPending}
                  className="inline-flex items-center gap-1.5 rounded-md bg-emerald-500/15 px-3 py-1.5 text-[11px] text-emerald-300 hover:bg-emerald-500/25 disabled:opacity-30"
                >
                  {createSchedule.isPending ? <Loader2 size={12} className="animate-spin" /> : <Check size={12} />}
                  Save schedule
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {confirmRestore && (
        <div className="fixed inset-0 z-[90] flex items-center justify-center bg-black/70 p-4" role="dialog" aria-modal="true" aria-labelledby="snapshot-restore-title">
          <div className="w-full max-w-sm rounded-xl border border-white/[0.09] bg-[#19191d] p-5 shadow-2xl">
            <div className="flex items-center gap-2 text-amber-300"><RotateCcw size={16} /><h3 id="snapshot-restore-title" className="text-[14px] font-medium">Restore this snapshot?</h3></div>
            {restoreTarget && (
              <div className="mt-3 space-y-1.5 rounded-lg border border-white/[0.06] bg-white/[0.02] p-3 text-[11px]">
                <div className="flex justify-between"><span className="text-white/30">Mount</span><span className="text-white/65">{restoreTarget.metadata?.containerPath || restoreTarget.metadata?.hostPath || 'volume'}</span></div>
                <div className="flex justify-between"><span className="text-white/30">Created</span><span className="text-white/65">{formatDate(restoreTarget.createdAt)}</span></div>
                <div className="flex justify-between"><span className="text-white/30">Size</span><span className="text-white/65">{formatSize(restoreTarget.size)}</span></div>
              </div>
            )}
            <p className="mt-3 text-[12px] leading-5 text-white/40">
              Current volume files will be replaced. This operation cannot be undone.
            </p>
            <div className="mt-5 flex justify-end gap-2">
              <button onClick={() => setConfirmRestore(null)} className="rounded-md px-3 py-1.5 text-[11px] text-white/45 hover:bg-white/[0.05]">Cancel</button>
              <button onClick={() => restoreBackup.mutate({ id: serviceId, backupId: confirmRestore }, { onSuccess: () => setConfirmRestore(null) })} className="inline-flex items-center gap-1.5 rounded-md bg-amber-500/15 px-3 py-1.5 text-[11px] text-amber-300 hover:bg-amber-500/25"><Check size={12} /> Restore</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
