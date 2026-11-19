import { useState } from 'react'
import { DatabaseBackup, HardDrive, Clock3 } from 'lucide-react'
import BackupsSubTab from './BackupsSubTab'
import SnapshotsSubTab from './SnapshotsSubTab'
import PitrSubTab from './PitrSubTab'
import type { Service } from '@/types'

const SUB_TABS = [
  { key: 'backups', label: 'Backups', icon: DatabaseBackup },
  { key: 'snapshots', label: 'Snapshots', icon: HardDrive },
  { key: 'pitr', label: 'Point-in-time recovery', icon: Clock3 },
]

export default function BackupsTab({ svc, serviceId }: { svc: Service; serviceId: string }) {
  const [subTab, setSubTab] = useState('backups')
  const tabs = SUB_TABS.filter((tab) => tab.key === 'pitr' ? svc.subtype === 'postgres' : tab.key === 'snapshots' ? svc.storageMounts?.length > 0 : true)

  return (
    <div className="min-h-full bg-[#111114]">
      <div className="flex overflow-x-auto border-b border-white/6 px-5" role="tablist" aria-label="Backup and recovery sections">
        {tabs.map((t) => {
          const Icon = t.icon
          return (
            <button
              key={t.key}
              type="button"
              role="tab"
              aria-selected={subTab === t.key}
              onClick={() => setSubTab(t.key)}
              className={`flex items-center gap-1.5 px-3 py-2.5 text-[11px] border-b-2 transition-all whitespace-nowrap ${
                subTab === t.key
                  ? 'border-rail-purple text-rail-purple'
                  : 'border-transparent text-white/50 hover:text-white/60'
              }`}
            >
              <Icon size={12} />
              {t.label}
            </button>
          )
        })}
      </div>

      {subTab === 'backups' && <BackupsSubTab svc={svc} serviceId={serviceId} />}
      {subTab === 'snapshots' && <SnapshotsSubTab svc={svc} serviceId={serviceId} />}
      {subTab === 'pitr' && <PitrSubTab svc={svc} serviceId={serviceId} />}
    </div>
  )
}
