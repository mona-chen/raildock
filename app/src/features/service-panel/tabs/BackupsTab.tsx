import { useRef } from 'react'
import {
  ArrowDownToLine,
  Loader2,
  Upload,
  AlertCircle,
  Clock,
  CheckCircle2,
  XCircle,
  HardDrive,
  Trash2,
} from 'lucide-react'
import { useBackups, useBackupService, useRestoreService } from '@/hooks/useServices'
import type { Service } from '@/types'

function formatSize(bytes: number): string {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i]
}

export default function BackupsTab({ svc, serviceId }: { svc: Service; serviceId: string }) {
  const { data: backups, isLoading, isError, refetch } = useBackups(serviceId)
  const backupService = useBackupService()
  const restoreService = useRestoreService()
  const fileInputRef = useRef<HTMLInputElement>(null)

  const handleRestoreClick = () => {
    fileInputRef.current?.click()
  }

  const handleFileSelected = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    restoreService.mutate({ id: serviceId, file })
    e.target.value = ''
  }

  const handleCreateBackup = () => {
    backupService.mutate(serviceId, {
      onSuccess: () => refetch(),
    })
  }

  return (
    <div className="p-5 space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <div className="text-[14px] font-medium text-white/70">Backups</div>
          <div className="text-[12px] text-white/40 mt-0.5">
            {backups?.length ?? svc.backups.length} backup(s) available
          </div>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={handleRestoreClick}
            disabled={restoreService.isPending}
            className="flex items-center gap-1.5 px-3 py-2 bg-white/[0.06] text-white/60 rounded-lg text-[12px] hover:bg-white/[0.1] transition-all disabled:opacity-50"
            title="Restore from backup file"
          >
            <Upload size={13} />
            {restoreService.isPending ? 'Restoring...' : 'Restore'}
          </button>
          <input
            ref={fileInputRef}
            type="file"
            accept=".sql,.dump,.gz,.zip"
            className="hidden"
            onChange={handleFileSelected}
          />
          <button
            onClick={handleCreateBackup}
            disabled={backupService.isPending}
            className="flex items-center gap-1.5 px-3 py-2 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[12px] hover:bg-[#8b5cf6]/25 transition-all disabled:opacity-50"
          >
            {backupService.isPending ? (
              <Loader2 size={13} className="animate-spin" />
            ) : (
              <ArrowDownToLine size={13} />
            )}
            {backupService.isPending ? 'Creating...' : 'Create Backup'}
          </button>
        </div>
      </div>

      {isLoading ? (
        <div className="space-y-2">
          {[1, 2, 3].map((i) => (
            <div
              key={i}
              className="flex items-center gap-3 bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3 animate-pulse"
            >
              <div className="flex-1 space-y-2">
                <div className="h-3.5 bg-white/5 rounded w-32" />
                <div className="h-2.5 bg-white/5 rounded w-48" />
              </div>
              <div className="h-5 bg-white/5 rounded w-16" />
              <div className="h-4 bg-white/5 rounded w-12" />
            </div>
          ))}
        </div>
      ) : isError ? (
        <div className="text-center py-12">
          <AlertCircle size={24} className="mx-auto text-red-400/60 mb-2" />
          <div className="text-[13px] text-white/40">Failed to load backups</div>
          <button
            onClick={() => refetch()}
            className="mt-2 text-[12px] text-[#8b5cf6] hover:text-[#8b5cf6]/80"
          >
            Retry
          </button>
        </div>
      ) : (backups && backups.length > 0) || svc.backups.length > 0 ? (
        <div className="space-y-2">
          {(backups || svc.backups).map((b) => {
            const statusConfig = {
              completed: { icon: CheckCircle2, color: 'text-[#22c55e]', bg: 'bg-[#22c55e]/10' },
              success: { icon: CheckCircle2, color: 'text-[#22c55e]', bg: 'bg-[#22c55e]/10' },
              failed: { icon: XCircle, color: 'text-red-400', bg: 'bg-red-400/10' },
              pending: { icon: Loader2, color: 'text-amber-400', bg: 'bg-amber-400/10' },
              running: { icon: Loader2, color: 'text-[#8b5cf6]', bg: 'bg-[#8b5cf6]/10' },
            }
            const config = statusConfig[b.status as keyof typeof statusConfig] || statusConfig.pending
            const StatusIcon = config.icon
            const sizeNum = typeof b.size === 'number' ? b.size : parseInt(b.size as string) || 0

            return (
              <div
                key={b.id}
                className="flex items-center gap-3 bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3 group"
              >
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <div className="text-[13px] text-white/70 truncate">
                      Backup {String(b.id).slice(0, 8)}
                    </div>
                    <span
                      className={`inline-flex items-center gap-1 text-[11px] px-2 py-0.5 rounded-full ${config.bg} ${config.color}`}
                    >
                      <StatusIcon
                        size={11}
                        className={b.status === 'pending' || b.status === 'running' ? 'animate-spin' : ''}
                      />
                      {b.status}
                    </span>
                  </div>
                  <div className="flex items-center gap-3 mt-0.5">
                    <span className="text-[11px] text-white/40 flex items-center gap-1">
                      <Clock size={10} />
                      {new Date(b.createdAt).toLocaleString()}
                    </span>
                    <span className="text-[11px] text-white/40 font-mono">{formatSize(sizeNum)}</span>
                  </div>
                </div>
                <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                  <button
                    type="button"
                    disabled
                    className="p-1.5 hover:bg-white/[0.06] rounded text-white/30 hover:text-white/60 disabled:opacity-30 disabled:cursor-not-allowed"
                    title="Download (coming soon)"
                    aria-label="Download backup"
                  >
                    <ArrowDownToLine size={13} />
                  </button>
                  <button
                    type="button"
                    disabled
                    className="p-1.5 hover:bg-white/[0.06] rounded text-white/30 hover:text-red-400 disabled:opacity-30 disabled:cursor-not-allowed"
                    title="Delete (coming soon)"
                    aria-label="Delete backup"
                  >
                    <Trash2 size={13} />
                  </button>
                </div>
              </div>
            )
          })}
        </div>
      ) : (
        <div className="text-center py-12 border border-dashed border-white/[0.08] rounded-xl">
          <HardDrive size={28} className="mx-auto text-white/15 mb-3" />
          <div className="text-[13px] text-white/40 font-medium">No backups yet</div>
          <div className="text-[12px] text-white/25 mt-1">Create your first backup to protect your data.</div>
        </div>
      )}
    </div>
  )
}
