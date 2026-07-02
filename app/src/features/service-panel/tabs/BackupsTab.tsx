import { useState } from 'react'
import { DatabaseBackup, HardDrive, Clock3 } from 'lucide-react'
import BackupsSubTab from './BackupsSubTab'
import SnapshotsSubTab from './SnapshotsSubTab'
import PitrSubTab from './PitrSubTab'
import type { Service } from '@/types'

const SUB_TABS = [
  { key: 'backups', label: 'Backups', icon: DatabaseBackup },
  { key: 'snapshots', label: 'Snapshots', icon: HardDrive },
  { key: 'pitr', label: 'PITR', icon: Clock3 },
]

export default function BackupsTab({ svc, serviceId }: { svc: Service; serviceId: string }) {
  const [subTab, setSubTab] = useState('backups')

  return (
    <div className="min-h-full bg-[#111114]">
      <div className="flex border-b border-white/[0.06] px-5">
        {SUB_TABS.map((t) => {
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
                  ? 'border-[#8b5cf6] text-[#8b5cf6]'
                  : 'border-transparent text-white/40 hover:text-white/60'
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
