import { useState } from 'react'
import { ChevronRight, File, Folder, HardDrive, Loader2 } from 'lucide-react'
import { useBrowseStorageMount } from '@/hooks/useServices'
import type { StorageMountEntry } from '@/types'

function formatSize(bytes = 0) {
  if (!bytes) return '—'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  const unit = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1)
  return `${(bytes / 1024 ** unit).toFixed(unit ? 1 : 0)} ${units[unit]}`
}

export default function VolumeFileBrowser({ serviceId, storageMountId, containerPath }: { serviceId: string; storageMountId: string; containerPath: string }) {
  const [path, setPath] = useState('/')
  const { data, isLoading, isError } = useBrowseStorageMount(serviceId, storageMountId, path)

  const navigate = (name: string, type: string) => {
    if (type !== 'directory') return
    const next = path.replace(/\/$/, '') + '/' + name
    setPath(next || '/')
  }

  const goUp = () => {
    const parts = path.split('/').filter(Boolean)
    parts.pop()
    setPath('/' + parts.join('/'))
  }

  const entries = data?.entries ?? []
  const sorted = [...entries].sort((a, b) => {
    if (a.type === b.type) return a.name.localeCompare(b.name)
    return a.type === 'directory' ? -1 : 1
  })

  return (
    <div className="rounded-lg border border-white/[0.07] bg-[#17171b]">
      <div className="flex items-center gap-2 border-b border-white/[0.06] px-3 py-2">
        <HardDrive size={12} className="text-white/30" />
        <span className="text-[11px] text-white/50">{containerPath}</span>
        <ChevronRight size={12} className="text-white/20" />
        <span className="font-mono text-[11px] text-white/70">{path}</span>
        {path !== '/' && (
          <button onClick={goUp} className="ml-auto text-[10px] text-white/40 hover:text-white/70">
            Up
          </button>
        )}
      </div>

      <div className="max-h-64 overflow-auto">
        {isLoading ? (
          <div className="flex items-center justify-center gap-2 py-8 text-[11px] text-white/30">
            <Loader2 size={13} className="animate-spin" /> Reading volume…
          </div>
        ) : isError ? (
          <div className="py-8 text-center text-[11px] text-red-300">Could not read volume contents.</div>
        ) : sorted.length === 0 ? (
          <div className="py-8 text-center text-[11px] text-white/25">This directory is empty.</div>
        ) : (
          <ul className="divide-y divide-white/[0.04]">
            {sorted.map((entry: StorageMountEntry) => (
              <li key={entry.name}>
                <button
                  type="button"
                  onClick={() => navigate(entry.name, entry.type)}
                  disabled={entry.type !== 'directory'}
                  className="flex w-full items-center gap-2 px-3 py-2 text-left hover:bg-white/[0.03] disabled:cursor-default"
                >
                  {entry.type === 'directory' ? (
                    <Folder size={13} className="text-amber-300/70" />
                  ) : (
                    <File size={13} className="text-white/30" />
                  )}
                  <span className="flex-1 truncate font-mono text-[11px] text-white/65">{entry.name}</span>
                  <span className="text-[10px] text-white/25">{formatSize(entry.size)}</span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  )
}
