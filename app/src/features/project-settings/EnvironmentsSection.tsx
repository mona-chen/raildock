import { useState } from 'react'
import { Check, Copy, Layers, Loader2, Pencil, Plus, RefreshCw, Trash2, X } from 'lucide-react'
import {
  useCreateEnvironment,
  useDestroyEnvironment,
  useEnvironments,
  useUpdateEnvironment,
} from '@/hooks/useEnvironments'
import DuplicateEnvironmentDialog from '@/features/environments/DuplicateEnvironmentDialog'
import SyncEnvironmentDialog from '@/features/environments/SyncEnvironmentDialog'
import type { Environment } from '@/types'

/**
 * Project Settings → Environments.
 *
 * Railway, Coolify and Dokploy all treat the default environment as permanent
 * and refuse to delete an environment that still owns services. RailDock
 * mirrors that: `production` is listed first and locked, and a non-empty
 * environment can only be removed after its services are moved.
 */
export default function EnvironmentsSection({ projectId }: { projectId: string }) {
  const { data: environments = [], isLoading, isError, refetch } = useEnvironments(projectId)
  const createEnvironment = useCreateEnvironment()
  const updateEnvironment = useUpdateEnvironment()
  const destroyEnvironment = useDestroyEnvironment()

  const [showCreate, setShowCreate] = useState(false)
  const [newName, setNewName] = useState('')
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editName, setEditName] = useState('')
  const [duplicateSource, setDuplicateSource] = useState<Environment | null>(null)
  const [syncTarget, setSyncTarget] = useState<Environment | null>(null)

  const handleCreate = () => {
    const trimmed = newName.trim()
    if (!trimmed) return
    createEnvironment.mutate(
      { projectId, data: { name: trimmed } },
      {
        onSuccess: () => {
          setNewName('')
          setShowCreate(false)
        },
      },
    )
  }

  const startEditing = (environment: Environment) => {
    setEditingId(environment.id)
    setEditName(environment.name)
  }

  const commitEdit = () => {
    if (!editingId) return
    const trimmed = editName.trim()
    if (!trimmed) {
      setEditingId(null)
      return
    }
    updateEnvironment.mutate(
      { projectId, id: editingId, data: { name: trimmed } },
      { onSuccess: () => setEditingId(null) },
    )
  }

  return (
    <section className="overflow-hidden rounded-xl border border-white/[0.06] bg-[#16161a]">
      <div className="flex items-start gap-3 border-b border-white/[0.06] p-4">
        <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-rail-purple/10">
          <Layers size={17} className="text-rail-purple" />
        </div>
        <div className="min-w-0 flex-1">
          <h2 className="text-sm font-medium text-white">Environments</h2>
          <p className="mt-1 text-[11px] text-white/35">
            Isolated copies of this project&apos;s services and configuration. Copy one with{' '}
            <span className="text-white/55">duplicate</span>, or pull its services into another with{' '}
            <span className="text-white/55">sync</span>. Every project starts with a permanent{' '}
            <span className="text-white/55">production</span> environment.
          </p>
        </div>
        <button
          type="button"
          onClick={() => setShowCreate((value) => !value)}
          className="flex shrink-0 items-center gap-1.5 rounded-lg bg-rail-purple px-2.5 py-1.5 text-[11px] font-medium text-white transition-colors hover:bg-rail-purple-dark"
        >
          <Plus size={12} /> New environment
        </button>
      </div>

      {showCreate && (
        <div className="flex items-center gap-2 border-b border-white/[0.06] bg-black/15 p-3">
          <input
            autoFocus
            value={newName}
            onChange={(event) => setNewName(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === 'Enter') handleCreate()
              if (event.key === 'Escape') setShowCreate(false)
            }}
            placeholder="staging"
            aria-label="New environment name"
            className="flex-1 rounded-lg border border-white/[0.08] bg-black/30 px-3 py-2 text-[12px] text-white/80 outline-none focus:border-rail-purple/50"
          />
          <button
            type="button"
            onClick={handleCreate}
            disabled={!newName.trim() || createEnvironment.isPending}
            className="rounded-lg bg-rail-purple px-3 py-2 text-[11px] font-medium text-white transition-colors hover:bg-rail-purple-dark disabled:opacity-40"
          >
            {createEnvironment.isPending ? 'Creating…' : 'Create'}
          </button>
          <button
            type="button"
            onClick={() => setShowCreate(false)}
            className="rounded-lg p-2 text-white/35 transition-colors hover:bg-white/[0.05] hover:text-white/60"
            aria-label="Cancel"
          >
            <X size={13} />
          </button>
        </div>
      )}

      {isLoading ? (
        <div className="flex items-center gap-2 p-4 text-[12px] text-white/40">
          <Loader2 size={13} className="animate-spin" /> Loading environments…
        </div>
      ) : isError ? (
        <button
          type="button"
          onClick={() => refetch()}
          className="w-full p-4 text-left text-[12px] text-red-400 hover:text-red-300"
        >
          Could not load environments — retry
        </button>
      ) : (
        <ul className="divide-y divide-white/[0.05]">
          {environments.map((environment) => {
            const serviceCount = environment.serviceCount ?? 0
            const canDelete = !environment.isDefault && serviceCount === 0
            return (
              <li key={environment.id} className="flex items-center gap-3 px-4 py-3">
                {editingId === environment.id ? (
                  <>
                    <input
                      autoFocus
                      value={editName}
                      onChange={(event) => setEditName(event.target.value)}
                      onKeyDown={(event) => {
                        if (event.key === 'Enter') commitEdit()
                        if (event.key === 'Escape') setEditingId(null)
                      }}
                      aria-label={`Rename ${environment.name}`}
                      className="flex-1 rounded-lg border border-white/[0.08] bg-black/30 px-2.5 py-1.5 text-[12px] text-white/80 outline-none focus:border-rail-purple/50"
                    />
                    <button
                      type="button"
                      onClick={commitEdit}
                      className="rounded p-1.5 text-emerald-400 hover:bg-emerald-500/10"
                      aria-label="Save name"
                    >
                      <Check size={13} />
                    </button>
                    <button
                      type="button"
                      onClick={() => setEditingId(null)}
                      className="rounded p-1.5 text-white/35 hover:bg-white/[0.06]"
                      aria-label="Cancel rename"
                    >
                      <X size={13} />
                    </button>
                  </>
                ) : (
                  <>
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2">
                        <span className="truncate text-[12.5px] text-white/80">{environment.name}</span>
                        {environment.isDefault && (
                          <span className="rounded bg-white/[0.06] px-1.5 py-0.5 text-[9px] uppercase tracking-wide text-white/40">
                            default
                          </span>
                        )}
                      </div>
                      <div className="mt-0.5 text-[10px] text-white/25">
                        {serviceCount} service{serviceCount === 1 ? '' : 's'}
                        {environment.description ? ` · ${environment.description}` : ''}
                      </div>
                    </div>
                    <button
                      type="button"
                      onClick={() => setDuplicateSource(environment)}
                      title={`Copy every service in ${environment.name} into a new environment`}
                      className="rounded p-1.5 text-white/30 transition-colors hover:bg-white/[0.06] hover:text-white/70"
                      aria-label={`Duplicate ${environment.name}`}
                    >
                      <Copy size={12} />
                    </button>
                    <button
                      type="button"
                      disabled={environments.length < 2}
                      onClick={() => setSyncTarget(environment)}
                      title={
                        environments.length < 2
                          ? 'Create another environment before syncing'
                          : `Pull another environment's services into ${environment.name}`
                      }
                      className="rounded p-1.5 text-white/30 transition-colors hover:bg-white/[0.06] hover:text-white/70 disabled:cursor-not-allowed disabled:opacity-25 disabled:hover:bg-transparent disabled:hover:text-white/30"
                      aria-label={`Sync ${environment.name}`}
                    >
                      <RefreshCw size={12} />
                    </button>
                    <button
                      type="button"
                      onClick={() => startEditing(environment)}
                      className="rounded p-1.5 text-white/30 transition-colors hover:bg-white/[0.06] hover:text-white/70"
                      aria-label={`Rename ${environment.name}`}
                    >
                      <Pencil size={12} />
                    </button>
                    <button
                      type="button"
                      disabled={!canDelete || destroyEnvironment.isPending}
                      onClick={() => destroyEnvironment.mutate({ projectId, id: environment.id })}
                      title={
                        environment.isDefault
                          ? 'The default environment cannot be deleted'
                          : serviceCount > 0
                            ? 'Move this environment’s services before deleting it'
                            : 'Delete environment'
                      }
                      className="rounded p-1.5 text-white/30 transition-colors hover:bg-red-500/10 hover:text-red-400 disabled:cursor-not-allowed disabled:opacity-25 disabled:hover:bg-transparent disabled:hover:text-white/30"
                      aria-label={`Delete ${environment.name}`}
                    >
                      <Trash2 size={12} />
                    </button>
                  </>
                )}
              </li>
            )
          })}
        </ul>
      )}

      <DuplicateEnvironmentDialog
        projectId={projectId}
        source={duplicateSource}
        environments={environments}
        open={duplicateSource !== null}
        onOpenChange={(open) => { if (!open) setDuplicateSource(null) }}
      />
      <SyncEnvironmentDialog
        projectId={projectId}
        target={syncTarget}
        environments={environments}
        open={syncTarget !== null}
        onOpenChange={(open) => { if (!open) setSyncTarget(null) }}
      />
    </section>
  )
}
