import { useMemo, useState } from 'react'
import { AlertTriangle, Archive, Database, FolderOpen, HardDrive, Link2, Plus, Search, Trash2, X } from 'lucide-react'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { useAddStorageMount, useRecovery, useRemoveStorageMount, useSnapshotVolume } from '@/hooks/useServices'
import VolumeFileBrowser from './VolumeFileBrowser'
import type { Service, StorageMount, StorageMountKind } from '@/types'

const STORAGE_KINDS: { value: StorageMountKind; label: string; description: string }[] = [
  { value: 'volume', label: 'Docker Volume', description: 'Managed, portable, and recommended for most apps.' },
  { value: 'bind', label: 'Host Path', description: 'Absolute path on the server. Advanced use only.' },
  { value: 'tmpfs', label: 'Tmpfs', description: 'In-memory storage. Lost when the container stops.' },
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

function containerPathHint(containerPath: string) {
  if (!containerPath) return null
  const relative = containerPath.replace(/^\//, '')
  return `Your app is built into /app. If it writes to ./${relative}, this mount will persist it.`
}

export default function StorageTab({ svc }: { svc: Service }) {
  const addStorage = useAddStorageMount()
  const removeStorage = useRemoveStorageMount()
  const snapshotVolume = useSnapshotVolume()
  const { data: recovery } = useRecovery(svc.id)

  const [kind, setKind] = useState<StorageMountKind>('volume')
  const [hostPath, setHostPath] = useState('')
  const [containerPath, setContainerPath] = useState('')
  const [pendingRemoval, setPendingRemoval] = useState<StorageMount | null>(null)
  const [browsingMount, setBrowsingMount] = useState<StorageMount | null>(null)
  const [snapshotDestination, setSnapshotDestination] = useState('')

  const generatedHostPath = useMemo(() => {
    if (kind !== 'volume' || hostPath) return hostPath
    if (!containerPath) return ''
    return autoVolumeName(svc, containerPath)
  }, [kind, hostPath, containerPath, svc])

  const submit = (event: React.FormEvent) => {
    event.preventDefault()
    if (!containerPath) return

    const payloadHostPath = kind === 'volume' ? generatedHostPath : hostPath
    if (!payloadHostPath) return

    addStorage.mutate(
      { id: svc.id, hostPath: payloadHostPath, containerPath, kind },
      {
        onSuccess: () => {
          setHostPath('')
          setContainerPath('')
          setKind('volume')
        },
      }
    )
  }

  const effectiveHostPath = kind === 'volume' ? generatedHostPath : hostPath

  return (
    <div className="min-h-full bg-[#111114]">
      <header className="border-b border-white/[0.06] px-5 py-4">
        <div className="flex items-center gap-2 text-[14px] font-medium text-white/85">
          <HardDrive size={15} className="text-[#8b5cf6]" /> Persistent storage
        </div>
        <p className="mt-1 max-w-xl text-[12px] leading-5 text-white/35">
          Mount durable storage into your service. Docker Volumes are recommended because they are managed by RailDock and move with your app.
        </p>
      </header>

      <div className="border-b border-amber-400/10 bg-amber-400/[0.035] px-5 py-3">
        <div className="flex gap-2 text-[11px] leading-5 text-amber-200/55">
          <AlertTriangle size={14} className="mt-0.5 shrink-0 text-amber-300/60" />
          <span>
            Persistent mounts affect rolling-deploy safety when old and new containers write concurrently. Prefer one writer, take a verified snapshot before changing mounts, and expect a brief restart when mounts change.
          </span>
        </div>
      </div>

      <section className="px-5 py-4">
        <div className="mb-2 flex items-center justify-between">
          <h3 className="text-[11px] font-medium uppercase tracking-[0.12em] text-white/35">Mounted paths</h3>
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
        </div>

        {svc.storageMounts.length ? (
          <div className="divide-y divide-white/[0.05] border-y border-white/[0.05]">
            {svc.storageMounts.map((mount) => (
              <article key={`${mount.hostPath}:${mount.containerPath}`} className="grid grid-cols-[1fr_auto_1fr_auto] items-center gap-3 py-3">
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <Database size={13} className="text-white/25" />
                    <span className="truncate font-mono text-[11px] text-white/65">{mount.hostPath}</span>
                  </div>
                  <div className="mt-1 flex items-center gap-2 pl-5">
                    <span className="rounded bg-white/[0.05] px-1.5 py-0.5 text-[9px] font-medium text-white/40">
                      {kindLabel(mount.kind)}
                    </span>
                    {mount.kind === 'bind' && <span className="text-[10px] text-white/20">Host path</span>}
                    {mount.kind === 'volume' && <span className="text-[10px] text-white/20">Named volume</span>}
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
                    className="rounded p-1.5 text-white/25 hover:bg-[#8b5cf6]/10 hover:text-[#a78bfa] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#8b5cf6]"
                  >
                    <Search size={13} />
                  </button>
                  <button
                    type="button"
                    onClick={() => setPendingRemoval(mount)}
                    aria-label={`Remove ${mount.hostPath}`}
                    className="rounded p-1.5 text-white/25 hover:bg-red-500/10 hover:text-red-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-400"
                  >
                    <Trash2 size={13} />
                  </button>
                </div>
              </article>
            ))}
          </div>
        ) : (
          <div className="border-y border-dashed border-white/[0.07] py-10 text-center text-[12px] text-white/30">
            No persistent mounts attached.
          </div>
        )}
      </section>

      <section className="px-5 pb-5">
        <h3 className="mb-2 text-[11px] font-medium uppercase tracking-[0.12em] text-white/35">Attach storage</h3>
        <form onSubmit={submit} className="rounded-lg border border-white/[0.07] bg-white/[0.02] p-3">
          <div className="mb-3 grid grid-cols-[1fr_1fr] gap-2">
            <label className="text-[10px] text-white/35">
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

            <label className="text-[10px] text-white/35">
              {kind === 'volume' ? 'Volume name (auto-generated)' : kind === 'bind' ? 'Host path' : 'Tmpfs path'}
              <input
                value={effectiveHostPath}
                onChange={(event) => setHostPath(event.target.value)}
                placeholder={kind === 'volume' ? 'my-app-data' : kind === 'bind' ? '/mnt/data' : 'tmpfs'}
                className="mt-1 block w-full rounded-md border border-white/[0.08] bg-[#17171b] px-2.5 py-2 font-mono text-[11px] text-white/70 placeholder:text-white/15 focus:outline-none focus:ring-1 focus:ring-[#8b5cf6]"
              />
            </label>
          </div>

          <label className="mb-3 block text-[10px] text-white/35">
            Container path
            <input
              value={containerPath}
              onChange={(event) => setContainerPath(event.target.value)}
              placeholder="/app/data"
              className="mt-1 block w-full rounded-md border border-white/[0.08] bg-[#17171b] px-2.5 py-2 font-mono text-[11px] text-white/70 placeholder:text-white/15 focus:outline-none focus:ring-1 focus:ring-[#8b5cf6]"
            />
            {containerPathHint(containerPath) && (
              <span className="mt-1.5 block text-[10px] leading-4 text-white/25">{containerPathHint(containerPath)}</span>
            )}
          </label>

          <div className="flex items-center justify-between">
            <p className="max-w-md text-[10px] leading-4 text-white/25">
              {kind === 'volume' && 'RailDock will create the Docker volume for you. Leave the name blank to auto-generate one from the container path.'}
              {kind === 'bind' && 'The host path must already exist or Dokku will create it. Use absolute paths only.'}
              {kind === 'tmpfs' && 'Tmpfs mounts are useful for caches but data is lost on restart.'}
            </p>
            <button
              disabled={!effectiveHostPath || !containerPath || addStorage.isPending}
              className="inline-flex items-center gap-1.5 rounded-md bg-white/[0.08] px-3 py-2 text-[11px] text-white/70 hover:bg-white/[0.12] disabled:opacity-30"
            >
              <Plus size={12} /> Attach
            </button>
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
              <button
                onClick={() => setPendingRemoval(null)}
                className="rounded-md px-3 py-1.5 text-[11px] text-white/45 hover:bg-white/[0.05]"
              >
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
              <button
                onClick={() => setBrowsingMount(null)}
                className="rounded p-1.5 text-white/25 hover:bg-white/[0.05]"
              >
                <X size={14} />
              </button>
            </div>
            <VolumeFileBrowser
              serviceId={svc.id}
              storageMountId={browsingMount.id}
              containerPath={browsingMount.containerPath}
            />
          </div>
        </div>
      )}
    </div>
  )
}
