import { useSearchParams } from 'react-router-dom'
import { Clock3, DatabaseBackup, HardDrive } from 'lucide-react'
import BackupsSubTab from './BackupsSubTab'
import SnapshotsSubTab from './SnapshotsSubTab'
import PitrSubTab from './PitrSubTab'
import StorageTab from './StorageTab'
import { useBackupSchedules, useRecovery } from '@/hooks/useServices'
import type { Service } from '@/types'
import { supportsLogicalBackup, supportsPitr } from './recovery/lib'

type Section = 'backups' | 'pitr' | 'volumes'

/**
 * Everything that protects a service's data, by what it covers:
 *
 * - Database backups — logical dumps of a datastore (Postgres, MySQL, MariaDB,
 *   MongoDB, Redis), manual or scheduled.
 * - Point-in-time — PostgreSQL base backups plus continuous WAL.
 * - Volumes — the mounted folders themselves, with snapshots and schedules.
 *
 * An app with no datastore only has volumes, so it gets that view directly
 * with no section switcher.
 */
export default function BackupsTab({ svc, serviceId }: { svc: Service; serviceId: string }) {
  const [searchParams, setSearchParams] = useSearchParams()
  const logical = supportsLogicalBackup(svc)
  const pitr = supportsPitr(svc)
  const hasMounts = (svc.storageMounts?.length ?? 0) > 0

  const sections: { key: Section; label: string; icon: typeof DatabaseBackup }[] = [
    ...(logical ? [{ key: 'backups' as const, label: 'Database backups', icon: DatabaseBackup }] : []),
    ...(pitr ? [{ key: 'pitr' as const, label: 'Point-in-time', icon: Clock3 }] : []),
    // Datastores rarely need extra mounts, so their Volumes section only
    // appears once one exists; apps always get it so a volume can be added.
    ...(!logical || hasMounts ? [{ key: 'volumes' as const, label: 'Volumes', icon: HardDrive }] : []),
  ]

  const requested = searchParams.get('section') as Section | null
  const active = sections.find((section) => section.key === requested)?.key ?? sections[0]?.key ?? 'volumes'
  const select = (next: Section) =>
    setSearchParams((previous) => {
      const params = new URLSearchParams(previous)
      params.set('section', next)
      return params
    }, { replace: true })

  return (
    <div className="min-h-full bg-[#111114]">
      <ProtectionSummary svc={svc} serviceId={serviceId} logical={logical} pitr={pitr} />
      {sections.length > 1 && (
        <div className="flex overflow-x-auto border-b border-white/6 px-5" role="tablist" aria-label="Data protection sections">
          {sections.map((section) => {
            const Icon = section.icon
            return (
              <button
                key={section.key}
                type="button"
                role="tab"
                aria-selected={active === section.key}
                onClick={() => select(section.key)}
                className={`flex items-center gap-1.5 whitespace-nowrap border-b-2 px-3 py-2.5 text-[12px] transition-colors ${
                  active === section.key ? 'border-rail-purple text-white/85' : 'border-transparent text-white/50 hover:text-white/70'
                }`}
              >
                <Icon size={14} />
                {section.label}
              </button>
            )
          })}
        </div>
      )}

      {active === 'backups' && <BackupsSubTab svc={svc} serviceId={serviceId} />}
      {active === 'pitr' && <PitrSubTab svc={svc} serviceId={serviceId} />}
      {active === 'volumes' && (
        <>
          <StorageTab svc={svc} />
          <SnapshotsSubTab svc={svc} serviceId={serviceId} />
        </>
      )}
    </div>
  )
}

/**
 * One line that answers "is this service protected?" before the operator digs
 * into a section: which kinds of copy run automatically, and whether any of
 * them leave the host.
 */
function ProtectionSummary({ svc, serviceId, logical, pitr }: { svc: Service; serviceId: string; logical: boolean; pitr: boolean }) {
  const { data: schedules = [] } = useBackupSchedules(serviceId)
  const { data: recovery } = useRecovery(serviceId)
  if (!recovery) return null

  const mounts = svc.storageMounts ?? []
  const enabled = schedules.filter((schedule) => schedule.enabled)
  const databaseScheduled = enabled.some((schedule) => schedule.backupKind === 'database')
  const scheduledMounts = new Set(enabled.filter((s) => s.backupKind === 'volume').map((s) => String(s.storageMountId)))
  const coveredMounts = mounts.filter((mount) => scheduledMounts.has(String(mount.id))).length
  const offsite = enabled.some((schedule) => (schedule.destinationIds ?? []).length > 0) || Boolean(recovery.pitr?.enabled)

  const items: { label: string; ok: boolean }[] = [
    ...(logical ? [{ label: databaseScheduled ? 'Database backed up automatically' : 'No automatic database backup', ok: databaseScheduled }] : []),
    ...(pitr ? [{ label: recovery.pitr?.enabled ? 'Point-in-time on' : 'Point-in-time off', ok: Boolean(recovery.pitr?.enabled) }] : []),
    ...(mounts.length > 0 ? [{ label: `${coveredMounts} of ${mounts.length} volume${mounts.length === 1 ? '' : 's'} on a schedule`, ok: coveredMounts === mounts.length }] : []),
    ...(enabled.length > 0 || recovery.pitr?.enabled ? [{ label: offsite ? 'Copies leave this host' : 'Copies stay on this host only', ok: offsite }] : []),
  ]
  if (items.length === 0) return null

  return (
    <div className="flex flex-wrap gap-x-4 gap-y-1 border-b border-white/6 px-5 py-2.5 text-[11px]" aria-label="Protection summary">
      {items.map((item) => (
        <span key={item.label} className="flex items-center gap-1.5 text-white/55">
          <span aria-hidden className={`size-1.5 rounded-full ${item.ok ? 'bg-emerald-400' : 'bg-amber-400'}`} />
          {item.label}
        </span>
      ))}
    </div>
  )
}
