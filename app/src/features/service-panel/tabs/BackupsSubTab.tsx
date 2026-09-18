import { useMemo, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
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
  Pencil,
  Plus,
  RotateCcw,
  ShieldCheck,
  Trash2,
  Upload,
} from 'lucide-react'
import {
  useBackups,
  useRecovery,
  useBackupSchedules,
  useBackupService,
  useCreateBackupSchedule,
  useCreateVolumeBackupSchedule,
  useDeleteBackup,
  useDestroyBackupSchedule,
  useUpdateBackupSchedule,
  useRestoreBackup,
  useRestoreService,
  useRunRestoreDrill,
} from '@/hooks/useServices'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Switch } from '@/components/ui/switch'
import { api } from '@/lib/api'
import type { Service, BackupDestination, BackupSchedule } from '@/types'

function formatSize(bytes = 0) {
  if (!bytes) return '—'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  const unit = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1)
  return `${(bytes / 1024 ** unit).toFixed(unit ? 1 : 0)} ${units[unit]}`
}

function formatDate(value?: string) {
  return value ? new Date(value).toLocaleString() : 'Not yet run'
}

/** "in 6h" / "2d ago" — the countdown operators actually scan for. */
function formatRelative(value?: string) {
  if (!value) return 'Not scheduled'
  const diff = new Date(value).getTime() - Date.now()
  const abs = Math.abs(diff)
  const units: [number, string][] = [[86400000, 'd'], [3600000, 'h'], [60000, 'm']]
  for (const [ms, label] of units) {
    if (abs >= ms) {
      const count = Math.round(abs / ms)
      return diff >= 0 ? `in ${count}${label}` : `${count}${label} ago`
    }
  }
  return diff >= 0 ? 'in <1m' : 'just now'
}

// Retention defaults follow the platform conventions (roughly a week of
// dailies, a month of weeklies, two quarters of monthlies) so a new schedule
// starts sane instead of at an arbitrary 7.
const DEFAULT_RETENTION: Record<string, number> = { daily: 7, weekly: 4, monthly: 6 }

const FREQUENCY_LABEL: Record<string, string> = { daily: 'Daily', weekly: 'Weekly', monthly: 'Monthly' }

function DestinationBadge({ name, kind }: { name: string; kind?: string }) {
  const color = kind === 'local' ? 'text-white/45' : kind === 'r2' ? 'text-orange-300' : 'text-emerald-300'
  return <span className={`rounded bg-white/[0.05] px-1.5 py-0.5 text-[9px] ${color}`}>{name}</span>
}

export default function BackupsSubTab({ svc, serviceId }: { svc: Service; serviceId: string }) {
  const { data: backups = [], isLoading, isError, refetch } = useBackups(serviceId)
  const { data: schedules = [] } = useBackupSchedules(serviceId)
  const createBackup = useBackupService()
  const createSchedule = useCreateBackupSchedule()
  const createVolumeSchedule = useCreateVolumeBackupSchedule()
  const destroySchedule = useDestroyBackupSchedule()
  const updateSchedule = useUpdateBackupSchedule()
  const restoreUpload = useRestoreService()
  const restoreBackup = useRestoreBackup()
  const deleteBackup = useDeleteBackup()
  const runDrill = useRunRestoreDrill()
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [showSchedule, setShowSchedule] = useState(false)
  const [frequency, setFrequency] = useState('daily')
  const [retentionCount, setRetentionCount] = useState(DEFAULT_RETENTION.daily)
  // Once the operator picks a retention window by hand, changing the frequency
  // must not silently overwrite it.
  const [retentionTouched, setRetentionTouched] = useState(false)
  const [editingScheduleId, setEditingScheduleId] = useState<string | null>(null)
  const [editFrequency, setEditFrequency] = useState('daily')
  const [editRetention, setEditRetention] = useState(7)
  const [scheduleDestinations, setScheduleDestinations] = useState<string[]>([])
  const [scheduleKind, setScheduleKind] = useState<'database' | 'volume'>('database')
  const [scheduleMountId, setScheduleMountId] = useState('')
  const [confirmRestore, setConfirmRestore] = useState<string | null>(null)
  const [restoreConfirmation, setRestoreConfirmation] = useState('')
  const [pendingUpload, setPendingUpload] = useState<File | null>(null)
  const [uploadConfirmation, setUploadConfirmation] = useState('')
  const [selectedDestinations, setSelectedDestinations] = useState<string[]>([])

  const { data: recovery } = useRecovery(serviceId)
  const destinations = recovery?.destinations || []
  const hasDestinations = destinations.length > 0
  const volumeMounts = svc.storageMounts ?? []

  const latestVerified = useMemo(
    () => backups.find((backup) => backup.status === 'completed' && backup.metadata?.verifiedAt),
    [backups],
  )
  const restoreTarget = backups.find((backup) => backup.id === confirmRestore)
  const restoreConfirmed = restoreConfirmation === svc.name

  const closeRestore = () => {
    setConfirmRestore(null)
    setRestoreConfirmation('')
  }

  const closeUpload = () => {
    setPendingUpload(null)
    setUploadConfirmation('')
  }

  const toggleDestination = (id: string, current: string[], setter: (ids: string[]) => void) => {
    if (current.includes(id)) {
      setter(current.filter((item) => item !== id))
    } else {
      setter([...current, id])
    }
  }

  const destinationOptions = (
    <>
      <label className="flex items-center gap-2 rounded px-2 py-1.5 text-[11px] text-white/70 hover:bg-white/[0.05] cursor-pointer">
        <input
          type="checkbox"
          checked={false}
          disabled
          className="rounded border-white/20 bg-[#17171b]"
        />
        <span>Local encrypted host (always included)</span>
      </label>
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
              if (file) { setUploadConfirmation(''); setPendingUpload(file) }
              event.target.value = ''
            }} />

            <div className="relative group">
              <button type="button" className="inline-flex items-center gap-1.5 rounded-md border border-white/[0.08] bg-[#17171b] px-2.5 py-1.5 text-[11px] text-white/70 hover:bg-white/[0.05]">
                <Cloud size={12} />
                {selectedDestinations.length === 0 ? 'Local only' : `${selectedDestinations.length} destination${selectedDestinations.length === 1 ? '' : 's'}`}
              </button>
              <div className="absolute right-0 top-full z-20 mt-1 hidden w-56 rounded-md border border-white/[0.08] bg-[#17171b] p-1 shadow-xl group-hover:block group-focus-within:block">
                {destinationOptions}
                <Link
                  to="/dashboard/settings?tab=backup-destinations"
                  className="mt-1 flex items-center gap-1.5 border-t border-white/[0.06] px-2 py-1.5 text-[10px] text-[#a78bfa] hover:text-[#c4b5fd]"
                >
                  <ExternalLink size={10} />
                  Manage destinations
                </Link>
              </div>
            </div>

            <button type="button" onClick={() => createBackup.mutate({ id: serviceId, backupDestinationIds: selectedDestinations })} disabled={createBackup.isPending} className="inline-flex items-center gap-1.5 rounded-md bg-[#8b5cf6] px-3 py-1.5 text-[11px] font-medium text-white hover:bg-[#7C3AED] disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#a78bfa]">
              {createBackup.isPending ? <Loader2 size={12} className="animate-spin" /> : <Plus size={12} />}
              Create backup
            </button>
          </div>
        </div>
      </header>

      {!hasDestinations && (
        <div className="mx-5 mt-4 rounded-lg border border-amber-400/20 bg-amber-400/[0.04] px-3 py-2 text-[11px] text-amber-300">
          No shared backup destinations configured.
          <Link to="/dashboard/settings?tab=backup-destinations" className="ml-1 underline hover:text-amber-200">
            Add an S3 or R2 destination
          </Link>
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
          <div className="text-[10px] uppercase tracking-[0.14em] text-white/25">Scheduled backups</div>
          <div className="mt-1 text-[12px] text-white/70">
            {schedules.length === 0
              ? 'Manual only'
              : `${schedules.length} schedule${schedules.length === 1 ? '' : 's'} · next ${formatRelative(
                  schedules
                    .map((schedule) => schedule.nextRunAt)
                    .filter(Boolean)
                    .sort()[0] as string | undefined,
                )}`}
          </div>
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
          <Link
            to="/dashboard/settings?tab=backup-destinations"
            className="text-[11px] text-[#a78bfa] hover:text-[#c4b5fd] flex items-center gap-1"
          >
            <ExternalLink size={10} />
            Manage
          </Link>
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
        <div className="mb-3 flex items-start justify-between gap-3">
          <div>
            <h3 className="text-[11px] font-medium uppercase tracking-[0.12em] text-white/35">Scheduled backups</h3>
            <p className="mt-1 text-[10px] text-white/20">
              Every schedule keeps its own retention window and destinations, and can be paused
              without losing its place in the rotation.
            </p>
          </div>
          <button
            type="button"
            onClick={() => setShowSchedule((value) => !value)}
            className="shrink-0 text-[11px] text-[#a78bfa] hover:text-[#c4b5fd]"
          >
            {showSchedule ? 'Cancel' : '+ Add schedule'}
          </button>
        </div>

        {showSchedule && (
          <form
            className="mb-3 rounded-lg border border-white/[0.07] bg-white/[0.02] p-3"
            onSubmit={(event) => {
              event.preventDefault()
              const onCreated = () => {
                setShowSchedule(false)
                setScheduleDestinations([])
                setScheduleMountId('')
                setRetentionTouched(false)
              }
              if (scheduleKind === 'volume') {
                if (!scheduleMountId) return
                createVolumeSchedule.mutate(
                  {
                    id: serviceId,
                    data: {
                      frequency,
                      retentionCount,
                      storageMountId: scheduleMountId,
                      destinationIds: scheduleDestinations,
                    },
                  },
                  { onSuccess: onCreated }
                )
                return
              }
              createSchedule.mutate(
                { id: serviceId, data: { frequency, retentionCount, destinationIds: scheduleDestinations } },
                { onSuccess: onCreated }
              )
            }}
          >
            {volumeMounts.length > 0 && (
              <div className="mb-2 flex items-end gap-2">
                <label className="flex-1 text-[10px] text-white/35">
                  Back up
                  <Select
                    value={scheduleKind}
                    onValueChange={(value) => setScheduleKind(value as 'database' | 'volume')}
                  >
                    <SelectTrigger className="mt-1 block w-full rounded-md border border-white/[0.08] bg-[#17171b] px-2 py-1.5 text-[12px] text-white/70">
                      <SelectValue placeholder="Database" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="database">Database</SelectItem>
                      <SelectItem value="volume">Volume snapshot</SelectItem>
                    </SelectContent>
                  </Select>
                </label>
                {scheduleKind === 'volume' && (
                  <label className="flex-1 text-[10px] text-white/35">
                    Mounted path
                    <Select value={scheduleMountId} onValueChange={setScheduleMountId}>
                      <SelectTrigger className="mt-1 block w-full rounded-md border border-white/[0.08] bg-[#17171b] px-2 py-1.5 text-[12px] text-white/70">
                        <SelectValue placeholder="Choose a volume" />
                      </SelectTrigger>
                      <SelectContent>
                        {volumeMounts.map((mount) => (
                          <SelectItem key={mount.id} value={mount.id}>
                            {mount.containerPath}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </label>
                )}
              </div>
            )}
            <div className="flex items-end gap-2">
              <label className="flex-1 text-[10px] text-white/35">
                Frequency
                <Select
                  value={frequency}
                  onValueChange={(value) => {
                    setFrequency(value)
                    if (!retentionTouched) setRetentionCount(DEFAULT_RETENTION[value] ?? 7)
                  }}
                >
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
                <input
                  type="number"
                  min={1}
                  max={90}
                  value={retentionCount}
                  onChange={(event) => {
                    setRetentionTouched(true)
                    setRetentionCount(Number(event.target.value))
                  }}
                  className="mt-1 block w-full rounded-md border border-white/[0.08] bg-[#17171b] px-2 py-1.5 text-[12px] text-white/70 focus:outline-none focus:ring-1 focus:ring-[#8b5cf6]"
                />
              </label>
              <button className="rounded-md bg-rail-purple px-3 py-1.5 text-[11px] font-medium text-white hover:bg-rail-purple-dark">
                Save
              </button>
            </div>
            <p className="mt-2 text-[10px] text-white/25">
              Keeps the newest artifact of every kind, and never expires a pre-destroy or pre-restore
              safety snapshot.
            </p>
            {destinations.length > 0 && (
              <div className="mt-3">
                <div className="mb-1 text-[10px] text-white/35">Also send scheduled backups to</div>
                <div className="flex flex-wrap gap-2">
                  {destinations.map((destination: BackupDestination) => (
                    <label
                      key={destination.id}
                      className="flex cursor-pointer items-center gap-1.5 rounded border border-white/[0.07] px-2 py-1 text-[10px] text-white/60 hover:bg-white/[0.03]"
                    >
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

        {schedules.length === 0 ? (
          <div className="rounded-lg border border-dashed border-white/[0.08] py-6 text-center">
            <Clock3 size={18} className="mx-auto mb-2 text-white/15" />
            <div className="text-[12px] text-white/45">No scheduled backups</div>
            <div className="mt-1 text-[11px] text-white/20">
              Add a daily, weekly or monthly cadence so recoverability does not depend on remembering.
            </div>
          </div>
        ) : (
          <div className="divide-y divide-white/[0.05] rounded-lg border border-white/[0.05]">
            {schedules.map((schedule: BackupSchedule) => {
              const isEditing = editingScheduleId === schedule.id
              const isVolume = schedule.backupKind === 'volume'
              return (
                <div key={schedule.id} className={`px-3 py-2.5 ${schedule.enabled ? '' : 'opacity-55'}`}>
                  <div className="flex items-center gap-3">
                    <Clock3 size={13} className={schedule.enabled ? 'text-rail-purple' : 'text-white/20'} />
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2 text-[12px] text-white/70">
                        <span className="font-medium">
                          {FREQUENCY_LABEL[schedule.frequency] || schedule.frequency}
                        </span>
                        <span className="rounded bg-white/[0.05] px-1.5 py-0.5 text-[9px] text-white/40">
                          {isVolume ? 'volume' : 'database'}
                        </span>
                        {isVolume && schedule.storageMount?.containerPath && (
                          <span className="truncate font-mono text-[10px] text-white/30">
                            {schedule.storageMount.containerPath}
                          </span>
                        )}
                        <span className="text-white/30">keep {schedule.retentionCount}</span>
                      </div>
                      <div className="mt-0.5 text-[10px] text-white/25">
                        {schedule.enabled ? `Next ${formatRelative(schedule.nextRunAt)}` : 'Paused'}
                        {' · '}
                        {schedule.lastRunAt ? `last run ${formatRelative(schedule.lastRunAt)}` : 'never run'}
                      </div>
                    </div>
                    <Switch
                      checked={Boolean(schedule.enabled)}
                      aria-label={schedule.enabled ? 'Pause schedule' : 'Resume schedule'}
                      onCheckedChange={(checked) =>
                        updateSchedule.mutate({ id: serviceId, scheduleId: schedule.id, data: { enabled: checked } })
                      }
                    />
                    <button
                      type="button"
                      aria-label="Edit schedule"
                      onClick={() => {
                        if (isEditing) {
                          setEditingScheduleId(null)
                          return
                        }
                        setEditingScheduleId(schedule.id)
                        setEditFrequency(schedule.frequency)
                        setEditRetention(schedule.retentionCount)
                      }}
                      className="rounded p-1 text-white/25 hover:bg-white/[0.06] hover:text-white/60"
                    >
                      <Pencil size={12} />
                    </button>
                    <button
                      type="button"
                      aria-label="Delete schedule"
                      onClick={() => destroySchedule.mutate({ id: serviceId, scheduleId: schedule.id })}
                      className="rounded p-1 text-white/25 hover:bg-red-500/10 hover:text-red-400"
                    >
                      <Trash2 size={12} />
                    </button>
                  </div>

                  {isEditing && (
                    <div className="mt-2 flex items-end gap-2 rounded-lg border border-white/[0.07] bg-white/[0.02] p-2.5">
                      <label className="flex-1 text-[10px] text-white/35">
                        Frequency
                        <Select value={editFrequency} onValueChange={(value) => setEditFrequency(value)}>
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
                        <input
                          type="number"
                          min={1}
                          max={90}
                          value={editRetention}
                          onChange={(event) => setEditRetention(Number(event.target.value))}
                          className="mt-1 block w-full rounded-md border border-white/[0.08] bg-[#17171b] px-2 py-1.5 text-[12px] text-white/70"
                        />
                      </label>
                      <button
                        type="button"
                        onClick={() =>
                          updateSchedule.mutate(
                            {
                              id: serviceId,
                              scheduleId: schedule.id,
                              data: { frequency: editFrequency, retentionCount: editRetention },
                            },
                            { onSuccess: () => setEditingScheduleId(null) }
                          )
                        }
                        className="rounded-md bg-rail-purple px-3 py-1.5 text-[11px] font-medium text-white hover:bg-rail-purple-dark"
                      >
                        Save
                      </button>
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        )}
      </section>

      <section className="px-5 pb-5">
        <div className="mb-2 flex items-center justify-between">
          <h3 className="text-[11px] font-medium uppercase tracking-[0.12em] text-white/35">Artifacts</h3>
          <span className="text-[10px] text-white/20">{backups.length} total</span>
        </div>
        {isLoading ? <div className="py-10 text-center text-[12px] text-white/50">Loading recovery history…</div> : isError ? (
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
                    <button type="button" disabled={!ready} onClick={() => download(backup.id)} aria-label="Download backup" className="rounded p-1.5 text-white/50 hover:bg-white/[0.06] hover:text-white/70 disabled:opacity-20"><Download size={13} /></button>
                    <button type="button" disabled={!ready} onClick={() => { setRestoreConfirmation(''); setConfirmRestore(backup.id) }} aria-label="Restore backup" className="rounded p-1.5 text-white/50 hover:bg-amber-500/10 hover:text-amber-300 disabled:opacity-20"><RotateCcw size={13} /></button>
                    <button type="button" disabled={!ready || backup.backupKind === 'volume' || backup.backupKind === 'wal'} onClick={() => runDrill.mutate({ id: serviceId, backupId: backup.id })} aria-label="Run isolated restore drill" className="rounded p-1.5 text-white/50 hover:bg-emerald-500/10 hover:text-emerald-300 disabled:opacity-20"><FlaskConical size={13} /></button>
                    <button type="button" onClick={() => deleteBackup.mutate({ id: serviceId, backupId: backup.id })} aria-label="Delete backup" className="rounded p-1.5 text-white/20 hover:bg-red-500/10 hover:text-red-400"><Trash2 size={13} /></button>
                  </div>
                </article>
              )
            })}
          </div>
        )}
      </section>

      {pendingUpload && (
        <div className="fixed inset-0 z-[90] flex items-center justify-center bg-black/70 p-4" role="dialog" aria-modal="true" aria-labelledby="upload-restore-title">
          <div className="w-full max-w-sm rounded-xl border border-white/[0.09] bg-[#19191d] p-5 shadow-2xl">
            <div className="flex items-center gap-2 text-amber-300"><Upload size={16} /><h3 id="upload-restore-title" className="text-[14px] font-medium">Restore from an uploaded dump?</h3></div>
            <div className="mt-3 space-y-1.5 rounded-lg border border-white/[0.06] bg-white/[0.02] p-3 text-[11px]">
              <div className="flex justify-between"><span className="text-white/50">File</span><span className="max-w-[60%] truncate text-white/65">{pendingUpload.name}</span></div>
              <div className="flex justify-between"><span className="text-white/50">Size</span><span className="text-white/65">{formatSize(pendingUpload.size)}</span></div>
            </div>
            <p className="mt-3 text-[12px] leading-5 text-white/50">
              The current database contents will be replaced by this dump. A safety snapshot of the current state is
              taken first when a verified destination is available, but anything written since this dump was created
              cannot be recovered.
            </p>
            <label className="mt-3 block text-[11px] text-white/50">
              Type <span className="font-mono text-white/70">{svc.name}</span> to confirm
              <input
                value={uploadConfirmation}
                onChange={(event) => setUploadConfirmation(event.target.value)}
                autoComplete="off"
                aria-label="Confirm service name"
                className="mt-1.5 w-full rounded-md border border-white/[0.09] bg-white/[0.03] px-2.5 py-1.5 font-mono text-[11px] text-white/80 outline-none focus:border-amber-400/40"
              />
            </label>
            <div className="mt-5 flex justify-end gap-2">
              <button onClick={closeUpload} className="rounded-md px-3 py-1.5 text-[11px] text-white/45 hover:bg-white/[0.05]">Cancel</button>
              <button disabled={uploadConfirmation !== svc.name} onClick={() => restoreUpload.mutate({ id: serviceId, file: pendingUpload, confirm: svc.name }, { onSuccess: () => closeUpload() })} className="inline-flex items-center gap-1.5 rounded-md bg-amber-500/15 px-3 py-1.5 text-[11px] text-amber-300 hover:bg-amber-500/25 disabled:cursor-not-allowed disabled:opacity-40"><Check size={12} /> Restore</button>
            </div>
          </div>
        </div>
      )}

      {confirmRestore && (
        <div className="fixed inset-0 z-[90] flex items-center justify-center bg-black/70 p-4" role="dialog" aria-modal="true" aria-labelledby="restore-title">
          <div className="w-full max-w-sm rounded-xl border border-white/[0.09] bg-[#19191d] p-5 shadow-2xl">
            <div className="flex items-center gap-2 text-amber-300"><RotateCcw size={16} /><h3 id="restore-title" className="text-[14px] font-medium">Restore this recovery point?</h3></div>
            {restoreTarget && (
              <div className="mt-3 space-y-1.5 rounded-lg border border-white/[0.06] bg-white/[0.02] p-3 text-[11px]">
                <div className="flex justify-between"><span className="text-white/50">Type</span><span className="text-white/65 capitalize">{restoreTarget.backupKind === 'volume' ? 'Volume snapshot' : restoreTarget.backupKind}</span></div>
                <div className="flex justify-between"><span className="text-white/50">Created</span><span className="text-white/65">{formatDate(restoreTarget.createdAt)}</span></div>
                <div className="flex justify-between"><span className="text-white/50">Size</span><span className="text-white/65">{formatSize(restoreTarget.size)}</span></div>
                {restoreTarget.metadata?.checksum && <div className="flex justify-between"><span className="text-white/50">Checksum</span><span className="font-mono text-white/65">sha256:{restoreTarget.metadata.checksum.slice(0, 10)}…</span></div>}
              </div>
            )}
            <p className="mt-3 text-[12px] leading-5 text-white/50">
              Current {restoreTarget?.backupKind === 'volume' ? 'volume files' : 'database contents'} will be replaced.
              A safety snapshot of the current state is taken first when a verified destination is available, but
              everything written since this recovery point is replaced.
            </p>
            <label className="mt-3 block text-[11px] text-white/50">
              Type <span className="font-mono text-white/70">{svc.name}</span> to confirm
              <input
                value={restoreConfirmation}
                onChange={(event) => setRestoreConfirmation(event.target.value)}
                autoComplete="off"
                aria-label="Confirm service name"
                className="mt-1.5 w-full rounded-md border border-white/[0.09] bg-white/[0.03] px-2.5 py-1.5 font-mono text-[11px] text-white/80 outline-none focus:border-amber-400/40"
              />
            </label>
            <div className="mt-5 flex justify-end gap-2">
              <button onClick={closeRestore} className="rounded-md px-3 py-1.5 text-[11px] text-white/45 hover:bg-white/[0.05]">Cancel</button>
              <button disabled={!restoreConfirmed} onClick={() => restoreBackup.mutate({ id: serviceId, backupId: confirmRestore, confirm: svc.name }, { onSuccess: () => closeRestore() })} className="inline-flex items-center gap-1.5 rounded-md bg-amber-500/15 px-3 py-1.5 text-[11px] text-amber-300 hover:bg-amber-500/25 disabled:cursor-not-allowed disabled:opacity-40"><Check size={12} /> Restore</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
