import { useState } from 'react'
import { DatabaseBackup, Loader2, ShieldCheck, ShieldX, Clock, AlertCircle } from 'lucide-react'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { useRecovery, useConfigurePitr } from '@/hooks/useServices'
import type { Service, BackupDestination } from '@/types'

function formatDate(value?: string) {
  return value ? new Date(value).toLocaleString() : 'Not yet run'
}

export default function PitrSubTab({ svc, serviceId }: { svc: Service; serviceId: string }) {
  const { data: recovery, isLoading } = useRecovery(serviceId)
  const configurePitr = useConfigurePitr()
  const [selectedDestination, setSelectedDestination] = useState('')

  const destinations = recovery?.destinations || []
  const pitr = recovery?.pitr

  if (svc.subtype !== 'postgres') {
    return (
      <div className="flex flex-col items-center justify-center py-16 text-center">
        <DatabaseBackup size={32} className="text-white/15" />
        <div className="mt-3 text-[13px] text-white/45">Point-in-time recovery is only available for PostgreSQL services.</div>
      </div>
    )
  }

  if (isLoading) {
    return <div className="py-16 text-center text-[12px] text-white/30">Loading PITR status…</div>
  }

  return (
    <div className="min-h-full bg-[#111114] px-5 py-4">
      <div className="mb-4">
        <div className="flex items-center gap-2 text-[14px] font-medium text-white/85">
          <DatabaseBackup size={15} className="text-[#8b5cf6]" />
          PostgreSQL point-in-time recovery
        </div>
        <p className="mt-1 text-[12px] text-white/35">Daily physical base backups plus continuous WAL archiving let you restore to any moment.</p>
      </div>

      {pitr?.enabled ? (
        <div className="rounded-lg border border-white/[0.07] bg-white/[0.02] p-4">
          <div className="flex items-start justify-between gap-4">
            <div>
              <div className="flex items-center gap-2 text-[13px] font-medium text-emerald-400">
                <ShieldCheck size={14} />
                Active
              </div>
              <div className="mt-1 text-[11px] text-white/35">
                Retention: {pitr.retentionDays} day{pitr.retentionDays === 1 ? '' : 's'}
              </div>
            </div>
            <div className="text-right text-[11px] text-white/35">
              <div>Last base backup</div>
              <div className="text-white/65">{formatDate(pitr.lastBaseBackupAt)}</div>
            </div>
          </div>

          <div className="mt-4 grid grid-cols-2 gap-3 border-t border-white/[0.06] pt-4">
            <div>
              <div className="text-[10px] uppercase tracking-[0.14em] text-white/25">Last WAL archived</div>
              <div className="mt-1 text-[12px] text-white/70">{formatDate(pitr.lastWalArchivedAt)}</div>
            </div>
            <div>
              <div className="text-[10px] uppercase tracking-[0.14em] text-white/25">Status</div>
              <div className="mt-1 flex items-center gap-1.5 text-[12px] text-white/70">
                {pitr.status === 'active' ? <ShieldCheck size={12} className="text-emerald-400" /> : pitr.status === 'error' ? <AlertCircle size={12} className="text-red-400" /> : <Clock size={12} className="text-amber-400" />}
                <span className="capitalize">{pitr.status}</span>
              </div>
            </div>
          </div>

          {pitr.lastError && (
            <div className="mt-4 rounded-md border border-red-400/20 bg-red-400/[0.04] p-3 text-[11px] text-red-300">
              <div className="flex items-center gap-1.5 font-medium">
                <AlertCircle size={12} />
                Last error
              </div>
              <div className="mt-1 text-white/50">{pitr.lastError}</div>
            </div>
          )}
        </div>
      ) : (
        <div className="rounded-lg border border-white/[0.07] bg-white/[0.02] p-4">
          <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <div className="flex items-center gap-2 text-[13px] font-medium text-white/65">
                <ShieldX size={14} className="text-white/35" />
                PITR is not enabled
              </div>
              <p className="mt-1 text-[11px] text-white/35">Choose an off-site destination for WAL archives and base backups.</p>
            </div>

            {destinations.length === 0 ? (
              <div className="text-[11px] text-amber-300">
                Add a verified destination first.
              </div>
            ) : (
              <Select
                value={selectedDestination}
                onValueChange={(value) => {
                  if (value) {
                    configurePitr.mutate({ id: serviceId, destinationId: value, retentionDays: 7 })
                    setSelectedDestination('')
                  }
                }}
                disabled={configurePitr.isPending}
              >
                <SelectTrigger className="w-full rounded-md border-0 bg-emerald-500/10 px-3 py-1.5 text-[10px] text-emerald-300 h-auto sm:w-auto sm:min-w-[180px]">
                  <SelectValue placeholder="Enable PITR" />
                </SelectTrigger>
                <SelectContent>
                  {destinations.map((destination: BackupDestination) => (
                    <SelectItem key={destination.id} value={destination.id}>{destination.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            )}
          </div>

          {configurePitr.isPending && (
            <div className="mt-4 flex items-center gap-2 text-[11px] text-white/45">
              <Loader2 size={12} className="animate-spin" />
              Configuring PostgreSQL WAL archiving…
            </div>
          )}
        </div>
      )}
    </div>
  )
}
