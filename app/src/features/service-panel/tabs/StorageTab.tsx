import { useMemo, useState } from 'react'
import { AlertTriangle, Archive, ChevronDown, ChevronRight, Database, FolderOpen, HardDrive, Link2, Plus, Search, Trash2, X } from 'lucide-react'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { useAddStorageMount, useRecovery, useRemoveStorageMount, useSnapshotVolume } from '@/hooks/useServices'
import VolumeFileBrowser from './VolumeFileBrowser'
import type { Service, StorageMount, StorageMountKind } from '@/types'

const STORAGE_KINDS: { value: StorageMountKind; label: string; description: string }[] = [
  { value: 'volume', label: 'Docker Volume', description: 'Managed and portable — recommended.' },
  { value: 'bind', label: 'Host Path', description: 'Absolute server path. Advanced only.' },
  { value: 'tmpfs', label: 'Tmpfs', description: 'In-memory. Lost on restart.' },
]

function kindLabel(kind: StorageMountKind) {
  return STORAGE_KINDS.find((k) => k.value === kind)?.label ?? kind
}

function autoVolumeName(service: Service, containerPath: string) {
  const suffix = containerPath
    .replace(/^\//, '')
    .replace(/[^a-zA-Z0-9_.-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .toLowerCase()
  return `${service.name}-${suffix || 'data'}`.replace(/[^a-zA-Z0-9_.-]+/g, '-')
}

export default function StorageTab({ svc }: { svc: Service }) {
  const addStorage = useAddStorageMount()
  const removeStorage = useRemoveStorageMount()
  const snapshotVolume = useSnapshotVolume()
  const { data: recovery } = useRecovery(svc.id)

  const [kind, setKind] = useState<StorageMountKind>('volume')
  const [hostPath, setHostPath] = useState('')
  const [containerPath, setContainerPath] = useState('')
  const [showAdvanced, setShowAdvanced] = useState(false)
  const [pendingRemoval, setPendingRemoval] = useState<StorageMount | null>(null)
  const [browsingMount, setBrowsingMount] = useState<StorageMount | null>(null)
  const [snapshotDestination, setSnapshotDestination] = useState('')

  const generatedHostPath = useMemo(() => {
    if (!containerPath) return ''
    return autoVolumeName(svc, containerPath)
  }, [containerPath, svc])

  const effectiveHostPath = hostPath || generatedHostPath
  const canSubmit = Boolean(containerPath) && Boolean(effectiveHostPath)

  const submit = (event: React.FormEvent) => {
    event.preventDefault()
    if (!canSubmit) return

    const payloadHostPath = kind === 'volume' ? effectiveHostPath : hostPath
    if (!payloadHostPath) return

    addStorage.mutate(
      { id: svc.id, hostPath: payloadHostPath, containerPath, kind },
      {
        onSuccess: () => {
          setHostPath('')
          setContainerPath('')
          setKind('volume')
          setShowAdvanced(false)
        },
      }
    )
  }

  return (
    <div className="min-h-full bg-[#111114]">
      <header className="border-b border-white/[0.06] px-5 py-4">
        <div className="flex items-center gap-2 text-[14px] font-medium text-white/85">
          <HardDrive size={15} className="text-[#8b5cf6]" /> Persistent storage
        </div>
        <p className="mt-1 max-w-xl text-[12px] leading-5 text-white/35">
          Mount a folder from your service so it survives redeploys and restarts.
        </p>
      </header>

      <section className="px-5 py-4">
        <div className="mb-2 flex items-center justify-between">
          <h3 className="text-[11px] font-medium uppercase tracking-[0.12em] text-white/35">Mounted paths</h3>
          {svc.storageMounts.length > 0 && (
            <div className="flex items-center gap-2">
              <Select value={snapshotDestination} onValueChange={(value) => setSnapshotDestination(value)}>
                <SelectTrigger aria-label="Snapshot destination" className="rounded border border-white/[0.07] bg-[#17171b] px-2 py-1 text-[10px] text-white/40">
                  <SelectValue placeholder="Local snapshots" />
                </SelectTrigger>
                <SelectContent>
                  {recovery?.destinations.map((item) => (
                    <SelectItem key={item.id} value={item.id}>
                      {item.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <span className="text-[10px] text-white/20">{svc.storageMounts.length} attached</span>
            </div>
          )}
        </div>

        {svc.storageMounts.length ? (
          <div className="divide-y divide-white/[0.05] rounded-lg border border-white/[0.05]">
            {svc.storageMounts.map((mount) => (
              <article key={`${mount.hostPath}:${mount.containerPath}`} className="grid grid-cols-[1fr_auto_1fr_auto] items-center gap-3 px-3 py-3">
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <Database size={13} className="text-white/25" />
                    <span className="truncate font-mono text-[11px] text-white/65">{mount.hostPath}</span>
                  </div>
                  <div className="mt-1 flex items-center gap-2 pl-5">
                    <span className="rounded bg-white/[0.05] px-1.5 py-0.5 text-[9px] font-medium text-white/40">
                      {kindLabel(mount.kind)}
                    </span>
                  </div>
                </div>
                <Link2 size={12} className="text-white/15" />
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <FolderOpen size={13} className="text-white/25" />
                    <span className="truncate font-mono text-[11px] text-white/65">{mount.containerPath}</span>
                  </div>
                  <div className="mt-1 pl-5 text-[10px] text-white/20">Container path</div>
                </div>
                <div className="flex items-center">
                  <button
                    type="button"
                    disabled={!mount.id || snapshotVolume.isPending}
                    onClick={() =>
                      snapshotVolume.mutate({
                        id: svc.id,
                        storageMountId: mount.id,
                        backupDestinationId: snapshotDestination || undefined,
                      })
                    }
                    aria-label={`Snapshot ${mount.hostPath}`}
                    className="rounded p-1.5 text-white/25 hover:bg-emerald-500/10 hover:text-emerald-400 disabled:opacity-30"
                  >
                    <Archive size={13} />
                  </button>
                  <button
                    type="button"
                    onClick={() => setBrowsingMount(mount)}
                    aria-label={`Browse ${mount.hostPath}`}
                    className="rounded p-1.5 text-white/25 hover:bg-[#8b5cf6]/10 hover:text-[#a78bfa]"
                  >
                    <Search size={13} />
                  </button>
                  <button
                    type="button"
                    onClick={() => setPendingRemoval(mount)}
                    aria-label={`Remove ${mount.hostPath}`}
                    className="rounded p-1.5 text-white/25 hover:bg-red-500/10 hover:text-red-400"
                  >
                    <Trash2 size={13} />
                  </button>
                </div>
              </article>
            ))}
          </div>
        ) : (
          <div className="rounded-lg border border-dashed border-white/[0.07] py-10 text-center text-[12px] text-white/30">
            No persistent mounts yet.
          </div>
        )}
      </section>

      <section className="px-5 pb-5">
        <h3 className="mb-2 text-[11px] font-medium uppercase tracking-[0.12em] text-white/35">Attach storage</h3>
        <form onSubmit={submit} className="rounded-lg border border-white/[0.07] bg-white/[0.02] p-4">
          <label className="block text-[11px] text-white/50">
            Container path
            <input
              value={containerPath}
              onChange={(event) => setContainerPath(event.target.value)}
              placeholder="/app/data"
              className="mt-1.5 block w-full rounded-md border border-white/[0.08] bg-[#17171b] px-3 py-2.5 font-mono text-[12px] text-white/70 placeholder:text-white/15 focus:outline-none focus:ring-1 focus:ring-[#8b5cf6]"
            />
          </label>

          {!showAdvanced && containerPath && (
            <div className="mt-2 flex items-center gap-2 text-[10px] text-white/30">
              <Database size={12} />
              <span>
                RailDock will create a Docker Volume named <span className="font-mono text-white/50">{generatedHostPath || '...'}</span>
              </span>
            </div>
          )}

          {showAdvanced && (
            <div className="mt-3 space-y-3 rounded-lg border border-white/[0.06] bg-[#17171b]/50 p-3">
              <label className="block text-[10px] text-white/40">
                Storage type
                <Select value={kind} onValueChange={(value) => setKind(value as StorageMountKind)}>
                  <SelectTrigger className="mt-1 h-9 w-full rounded-md border border-white/[0.08] bg-[#17171b] px-2.5 text-[11px] text-white/70 focus:outline-none focus:ring-1 focus:ring-[#8b5cf6]">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {STORAGE_KINDS.map((k) => (
                      <SelectItem key={k.value} value={k.value}>
                        <div className="flex flex-col">
                          <span className="text-[11px]">{k.label}</span>
                          <span className="text-[9px] text-white/40">{k.description}</span>
                        </div>
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </label>

              <label className="block text-[10px] text-white/40">
                {kind === 'volume' ? 'Volume name (override auto-generated)' : kind === 'bind' ? 'Host path' : 'Tmpfs mount point'}
                <input
                  value={hostPath}
                  onChange={(event) => setHostPath(event.target.value)}
                  placeholder={kind === 'volume' ? generatedHostPath || 'my-app-data' : kind === 'bind' ? '/mnt/data' : 'tmpfs'}
                  className="mt-1 block w-full rounded-md border border-white/[0.08] bg-[#17171b] px-2.5 py-2 font-mono text-[11px] text-white/70 placeholder:text-white/15 focus:outline-none focus:ring-1 focus:ring-[#8b5cf6]"
                />
              </label>

              <p className="text-[10px] leading-4 text-white/25">
                {kind === 'volume' && 'Docker Volumes are managed by RailDock and move with your app.'}
                {kind === 'bind' && 'Use an absolute path on the server. Only choose this if you need host-level access.'}
                {kind === 'tmpfs' && 'Tmpfs is stored in memory. Data is lost when the container stops.'}
              </p>
            </div>
          )}

          <div className="mt-4 flex items-center justify-between">
            <button
              type="button"
              onClick={() => setShowAdvanced((value) => !value)}
              className="inline-flex items-center gap-1 text-[11px] text-white/35 hover:text-white/55"
            >
              {showAdvanced ? <ChevronDown size={12} /> : <ChevronRight size={12} />}
              {showAdvanced ? 'Hide advanced options' : 'Advanced options'}
            </button>
            <button
              disabled={!canSubmit || addStorage.isPending}
              className="inline-flex items-center gap-1.5 rounded-md bg-[#8b5cf6] px-3 py-2 text-[11px] font-medium text-white hover:bg-[#7c4fe0] disabled:opacity-30"
            >
              <Plus size={12} /> Attach
            </button>
          </div>

          <div className="mt-3 flex items-start gap-2 rounded-md border border-amber-400/10 bg-amber-400/[0.03] px-3 py-2 text-[10px] leading-4 text-amber-200/50">
            <AlertTriangle size={12} className="mt-0.5 shrink-0 text-amber-300/50" />
            <span>Mounts take effect on the next deploy. Take a snapshot before changing mounts to avoid data loss.</span>
          </div>
        </form>
      </section>

      {pendingRemoval && (
        <div className="fixed inset-0 z-[90] flex items-center justify-center bg-black/70 p-4" role="dialog" aria-modal="true">
          <div className="w-full max-w-sm rounded-xl border border-white/[0.09] bg-[#19191d] p-5 shadow-2xl">
            <div className="flex items-center gap-2 text-red-300">
              <AlertTriangle size={16} />
              <h3 className="text-[14px] font-medium">Detach persistent storage?</h3>
            </div>
            <p className="mt-3 text-[12px] leading-5 text-white/40">
              The data on <span className="font-mono text-white/60">{pendingRemoval.hostPath}</span> is not deleted,
              but the service will lose access to{' '}
              <span className="font-mono text-white/60">{pendingRemoval.containerPath}</span>. A redeploy is required
              for the change to take effect.
            </p>
            <div className="mt-5 flex justify-end gap-2">
              <button onClick={() => setPendingRemoval(null)} className="rounded-md px-3 py-1.5 text-[11px] text-white/45 hover:bg-white/[0.05]">
                Cancel
              </button>
              <button
                onClick={() =>
                  removeStorage.mutate(
                    { id: svc.id, hostPath: pendingRemoval.hostPath },
                    { onSuccess: () => setPendingRemoval(null) }
                  )
                }
                className="rounded-md bg-red-500/15 px-3 py-1.5 text-[11px] text-red-300 hover:bg-red-500/25"
              >
                Detach
              </button>
            </div>
          </div>
        </div>
      )}

      {browsingMount && (
        <div className="fixed inset-0 z-[90] flex items-center justify-center bg-black/70 p-4" role="dialog" aria-modal="true">
          <div className="w-full max-w-xl rounded-xl border border-white/[0.09] bg-[#19191d] p-5 shadow-2xl">
            <div className="mb-4 flex items-center justify-between">
              <div>
                <h3 className="text-[14px] font-medium text-white/85">Browse volume</h3>
                <p className="mt-0.5 text-[11px] text-white/35">
                  {browsingMount.hostPath} → {browsingMount.containerPath}
                </p>
              </div>
              <button onClick={() => setBrowsingMount(null)} className="rounded p-1.5 text-white/25 hover:bg-white/[0.05]">
                <X size={14} />
              </button>
            </div>
            <VolumeFileBrowser serviceId={svc.id} storageMountId={browsingMount.id} containerPath={browsingMount.containerPath} />
          </div>
        </div>
      )}
    </div>
  )
}
