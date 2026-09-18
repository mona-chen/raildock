import { useEffect, useState } from 'react'
import { Folder, Plus, Search, Box, Trash2 } from 'lucide-react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { useProjects, useCreateProject, useDestroyProject } from '@/hooks/useProjects'

import { useCanvasStore } from '@/stores/useCanvasStore'
import OnboardingChecklist from '@/components/OnboardingChecklist'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { SkeletonCard } from '@/components/ui/skeleton'
import ErrorState from '@/features/shared/ErrorState'
import EmptyState from '@/features/shared/EmptyState'
import { cn, confirmationFieldTone } from '@/lib/utils'

export default function ProjectsPage() {
  const navigate = useNavigate()
  const { data: projects = [], isLoading, isError, refetch } = useProjects()
  const createProject = useCreateProject()
  const destroyProject = useDestroyProject()
  const setActiveProject = useCanvasStore((s) => s.setActiveService)

  const [search, setSearch] = useState('')
  const [showCreate, setShowCreate] = useState(false)
  const [searchParams, setSearchParams] = useSearchParams()
  const [newName, setNewName] = useState('')
  const [newDesc, setNewDesc] = useState('')
  const [newEnv, setNewEnv] = useState<'production' | 'staging' | 'development'>('production')

  const filtered = projects.filter((p) =>
    p.name.toLowerCase().includes(search.toLowerCase()) ||
    p.description.toLowerCase().includes(search.toLowerCase())
  )

  // The command palette deep-links here with ?new=1 to open the create dialog.
  useEffect(() => {
    if (searchParams.get('new') !== '1') return
    setShowCreate(true)
    const next = new URLSearchParams(searchParams)
    next.delete('new')
    setSearchParams(next, { replace: true })
  }, [searchParams, setSearchParams])

  const handleOpenProject = (id: string) => {
    setActiveProject(null)
    navigate(`/dashboard/project/${id}`)
  }

  const handleCreate = () => {
    if (!newName.trim()) return
    createProject.mutate({ name: newName, description: newDesc, environment: newEnv }, {
      onSuccess: () => {
        setNewName('')
        setNewDesc('')
        setNewEnv('production')
        setShowCreate(false)
      },
    })
  }

  return (
    <div className="min-h-full p-8">
      <div className="max-w-5xl mx-auto">
        <OnboardingChecklist />
        <div className="flex items-center justify-between mb-8">
          <div>
            <h1 className="text-2xl font-bold text-white mb-1">Projects</h1>
            <p className="text-sm text-[#6b6b7b]">Manage your applications and services</p>
          </div>
          <button
            onClick={() => setShowCreate(true)}
            className="flex items-center gap-2 px-4 py-2.5 bg-rail-purple text-white text-sm font-medium rounded-xl hover:bg-rail-purple-dark transition-all"
          >
            <Plus size={16} /> New Project
          </button>
        </div>

        <div className="flex items-center bg-[rgba(255,255,255,0.04)] border border-[rgba(255,255,255,0.06)] rounded-xl px-4 py-2.5 gap-3 max-w-md mb-6">
          <Search size={16} className="text-[#6b6b7b]" />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search projects..."
            className="bg-transparent text-sm text-white placeholder-[#6b6b7b] outline-none w-full"
          />
        </div>

        {isLoading ? (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {Array.from({ length: 3 }).map((_, i) => (
              <SkeletonCard key={i} className="h-40" />
            ))}
          </div>
        ) : isError ? (
          <ErrorState
            title="Couldn't load projects"
            message="RailDock could not reach the API. Your projects are unaffected — retry to load them."
            onRetry={() => refetch()}
          />
        ) : filtered.length === 0 ? (
          projects.length === 0 ? (
            <EmptyState
              icon={Folder}
              title="No projects yet"
              description="A project groups the apps and databases that belong together on a server."
              action={
                <button
                  onClick={() => setShowCreate(true)}
                  className="inline-flex items-center gap-1.5 rounded-lg bg-[#8b5cf6] px-3 py-2 text-[13px] font-medium text-white hover:bg-[#7c3aed] transition-colors"
                >
                  <Plus size={14} /> New Project
                </button>
              }
            />
          ) : (
            <EmptyState
              icon={Search}
              title="No matching projects"
              description={`Nothing matches “${search}”. Try a different term, or clear the search.`}
              action={
                <button
                  onClick={() => setSearch('')}
                  className="rounded-lg border border-[rgba(255,255,255,0.1)] px-3 py-2 text-[13px] text-[#A0A0B0] hover:text-white transition-colors"
                >
                  Clear search
                </button>
              }
            />
          )
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {filtered.map((project) => (
              <ProjectCard key={project.id} project={project} onOpen={handleOpenProject} onDelete={(id, confirmation, options) =>
                destroyProject.mutateAsync({ id, confirmation, forceDestroyData: options?.forceDestroyData })
              } />
            ))}
          </div>
        )}
      </div>

      {showCreate && (
        <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-center justify-center px-4" onClick={() => setShowCreate(false)}>
          <div className="bg-[#18181B] border border-[rgba(255,255,255,0.08)] rounded-2xl p-6 w-full max-w-[420px]" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-base font-semibold text-white mb-1">New Project</h3>
            <p className="text-xs text-[#6b6b7b] mb-4">Create a new project to organize your services</p>
            <div className="space-y-3">
              <div>
                <label htmlFor="project-name" className="text-[11px] text-[#8a8a99] block mb-1.5">Project Name</label>
                <input
                  id="project-name"
                  value={newName}
                  onChange={(e) => setNewName(e.target.value)}
                  className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-rail-purple"
                  placeholder="my-project"
                />
              </div>
              <div>
                <label htmlFor="project-description" className="text-[11px] text-[#8a8a99] block mb-1.5">Description</label>
                <input
                  id="project-description"
                  value={newDesc}
                  onChange={(e) => setNewDesc(e.target.value)}
                  className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-rail-purple"
                  placeholder="What is this project about?"
                />
              </div>
              <div>
                <label htmlFor="project-environment" className="text-[11px] text-[#8a8a99] block mb-1.5">Environment</label>
                <Select value={newEnv} onValueChange={(value) => setNewEnv(value as 'production' | 'staging' | 'development')}>
                  <SelectTrigger id="project-environment">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="production">Production</SelectItem>
                    <SelectItem value="staging">Staging</SelectItem>
                    <SelectItem value="development">Development</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
            <div className="flex gap-2 mt-5">
              <button
                onClick={() => setShowCreate(false)}
                className="flex-1 py-2.5 border border-[rgba(255,255,255,0.08)] text-[#A0A0B0] text-xs rounded-lg hover:bg-[rgba(255,255,255,0.04)]"
              >
                Cancel
              </button>
              <button
                onClick={handleCreate}
                disabled={createProject.isPending}
                className="flex-1 py-2.5 bg-rail-purple text-white text-xs font-medium rounded-lg hover:bg-rail-purple-dark disabled:opacity-50"
              >
                {createProject.isPending ? 'Creating...' : 'Create Project'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

// ── Project Card (extracted component) ───────

function ProjectCard({
  project,
  onOpen,
  onDelete,
}: {
  project: { id: string; name: string; description: string; environment: string; serviceCounts: { total: number; app: number; database: number; cache: number } }
  onOpen: (id: string) => void
  onDelete: (id: string, confirmation: string, options?: { forceDestroyData?: boolean }) => Promise<unknown>
}) {
  const { total, app: appCount, database: dbCount, cache: cacheCount } = project.serviceCounts
  const [showConfirm, setShowConfirm] = useState(false)
  const [confirmName, setConfirmName] = useState('')
  const [deleteError, setDeleteError] = useState<string | null>(null)
  const [needsAcknowledgement, setNeedsAcknowledgement] = useState(false)

  const isConfirmValid = confirmName === project.name

  const handleOpen = () => {
    setShowConfirm(false)
    setConfirmName('')
    onOpen(project.id)
  }

  const handleDeleteClick = () => {
    setShowConfirm(true)
    setConfirmName('')
    setDeleteError(null)
    setNeedsAcknowledgement(false)
  }

  const handleDelete = async (forceDestroyData = false) => {
    if (!isConfirmValid) return
    setDeleteError(null)
    try {
      // The backend takes a verified snapshot of every database/volume first and
      // refuses the delete when that is impossible.
      await onDelete(project.id, confirmName, { forceDestroyData })
      setShowConfirm(false)
      setConfirmName('')
    } catch (err) {
      const error = err as Error & { code?: string }
      setDeleteError(error.message)
      if (error.code === 'snapshot_required') setNeedsAcknowledgement(true)
    }
  }

  const handleClose = () => {
    setShowConfirm(false)
    setConfirmName('')
    setDeleteError(null)
    setNeedsAcknowledgement(false)
  }

  return (
    <>
      <div className="relative group">
        <button
          onClick={(e) => {
            e.stopPropagation()
            handleOpen()
          }}
          className="w-full text-left bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] hover:border-[rgba(139,92,246,0.2)] rounded-2xl p-5 transition-all hover:bg-[rgba(255,255,255,0.04)]"
        >
          <div className="flex items-start justify-between mb-3">
            <div className="w-10 h-10 rounded-xl bg-[rgba(139,92,246,0.08)] border border-[rgba(139,92,246,0.12)] flex items-center justify-center">
              <Folder size={18} className="text-rail-purple" />
            </div>
            <span
              className={`text-[10px] px-2 py-0.5 rounded-full font-medium capitalize ${
                project.environment === 'production'
                  ? 'bg-[rgba(34,197,94,0.08)] text-rail-green'
                  : project.environment === 'staging'
                  ? 'bg-[rgba(59,130,246,0.08)] text-rail-blue'
                  : 'bg-[rgba(255,255,255,0.04)] text-[#A0A0B0]'
              }`}
            >
              {project.environment}
            </span>
          </div>

          <h3 className="text-base font-semibold text-white mb-1 group-hover:text-rail-purple transition-colors">
            {project.name}
          </h3>
          <p className="text-xs text-[#6b6b7b] mb-4 line-clamp-2">{project.description}</p>

          <div className="flex items-center gap-3 text-[10px] text-[#8a8a99]">
            <span className="flex items-center gap-1">
              <Box size={10} /> {total} services
            </span>
            {appCount > 0 && <span>{appCount} app{appCount > 1 ? 's' : ''}</span>}
            {dbCount > 0 && <span>{dbCount} db</span>}
            {cacheCount > 0 && <span>{cacheCount} cache</span>}
          </div>
        </button>

        <button
          onClick={(e) => {
            e.stopPropagation()
            handleDeleteClick()
          }}
          className="absolute top-3 right-3 opacity-0 group-hover:opacity-100 p-1.5 rounded-lg text-white/50 hover:text-red-400 hover:bg-white/[0.04] transition-all"
          title="Delete project"
        >
          <Trash2 size={14} />
        </button>
      </div>

      {showConfirm && (
        <div
          className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-center justify-center px-4"
          onClick={() => setShowConfirm(false)}
        >
          <div
            className="bg-[#18181B] border border-red-500/20 rounded-2xl p-6 w-full max-w-[420px] shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 rounded-full bg-red-500/10 flex items-center justify-center">
                <Trash2 size={18} className="text-red-400" />
              </div>
              <div>
                <h3 className="text-base font-semibold text-white">Delete Project</h3>
                <p className="text-xs text-[#8a8a99]">This action cannot be undone</p>
              </div>
            </div>

            <p className="text-sm text-[#A0A0B0] mb-4">
              You are about to permanently delete{' '}
              <span className="font-medium text-white">{project.name}</span>
              {total > 0 && (
                <>
                  {' '}and its{' '}
                  <span className="font-medium text-white">
                    {total} service{total !== 1 ? 's' : ''}
                  </span>
                  :{' '}
                  {[
                    appCount > 0 ? `${appCount} app${appCount > 1 ? 's' : ''}` : null,
                    dbCount > 0 ? `${dbCount} database${dbCount > 1 ? 's' : ''}` : null,
                    cacheCount > 0 ? `${cacheCount} cache` : null,
                  ]
                    .filter(Boolean)
                    .join(', ')}
                </>
              )}
              . All associated Dokku resources (apps, databases) will be destroyed.
            </p>

            <p className="text-[11px] text-[#8a8a99] mb-4">
              Databases and volumes are snapshotted to a verified backup destination first. If none is configured the
              deletion is refused until you acknowledge the loss.
            </p>

            {deleteError && (
              <div className="mb-4 text-[11px] text-red-300 bg-red-500/10 border border-red-500/20 rounded-lg p-2.5">
                {deleteError}
              </div>
            )}

            <div className="mb-4">
              <label className="text-[11px] text-[#8a8a99] block mb-1.5">
                Type <span className="font-mono font-medium text-white">{project.name}</span> to confirm
              </label>
              <input
                value={confirmName}
                onChange={(e) => setConfirmName(e.target.value)}
                aria-label={`Type ${project.name} to confirm`}
                aria-invalid={confirmName.length > 0 && !isConfirmValid}
                autoComplete="off"
                spellCheck={false}
                className={cn(
                  'w-full px-3 py-2.5 bg-[#0B0B0D] border rounded-lg text-sm text-white outline-none transition-colors',
                  confirmationFieldTone(confirmName, isConfirmValid)
                )}
                autoFocus
              />
            </div>

            <div className="w-full flex gap-2">
              <button
                onClick={handleClose}
                className="flex-1 py-2.5 border border-[rgba(255,255,255,0.08)] text-[#A0A0B0] text-sm rounded-lg hover:bg-[rgba(255,255,255,0.04)] transition-all"
              >
                Cancel
              </button>
              <button
                onClick={() => handleDelete(needsAcknowledgement)}
                disabled={!isConfirmValid}
                className="flex-1 py-2.5 bg-red-500 text-white text-sm font-medium rounded-lg hover:bg-red-600 transition-all disabled:opacity-30 disabled:cursor-not-allowed"
              >
                {needsAcknowledgement ? 'Delete Without Snapshot' : 'Delete Project'}
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}
