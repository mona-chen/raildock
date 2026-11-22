import { useEffect, useMemo, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { ChevronDown, Cloud, ExternalLink, Loader2, Plus, RotateCcw, Upload } from 'lucide-react'
import {
  useBackups,
  useRecovery,
  useBackupSchedules,
  useBackupService,
  useCreateBackupSchedule,
  useRestoreService,
  useUpdateBackupPreferences,
} from '@/hooks/useServices'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import ConfirmDialog from '@/features/shared/ConfirmDialog'
import type { Backup, Service } from '@/types'
import { ArtifactList, DestinationChecklist, ScheduleForm, ScheduleList, SectionHeading, useForceDialog } from './recovery/shared'
import { DEFAULT_RETENTION, formatDate, formatRelative, formatSize, toggleId } from './recovery/lib'

const IMPORT_ACCEPT: Record<string, string> = {
  postgres: '.dump,.sql,.gz',
  mysql: '.sql,.gz',
  mariadb: '.sql,.gz',
  mongo: '.archive,.gz',
  redis: '.rdb',
}

/**
 * Logical dumps of a datastore: manual and scheduled backups, imports and
 * restores. Volume snapshots and PITR have their own sections, so this list
 * only carries database dumps (plus PITR base backups, which can be tested
 * here but are restored through point-in-time recovery).
 */
export default function BackupsSubTab({ svc, serviceId }: { svc: Service; serviceId: string }) {
  const { data: allBackups = [], isLoading, isError, refetch } = useBackups(serviceId)
  const { data: allSchedules = [] } = useBackupSchedules(serviceId)
  const { data: recovery } = useRecovery(serviceId)
  const createBackup = useBackupService()
  const createSchedule = useCreateBackupSchedule()
  const force = useForceDialog()
  const restoreUpload = useRestoreService(force.options)
  const rememberDestinations = useUpdateBackupPreferences()
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [showSchedule, setShowSchedule] = useState(false)
  const [pendingUpload, setPendingUpload] = useState<File | null>(null)
  const [selectedDestinations, setSelectedDestinations] = useState<string[]>([])
  // Seeded once per service from the server so a reload does not silently drop
  // the operator back to "Local only", while our own later toggles are not
  // fought over by a background refetch.
  const [destinationsSeededFor, setDestinationsSeededFor] = useState<string | null>(null)

  const destinations = recovery?.destinations ?? []
  const drills = recovery?.drills ?? []
  const preferences = recovery?.backupPreferences
  const inheritsOrganizationDefault = preferences?.serviceDestinationIds === null

  const backups = useMemo(
    () => allBackups.filter((backup: Backup) => backup.backupKind !== 'volume' && backup.backupKind !== 'wal'),
    [allBackups],
  )
  const schedules = allSchedules.filter((schedule) => schedule.backupKind === 'database')

  useEffect(() => {
    if (!preferences || destinationsSeededFor === serviceId) return
    setSelectedDestinations(preferences.defaultDestinationIds ?? [])
    setDestinationsSeededFor(serviceId)
  }, [preferences, serviceId, destinationsSeededFor])

  const latestVerified = backups.find((backup) => backup.status === 'completed' && backup.metadata?.verifiedAt && backup.backupKind !== 'pitr_base')
  const nextRun = schedules.filter((s) => s.enabled).map((s) => s.nextRunAt).filter(Boolean).sort()[0] as string | undefined

  // The manual-backup picker is the service's own choice, so changing it is
  // persisted immediately instead of living only in React state.
  const toggleSelectedDestination = (id: string) => {
    const next = toggleId(selectedDestinations, id)
    setSelectedDestinations(next)
    rememberDestinations.mutate({ id: serviceId, backupDestinationIds: next })
  }

  const useOrganizationDefault = () => {
    setSelectedDestinations(preferences?.organizationDestinationIds ?? [])
    rememberDestinations.mutate({ id: serviceId, backupDestinationIds: null })
  }

  const destinationLabel = !recovery
    ? 'Destinations…'
    : selectedDestinations.length === 0
      ? 'Local only'
      : `${selectedDestinations.length} destination${selectedDestinations.length === 1 ? '' : 's'}`

  return (
    <div className="min-h-full bg-[#111114]">
      <header className="flex items-start justify-between gap-4 border-b border-white/6 px-5 py-4">
        <div>
          <h2 className="text-[14px] font-medium text-white/85">Database backups</h2>
          <p className="mt-1 text-[12px] text-white/40">
            Full dumps of {svc.name}, checked with SHA-256 before they count as a copy.
          </p>
        </div>
        <div className="flex shrink-0 items-center gap-2">
          <button
            type="button"
            onClick={() => fileInputRef.current?.click()}
            className="inline-flex items-center gap-1.5 rounded-md border border-white/8 px-2.5 py-1.5 text-[11px] text-white/60 hover:bg-white/5"
          >
            <Upload size={12} /> Import
          </button>
          <input
            ref={fileInputRef}
            type="file"
            accept={IMPORT_ACCEPT[svc.subtype] ?? '.sql,.dump,.gz'}
            className="hidden"
            aria-label="Choose a dump file to import"
            onChange={(event) => {
              const file = event.target.files?.[0]
              if (file) setPendingUpload(file)
              event.target.value = ''
            }}
          />
          <Popover>
            <PopoverTrigger asChild>
              <button
                type="button"
                className="inline-flex items-center gap-1.5 rounded-md border border-white/8 bg-[#17171b] px-2.5 py-1.5 text-[11px] text-white/70 hover:bg-white/5"
              >
                <Cloud size={12} />
                {destinationLabel}
                <ChevronDown size={12} className="text-white/35" />
              </button>
            </PopoverTrigger>
            <PopoverContent align="end" className="w-64 border-white/8 bg-[#17171b] p-3">
              <div className="mb-2 text-[11px] text-white/50">Where new backups go</div>
              <DestinationChecklist destinations={destinations} selected={selectedDestinations} onToggle={toggleSelectedDestination} />
              {destinations.length > 0 && (
                <p className="mt-2 text-[10px] leading-4 text-white/30">
                  With no destination ticked, the only copy stays on this host. Once a destination stores it, the host copy is removed.
                </p>
              )}
              <div className="mt-2 flex items-center justify-between border-t border-white/6 pt-2">
                {!inheritsOrganizationDefault ? (
                  <button type="button" onClick={useOrganizationDefault} className="flex items-center gap-1 text-[11px] text-white/45 hover:text-white/75">
                    <RotateCcw size={11} /> Use organization default
                  </button>
                ) : (
                  <span className="text-[11px] text-white/30">Following organization default</span>
                )}
                <Link to="/dashboard/settings?tab=backup-destinations" className="flex items-center gap-1 text-[11px] text-rail-purple-light hover:underline">
                  <ExternalLink size={11} /> Manage
                </Link>
              </div>
            </PopoverContent>
          </Popover>
          <button
            type="button"
            onClick={() => createBackup.mutate({ id: serviceId, backupDestinationIds: selectedDestinations })}
            disabled={createBackup.isPending}
            className="inline-flex items-center gap-1.5 rounded-md bg-rail-purple px-3 py-1.5 text-[11px] font-medium text-white hover:bg-rail-purple-dark disabled:opacity-50"
          >
            {createBackup.isPending ? <Loader2 size={12} className="animate-spin" /> : <Plus size={12} />}
            Back up now
          </button>
        </div>
      </header>

      {recovery && destinations.length === 0 && (
        <div className="mx-5 mt-4 rounded-lg border border-amber-400/20 bg-amber-400/4 px-3 py-2 text-[11px] text-amber-300">
          Backups only exist on this host.{' '}
          <Link to="/dashboard/settings?tab=backup-destinations" className="underline hover:text-amber-200">
            Add an off-site destination
          </Link>{' '}
          so they survive a disk failure.
        </div>
      )}

      <dl className="grid grid-cols-3 border-b border-white/6">
        <div className="px-5 py-3">
          <dt className="text-[11px] text-white/35">Latest verified copy</dt>
          <dd className="mt-1 text-[12px] text-white/75">{latestVerified ? formatDate(latestVerified.createdAt) : 'None yet'}</dd>
        </div>
        <div className="border-x border-white/6 px-5 py-3">
          <dt className="text-[11px] text-white/35">Automatic backups</dt>
          <dd className="mt-1 text-[12px] text-white/75">
            {schedules.length === 0 ? 'Off' : nextRun ? `Next ${formatRelative(nextRun)}` : 'Paused'}
          </dd>
        </div>
        <div className="px-5 py-3">
          <dt className="text-[11px] text-white/35">Copies stored</dt>
          <dd className="mt-1 text-[12px] text-white/75">{backups.filter((b) => b.status === 'completed').length}</dd>
        </div>
      </dl>

      <section className="border-b border-white/6 px-5 py-4">
        <SectionHeading
          title="Schedules"
          description="Each schedule keeps its own number of copies and destinations, and can be paused without losing its place."
          action={!showSchedule && (
            <button type="button" onClick={() => setShowSchedule(true)} className="shrink-0 text-[11px] text-rail-purple-light hover:underline">
              Add schedule
            </button>
          )}
        />
        {showSchedule && (
          <ScheduleForm
            initial={{ frequency: 'daily', retentionCount: DEFAULT_RETENTION.daily, destinationIds: preferences?.defaultDestinationIds ?? [] }}
            destinations={destinations}
            pending={createSchedule.isPending}
            submitLabel="Create schedule"
            onCancel={() => setShowSchedule(false)}
            onSubmit={(draft) =>
              createSchedule.mutate(
                { id: serviceId, data: { frequency: draft.frequency, retentionCount: draft.retentionCount, destinationIds: draft.destinationIds } },
                { onSuccess: () => setShowSchedule(false) },
              )
            }
          />
        )}
        <ScheduleList
          serviceId={serviceId}
          schedules={schedules}
          destinations={destinations}
          emptyTitle="No automatic backups"
          emptyHint="Add a daily, weekly or monthly schedule so a copy exists without anyone remembering to make one."
        />
      </section>

      <section className="px-5 py-4">
        <SectionHeading title="Backups" description="Test a restore in an isolated copy any time; your live data is not touched." />
        <ArtifactList
          svc={svc}
          serviceId={serviceId}
          backups={backups}
          drills={drills}
          isLoading={isLoading}
          isError={isError}
          refetch={refetch}
          emptyTitle="No backups yet"
          emptyHint="Make one now before your next risky change."
          describe={(backup) => (backup.backupKind === 'pitr_base' ? 'PITR base backup' : 'Full dump')}
        />
      </section>

      <ConfirmDialog
        open={pendingUpload !== null}
        onOpenChange={(open) => { if (!open) setPendingUpload(null) }}
        title="Restore from an uploaded dump?"
        description={
          pendingUpload && (
            <>
              <span className="text-white/80">{pendingUpload.name}</span> ({formatSize(pendingUpload.size)}) replaces the current
              contents of {svc.name}.
            </>
          )
        }
        warning="A safety snapshot of the current data is taken first, so this can be undone. Anything written after the dump was made is replaced."
        confirmWord={svc.name}
        confirmLabel="Restore"
        pending={restoreUpload.isPending}
        onConfirm={() => {
          if (!pendingUpload) return
          restoreUpload.mutate({ id: serviceId, file: pendingUpload, confirm: svc.name }, { onSettled: () => setPendingUpload(null) })
        }}
      />
      {force.dialog}
    </div>
  )
}
