import { useMemo, useRef, useState } from 'react'
import {
  AlertCircle,
  Archive,
  Check,
  Clock3,
  Cloud,
  DatabaseBackup,
  Download,
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
  useCreateBackupDestination,
  useRecovery,
  useRunRestoreDrill,
} from '@/hooks/useServices'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { api } from '@/lib/api'
import type { Service } from '@/types'

function formatSize(bytes = 0) {
  if (!bytes) return '—'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  const unit = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1)
  return `${(bytes / 1024 ** unit).toFixed(unit ? 1 : 0)} ${units[unit]}`
}

function formatDate(value?: string) {
  return value ? new Date(value).toLocaleString() : 'Not yet run'
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
  const createDestination = useCreateBackupDestination()
  const configurePitr = useConfigurePitr()
  const runDrill = useRunRestoreDrill()
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [showSchedule, setShowSchedule] = useState(false)
  const [frequency, setFrequency] = useState('daily')
  const [retentionCount, setRetentionCount] = useState(7)
  const [confirmRestore, setConfirmRestore] = useState<string | null>(null)
  const [showDestination, setShowDestination] = useState(false)
  const [selectedDestination, setSelectedDestination] = useState('')
  const [destination, setDestination] = useState({ name: '', provider: 's3', endpoint: '', region: 'us-east-1', bucket: '', path_prefix: 'raildock', access_key_id: '', secret_access_key: '' })
  const [recoveryKey, setRecoveryKey] = useState('')

  const latestVerified = useMemo(
    () => backups.find((backup) => backup.status === 'completed' && backup.metadata?.verifiedAt),
    [backups],
  )
  const restoreTarget = backups.find((backup) => backup.id === confirmRestore)

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
            <Select value={selectedDestination || 'local'} onValueChange={(value) => setSelectedDestination(value === 'local' ? '' : value)}>
              <SelectTrigger aria-label="Backup destination" className="rounded-md border border-white/[0.08] bg-[#17171b] px-2 py-1.5 text-[11px] text-white/55">
                <SelectValue placeholder="Local encrypted host" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="local">Local encrypted host</SelectItem>
                {recovery?.destinations.map((item) => <SelectItem key={item.id} value={item.id}>{item.name}</SelectItem>)}
              </SelectContent>
            </Select>
            <button type="button" onClick={() => createBackup.mutate({ id: serviceId, backupDestinationId: selectedDestination || undefined })} disabled={createBackup.isPending} className="inline-flex items-center gap-1.5 rounded-md bg-[#8b5cf6] px-3 py-1.5 text-[11px] font-medium text-white hover:bg-[#7c4fe0] disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#a78bfa]">
              {createBackup.isPending ? <Loader2 size={12} className="animate-spin" /> : <Plus size={12} />}
              Create backup
            </button>
          </div>
        </div>
      </header>

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
          <div><h3 className="flex items-center gap-2 text-[11px] font-medium uppercase tracking-[0.12em] text-white/35"><Cloud size={13} /> Off-site destinations</h3><p className="mt-1 text-[10px] text-white/20">S3 and R2 compatible · AES-256-GCM before upload</p></div>
          <button type="button" onClick={() => setShowDestination((value) => !value)} className="text-[11px] text-[#a78bfa]">{showDestination ? 'Cancel' : 'Add destination'}</button>
        </div>
        {showDestination && <form className="mt-3 grid grid-cols-2 gap-2 rounded-lg border border-white/[0.07] bg-white/[0.02] p-3" onSubmit={(event) => { event.preventDefault(); createDestination.mutate({ id: serviceId, data: destination }, { onSuccess: (item) => { setSelectedDestination(item.id); setRecoveryKey(item.recoveryKey || ''); setShowDestination(false) } }) }}>
          {(['name', 'bucket', 'region', 'endpoint', 'access_key_id', 'secret_access_key'] as const).map((key) => <label key={key} className="text-[10px] capitalize text-white/35">{key.replaceAll('_', ' ')}<input required={!['endpoint'].includes(key)} type={key.includes('secret') ? 'password' : 'text'} value={destination[key]} onChange={(event) => setDestination({ ...destination, [key]: event.target.value })} className="mt-1 block w-full rounded-md border border-white/[0.08] bg-[#17171b] px-2 py-1.5 text-[11px] text-white/70" /></label>)}
          <label className="text-[10px] text-white/35">Provider<Select value={destination.provider} onValueChange={(value) => setDestination({ ...destination, provider: value })}><SelectTrigger className="mt-1 block w-full rounded-md border border-white/[0.08] bg-[#17171b] px-2 py-1.5 text-[11px] text-white/70"><SelectValue placeholder="Select provider" /></SelectTrigger><SelectContent><SelectItem value="s3">Amazon S3</SelectItem><SelectItem value="r2">Cloudflare R2</SelectItem></SelectContent></Select></label>
          <button disabled={createDestination.isPending} className="self-end rounded-md bg-[#8b5cf6] px-3 py-2 text-[11px] text-white">Verify & save</button>
        </form>}
        {recoveryKey && <div className="mt-3 rounded-lg border border-amber-400/20 bg-amber-400/[0.04] p-3"><div className="text-[10px] font-medium text-amber-300">Save this recovery key now — it is shown once.</div><code className="mt-2 block break-all select-all text-[10px] text-white/55">{recoveryKey}</code></div>}
        <div className="mt-3 flex flex-wrap gap-2">{recovery?.destinations.map((item) => <div key={item.id} className="rounded-md border border-white/[0.07] px-2.5 py-1.5 text-[10px] text-white/45"><span className={item.status === 'verified' ? 'text-emerald-400' : 'text-red-400'}>●</span> {item.name} · {item.bucket}</div>)}</div>
        {svc.subtype === 'postgres' && <div className="mt-3 flex items-center gap-3 rounded-lg border border-white/[0.07] bg-white/[0.02] p-3">
          <div className="min-w-0 flex-1"><div className="text-[11px] text-white/65">PostgreSQL point-in-time recovery</div><div className="mt-1 text-[10px] text-white/25">Daily physical base backup + continuous WAL archiving</div></div>
          {recovery?.pitr?.enabled ? <div className="text-right text-[10px] text-emerald-400">Active<div className="text-white/25">WAL {formatDate(recovery.pitr.lastWalArchivedAt)}</div></div> : <button type="button" disabled={!selectedDestination || configurePitr.isPending} onClick={() => configurePitr.mutate({ id: serviceId, destinationId: selectedDestination, retentionDays: 7 })} className="rounded-md bg-emerald-500/10 px-3 py-1.5 text-[10px] text-emerald-300 disabled:opacity-30">Enable PITR</button>}
        </div>}
      </section>

      <section className="px-5 py-4">
        <div className="mb-2 flex items-center justify-between">
          <h3 className="text-[11px] font-medium uppercase tracking-[0.12em] text-white/35">Schedule</h3>
          <button type="button" onClick={() => setShowSchedule((value) => !value)} className="text-[11px] text-[#a78bfa] hover:text-[#c4b5fd]">{showSchedule ? 'Cancel' : 'Configure'}</button>
        </div>
        {showSchedule && (
          <form className="mb-3 flex items-end gap-2 rounded-lg border border-white/[0.07] bg-white/[0.02] p-3" onSubmit={(event) => {
            event.preventDefault()
            createSchedule.mutate({ id: serviceId, data: { frequency, retentionCount } }, { onSuccess: () => setShowSchedule(false) })
          }}>
            <label className="flex-1 text-[10px] text-white/35">Frequency
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
            <label className="w-28 text-[10px] text-white/35">Keep latest
              <input type="number" min={1} max={30} value={retentionCount} onChange={(event) => setRetentionCount(Number(event.target.value))} className="mt-1 block w-full rounded-md border border-white/[0.08] bg-[#17171b] px-2 py-1.5 text-[12px] text-white/70 focus:outline-none focus:ring-1 focus:ring-[#8b5cf6]" />
            </label>
            <button className="rounded-md bg-white/[0.08] px-3 py-1.5 text-[11px] text-white/70 hover:bg-white/[0.12]">Save</button>
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
              return (
                <article key={backup.id} className="group grid grid-cols-[1fr_auto_auto] items-center gap-4 py-3">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      {ready ? <FileCheck2 size={14} className="text-emerald-400" /> : backup.status === 'failed' ? <AlertCircle size={14} className="text-red-400" /> : <Loader2 size={14} className="animate-spin text-amber-400" />}
                      <span className="font-mono text-[11px] text-white/65">{String(backup.id).slice(0, 8)}</span>
                      <span className={`rounded px-1.5 py-0.5 text-[9px] uppercase tracking-wider ${ready ? 'bg-emerald-500/10 text-emerald-400' : backup.status === 'failed' ? 'bg-red-500/10 text-red-400' : 'bg-amber-500/10 text-amber-300'}`}>{ready ? 'verified' : backup.status}</span>
                    </div>
                    <div className="mt-1 flex items-center gap-2 pl-[22px] text-[10px] text-white/25">
                      <span>{formatDate(backup.createdAt)}</span><span>·</span><span>{formatSize(backup.size)}</span>
                      {backup.metadata?.checksum && <><span>·</span><span className="font-mono">sha256:{backup.metadata.checksum.slice(0, 10)}</span></>}
                      {backup.encrypted && <><span>·</span><span className="text-emerald-400/70">encrypted</span></>}
                    </div>
                  </div>
                  <span className="text-[10px] text-white/20">{backup.metadata?.destination || 'local'}</span>
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
            <p className="mt-3 text-[12px] leading-5 text-white/40">Current {restoreTarget?.backupKind === 'volume' ? 'volume files' : 'database contents'} will be replaced. Create a fresh backup first if you may need to reverse this operation.</p>
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
