import { useState } from 'react'
import { useVolumeSnapshots, useRecovery, useBackupSchedules, useCreateSnapshotSchedule } from '@/hooks/useServices'
import type { Service } from '@/types'
import { ArtifactList, ScheduleForm, ScheduleList, SectionHeading } from './recovery/shared'
import { DEFAULT_RETENTION } from './recovery/lib'

/**
 * Schedules and copies of a service's mounted volumes. Rendered beneath the
 * volume list, whose per-mount button takes a snapshot on demand, so this
 * section only carries what happens automatically and what already exists.
 */
export default function SnapshotsSubTab({ svc, serviceId }: { svc: Service; serviceId: string }) {
  const { data: snapshots = [], isLoading, isError, refetch } = useVolumeSnapshots(serviceId)
  const { data: schedules = [] } = useBackupSchedules(serviceId)
  const { data: recovery } = useRecovery(serviceId)
  const createSchedule = useCreateSnapshotSchedule()
  const [showSchedule, setShowSchedule] = useState(false)

  const destinations = recovery?.destinations ?? []
  const mounts = svc.storageMounts ?? []
  const volumeSchedules = schedules.filter((schedule) => schedule.backupKind === 'volume')
  const mountPath = (id?: string) => mounts.find((mount) => mount.id === id)?.containerPath

  if (mounts.length === 0) return null

  return (
    <div className="bg-[#111114]">
      <section className="border-t border-white/6 px-5 py-4">
        <SectionHeading
          title="Snapshot schedules"
          description="Copy a volume automatically. Each schedule keeps its own number of copies."
          action={!showSchedule && (
            <button type="button" onClick={() => setShowSchedule(true)} className="shrink-0 text-[11px] text-rail-purple-light hover:underline">
              Add schedule
            </button>
          )}
        />
        {showSchedule && (
          <ScheduleForm
            initial={{
              frequency: 'daily',
              retentionCount: DEFAULT_RETENTION.daily,
              destinationIds: recovery?.backupPreferences?.defaultDestinationIds ?? [],
              storageMountId: mounts.length === 1 ? mounts[0].id : undefined,
            }}
            mounts={mounts}
            destinations={destinations}
            pending={createSchedule.isPending}
            submitLabel="Create schedule"
            onCancel={() => setShowSchedule(false)}
            onSubmit={(draft) =>
              createSchedule.mutate(
                {
                  id: serviceId,
                  data: {
                    frequency: draft.frequency,
                    retentionCount: draft.retentionCount,
                    storageMountId: draft.storageMountId ?? '',
                    destinationIds: draft.destinationIds,
                  },
                },
                { onSuccess: () => setShowSchedule(false) },
              )
            }
          />
        )}
        <ScheduleList
          serviceId={serviceId}
          schedules={volumeSchedules}
          destinations={destinations}
          emptyTitle="No automatic snapshots"
          emptyHint="Volumes are only copied when someone presses the snapshot button."
        />
      </section>

      <section className="border-t border-white/6 px-5 py-4">
        <SectionHeading title="Snapshots" description="Encrypted tar archives of a volume, checked with SHA-256." />
        <ArtifactList
          svc={svc}
          serviceId={serviceId}
          backups={snapshots}
          drills={recovery?.drills ?? []}
          isLoading={isLoading}
          isError={isError}
          refetch={refetch}
          emptyTitle="No snapshots yet"
          emptyHint="Snapshot a volume before changing its mount or running a migration."
          describe={(backup) => backup.metadata?.containerPath || mountPath(String(backup.metadata?.storageMountId ?? '')) || backup.metadata?.hostPath || 'volume'}
        />
      </section>
    </div>
  )
}
