import { useMemo, useState } from 'react'
import { AlertTriangle, Archive, ChevronDown, ChevronRight, Database, FolderOpen, Link2, Plus, Search, Trash2 } from 'lucide-react'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { IconButton } from '@/components/ui/icon-button'
import ConfirmDialog from '@/features/shared/ConfirmDialog'
import { useAddStorageMount, useRemoveStorageMount, useSnapshotVolume } from '@/hooks/useServices'
import VolumeFileBrowser from './VolumeFileBrowser'
import type { Service, StorageMount, StorageMountKind } from '@/types'

const STORAGE_KINDS: { value: StorageMountKind; label: string; description: string }[] = [
  { value: 'volume', label: 'Docker Volume', description: 'Managed and portable — recommended.' },
  { value: 'bind', label: 'Host Path', description: 'Absolute server path. Advanced only.' },
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

  const [kind, setKind] = useState<StorageMountKind>('volume')
  const [hostPath, setHostPath] = useState('')
  const [containerPath, setContainerPath] = useState('')
  const [showAdvanced, setShowAdvanced] = useState(false)
  const [pendingRemoval, setPendingRemoval] = useState<StorageMount | null>(null)
  const [browsingMount, setBrowsingMount] = useState<StorageMount | null>(null)

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
      <header className="border-b border-white/6 px-5 py-4">
        <h2 className="text-[14px] font-medium text-white/85">Volumes</h2>
        <p className="mt-1 max-w-xl text-[12px] leading-5 text-white/40">
          Folders that survive redeploys and restarts. A snapshot goes to the same destinations as this service's backups.
        </p>
      </header>

      <section className="px-5 py-4">
        <div className="mb-2 flex items-center justify-between">
          <h3 className="text-[12px] font-medium text-white/70">Mounted paths</h3>
          {svc.storageMounts.length > 0 && <span className="text-[11px] text-white/35">{svc.storageMounts.length} attached</span>}
        </div>

        {svc.storageMounts.length ? (
          <div className="divide-y divide-white/5 rounded-lg border border-white/5">
            {svc.storageMounts.map((mount) => (
              <article key={`${mount.hostPath}:${mount.containerPath}`} className="grid grid-cols-[1fr_auto_1fr_auto] items-center gap-3 px-3 py-3">
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <Database size={13} className="text-white/25" />
                    <span className="truncate font-mono text-[11px] text-white/65">{mount.hostPath}</span>
                  </div>
                  <div className="mt-1 flex items-center gap-2 pl-5">
                    <span className="rounded bg-white/5 px-1.5 py-0.5 text-[9px] font-medium text-white/50">
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
                  <IconButton
                    title={`Snapshot ${mount.containerPath} now`}
                    disabled={!mount.id || snapshotVolume.isPending}
                    onClick={() => snapshotVolume.mutate({ id: svc.id, storageMountId: mount.id })}
                    className="hover:bg-emerald-500/10 hover:text-emerald-400"
                  >
                    <Archive />
                  </IconButton>
                  <IconButton title={`Browse ${mount.containerPath}`} onClick={() => setBrowsingMount(mount)}>
                    <Search />
                  </IconButton>
                  <IconButton
                    title={`Detach ${mount.containerPath}`}
                    onClick={() => setPendingRemoval(mount)}
                    className="hover:bg-red-500/10 hover:text-red-400"
                  >
                    <Trash2 />
                  </IconButton>
                </div>
              </article>
            ))}
          </div>
        ) : (
          <div className="rounded-lg border border-dashed border-white/[0.07] py-10 text-center text-[12px] text-white/50">
            No persistent mounts yet.
          </div>
        )}
      </section>

      <section className="px-5 pb-5">
        <h3 className="mb-2 text-[12px] font-medium text-white/70">Attach a volume</h3>
        <form onSubmit={submit} className="rounded-lg border border-white/[0.07] bg-white/2 p-4">
          <label className="block text-[11px] text-white/50">
            Container path
            <input
              value={containerPath}
              onChange={(event) => setContainerPath(event.target.value)}
              placeholder="/app/data"
              className="mt-1.5 block w-full rounded-md border border-white/8 bg-[#17171b] px-3 py-2.5 font-mono text-[12px] text-white/70 placeholder:text-white/15 focus:outline-hidden focus:ring-1 focus:ring-rail-purple"
            />
          </label>

          {!showAdvanced && containerPath && (
            <div className="mt-2 flex items-center gap-2 text-[10px] text-white/50">
              <Database size={12} />
              <span>
                RailDock will create a Docker Volume named <span className="font-mono text-white/50">{generatedHostPath || '...'}</span>
              </span>
            </div>
          )}

          {showAdvanced && (
            <div className="mt-3 space-y-3 rounded-lg border border-white/6 bg-[#17171b]/50 p-3">
              <label className="block text-[10px] text-white/50">
                Storage type
                <Select value={kind} onValueChange={(value) => setKind(value as StorageMountKind)}>
                  <SelectTrigger className="mt-1 h-9 w-full rounded-md border border-white/8 bg-[#17171b] px-2.5 text-[11px] text-white/70 focus:outline-hidden focus:ring-1 focus:ring-rail-purple">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {STORAGE_KINDS.map((k) => (
                      <SelectItem key={k.value} value={k.value}>
                        <div className="flex flex-col">
                          <span className="text-[11px]">{k.label}</span>
                          <span className="text-[9px] text-white/50">{k.description}</span>
                        </div>
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </label>

              <label className="block text-[10px] text-white/50">
                {kind === 'volume' ? 'Volume name (override auto-generated)' : 'Host path'}
                <input
                  value={hostPath}
                  onChange={(event) => setHostPath(event.target.value)}
                  placeholder={kind === 'volume' ? generatedHostPath || 'my-app-data' : '/mnt/data'}
                  className="mt-1 block w-full rounded-md border border-white/8 bg-[#17171b] px-2.5 py-2 font-mono text-[11px] text-white/70 placeholder:text-white/15 focus:outline-hidden focus:ring-1 focus:ring-rail-purple"
                />
              </label>

              <p className="text-[10px] leading-4 text-white/25">
                {kind === 'volume' && 'Docker Volumes are managed by RailDock and move with your app.'}
                {kind === 'bind' && 'Use an absolute path on the server. Only choose this if you need host-level access.'}
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
              className="inline-flex items-center gap-1.5 rounded-md bg-rail-purple px-3 py-2 text-[11px] font-medium text-white hover:bg-rail-purple-dark disabled:opacity-30"
            >
              <Plus size={12} /> Attach
            </button>
          </div>

          <div className="mt-3 flex items-start gap-2 rounded-md border border-amber-400/10 bg-amber-400/3 px-3 py-2 text-[10px] leading-4 text-amber-200/50">
            <AlertTriangle size={12} className="mt-0.5 shrink-0 text-amber-300/50" />
            <span>Mounts take effect on the next deploy. Take a snapshot before changing mounts to avoid data loss.</span>
          </div>
        </form>
      </section>

      <ConfirmDialog
        open={pendingRemoval !== null}
        onOpenChange={(open) => { if (!open) setPendingRemoval(null) }}
        title="Detach this volume?"
        description={
          pendingRemoval && (
            <>
              The data in <span className="font-mono text-white/70">{pendingRemoval.hostPath}</span> is kept, but the service
              loses access to <span className="font-mono text-white/70">{pendingRemoval.containerPath}</span> on its next deploy.
            </>
          )
        }
        confirmLabel="Detach"
        destructive
        pending={removeStorage.isPending}
        onConfirm={() => {
          if (!pendingRemoval) return
          removeStorage.mutate({ id: svc.id, hostPath: pendingRemoval.hostPath }, { onSuccess: () => setPendingRemoval(null) })
        }}
      />

      <Dialog open={browsingMount !== null} onOpenChange={(open) => { if (!open) setBrowsingMount(null) }}>
        <DialogContent className="border-white/9 bg-[#19191d] text-white sm:max-w-xl">
          <DialogHeader>
            <DialogTitle className="text-[14px]">Browse volume</DialogTitle>
            <DialogDescription className="text-[11px] text-white/40">
              {browsingMount?.hostPath} → {browsingMount?.containerPath}
            </DialogDescription>
          </DialogHeader>
          {browsingMount && (
            <VolumeFileBrowser serviceId={svc.id} storageMountId={browsingMount.id} containerPath={browsingMount.containerPath} />
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}
