import { useState } from 'react'
import { HardDrive, Trash2 } from 'lucide-react'
import { useAddStorageMount, useRemoveStorageMount } from '@/hooks/useServices'
import type { Service } from '@/types'

export default function StorageTab({ svc }: { svc: Service }) {
  const addStorage = useAddStorageMount()
  const removeStorage = useRemoveStorageMount()
  const [newHostPath, setNewHostPath] = useState('')
  const [newContainerPath, setNewContainerPath] = useState('')

  return (
    <div className="p-5 space-y-4">
      <div className="text-[14px] font-medium text-white/70 mb-2">Storage Mounts</div>
      {svc.storageMounts.length > 0 ? (
        <div className="space-y-2">
          {svc.storageMounts.map((sm) => (
            <div
              key={sm.hostPath}
              className="flex items-center gap-3 bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3 group"
            >
              <HardDrive size={15} className="text-white/30" />
              <div className="text-[12px] text-white/50 font-mono">
                {sm.hostPath} → {sm.containerPath}
              </div>
              <button
                onClick={() => removeStorage.mutate({ id: svc.id, hostPath: sm.hostPath })}
                className="ml-auto p-1.5 hover:bg-white/[0.06] rounded text-white/20 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity"
              >
                <Trash2 size={12} />
              </button>
            </div>
          ))}
        </div>
      ) : (
        <div className="text-[13px] text-white/30 py-4 text-center">No storage mounts configured</div>
      )}
      <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3 space-y-2">
        <div className="text-[12px] text-white/50 mb-1">Add Mount</div>
        <div className="flex gap-2">
          <input
            type="text"
            placeholder="/var/lib/dokku/data/storage/..."
            value={newHostPath}
            onChange={(e) => setNewHostPath(e.target.value)}
            className="flex-1 bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] font-mono text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
          />
          <input
            type="text"
            placeholder="/app/data"
            value={newContainerPath}
            onChange={(e) => setNewContainerPath(e.target.value)}
            className="flex-1 bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] font-mono text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
          />
          <button
            onClick={() => {
              if (newHostPath && newContainerPath) {
                addStorage.mutate({ id: svc.id, hostPath: newHostPath, containerPath: newContainerPath })
                setNewHostPath('')
                setNewContainerPath('')
              }
            }}
            className="px-3 py-1.5 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[12px] hover:bg-[#8b5cf6]/25 transition-all"
          >
            Add
          </button>
        </div>
      </div>
    </div>
  )
}
