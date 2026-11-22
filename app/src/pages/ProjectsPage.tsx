import { useEffect, useState } from 'react'
import { Folder, Plus, Search, Box, Trash2, ArrowUpRight } from 'lucide-react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { useProjects, useCreateProject, useDestroyProject } from '@/hooks/useProjects'
import { deletionInFlight } from '@/lib/projects'
import type { Project } from '@/types'

import { useCanvasStore } from '@/stores/useCanvasStore'
import OnboardingChecklist from '@/components/OnboardingChecklist'
import { Dialog, DialogContent, DialogTitle, DialogDescription } from '@/components/ui/dialog'
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
  const [sort, setSort] = useState('newest')
  const [showCreate, setShowCreate] = useState(false)
  const [searchParams, setSearchParams] = useSearchParams()
  const [newName, setNewName] = useState('')
  const [newDesc, setNewDesc] = useState('')
  const [newEnv, setNewEnv] = useState<'production' | 'staging' | 'development'>('production')

  const filtered = projects.filter((p) =>
    p.name.toLowerCase().includes(search.toLowerCase()) ||
    (p.description || '').toLowerCase().includes(search.toLowerCase())
  ).sort((a, b) => sort === 'name' ? a.name.localeCompare(b.name) : new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())
  const serviceCount = projects.reduce((count, project) => count + project.serviceCounts.total, 0)

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
    createProject.mutate({ name: newName.trim(), description: newDesc, environment: newEnv }, {
      onSuccess: (project) => {
        setNewName('')
        setNewDesc('')
        setNewEnv('production')
        setShowCreate(false)
        handleOpenProject(project.id)
      },
    })
  }

  return (
    <div className="h-full overflow-y-auto px-5 py-8 sm:px-8 lg:px-12">
      <div className="max-w-6xl mx-auto">
        <div className="flex flex-wrap items-center justify-between gap-4 mb-8">
          <div>
            <h1 className="text-2xl font-semibold text-white">Projects</h1>
          </div>
          <button
            onClick={() => setShowCreate(true)}
            className="flex items-center gap-2 px-4 py-2.5 bg-rail-purple text-white text-sm font-medium rounded-xl hover:bg-rail-purple-dark transition-all"
          >
            <Plus size={16} /> New Project
          </button>
        </div>

        <OnboardingChecklist />
        {!isLoading && !isError && projects.length > 0 && <div className="mb-8 flex gap-6 border-b border-white/8 pb-5 text-sm text-[#a0a0b0]"><span><strong className="mr-1.5 text-white">{projects.length}</strong> {projects.length === 1 ? 'project' : 'projects'}</span><span><strong className="mr-1.5 text-white">{serviceCount}</strong> {serviceCount === 1 ? 'service' : 'services'}</span></div>}
        <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
        <div className="flex min-w-full flex-1 items-center bg-[rgba(255,255,255,0.04)] border border-[rgba(255,255,255,0.06)] rounded-xl px-4 py-2.5 gap-3 max-w-md sm:min-w-0">
          <Search size={16} className="text-[#9292a3]" />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            aria-label="Search projects"
            placeholder="Find a project…"
            className="bg-transparent text-sm text-white placeholder-[#6b6b7b] outline-hidden w-full"
          />
        </div>

        <Select value={sort} onValueChange={setSort}><SelectTrigger aria-label="Sort projects" className="w-40"><SelectValue /></SelectTrigger><SelectContent><SelectItem value="newest">Newest first</SelectItem><SelectItem value="name">Name A–Z</SelectItem></SelectContent></Select>
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
                  className="inline-flex items-center gap-1.5 rounded-lg bg-rail-purple px-3 py-2 text-[13px] font-medium text-white hover:bg-rail-purple-dark transition-colors"
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

      <Dialog open={showCreate} onOpenChange={(open) => { if (!createProject.isPending) setShowCreate(open) }}>
        <DialogContent className="sm:max-w-[460px]">
          <form onSubmit={(event) => { event.preventDefault(); handleCreate() }}>
            <DialogTitle className="mb-2">Create a project</DialogTitle>
            <DialogDescription className="mb-6">Group related apps and databases in a project.</DialogDescription>
            <div className="space-y-3">
              <div>
                <label htmlFor="project-name" className="text-[11px] text-[#8a8a99] block mb-1.5">Project Name</label>
                <input
                  id="project-name"
                  required
                  maxLength={100}
                  autoComplete="off"
                  value={newName}
                  onChange={(e) => setNewName(e.target.value)}
                  className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-hidden focus:border-rail-purple"
                  placeholder="my-project"
                />
              </div>
              <div>
                <label htmlFor="project-description" className="text-[11px] text-[#8a8a99] block mb-1.5">Description</label>
                <input
                  id="project-description"
                  value={newDesc}
                  onChange={(e) => setNewDesc(e.target.value)}
                  className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-hidden focus:border-rail-purple"
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
                type="button"
                onClick={() => setShowCreate(false)}
                disabled={createProject.isPending}
                className="flex-1 py-2.5 border border-[rgba(255,255,255,0.08)] text-[#A0A0B0] text-xs rounded-lg hover:bg-[rgba(255,255,255,0.04)]"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={createProject.isPending || !newName.trim()}
                className="flex-1 py-2.5 bg-rail-purple text-white text-xs font-medium rounded-lg hover:bg-rail-purple-dark disabled:opacity-50"
              >
                {createProject.isPending ? 'Creating...' : 'Create Project'}
              </button>
            </div>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  )
}

// ── Project Card (extracted component) ───────

function ProjectCard({
  project,
  onOpen,
  onDelete,
}: {
  project: Pick<Project, 'id' | 'name' | 'description' | 'environment' | 'serviceCounts' | 'deletionStatus' | 'deletionError' | 'deletionErrorCode' | 'deletionPending'>
  onOpen: (id: string) => void
  onDelete: (id: string, confirmation: string, options?: { forceDestroyData?: boolean }) => Promise<unknown>
}) {
  const { total, app: appCount, database: dbCount, cache: cacheCount } = project.serviceCounts
  const [showConfirm, setShowConfirm] = useState(false)
  const [confirmName, setConfirmName] = useState('')
  const [deleting, setDeleting] = useState(false)
  const [deleteError, setDeleteError] = useState<string | null>(null)
  const [needsAcknowledgement, setNeedsAcknowledgement] = useState(false)

  const deletionPending = deletionInFlight(project)
  const deletionStalled = !deletionPending && (project.deletionStatus === 'queued' || project.deletionStatus === 'running')
  const isConfirmValid = confirmName === project.name

  const handleOpen = () => {
    setShowConfirm(false)
    setConfirmName('')
    onOpen(project.id)
  }

  const handleDeleteClick = () => {
    setShowConfirm(true)
    setConfirmName('')
    setDeleteError(project.deletionError || null)
    setNeedsAcknowledgement(project.deletionErrorCode === 'snapshot_required')
  }

  const handleDelete = async (forceDestroyData = false) => {
    if (!isConfirmValid || deleting) return
    setDeleting(true)
    setDeleteError(null)
    try {
      // Deletion is queued: the job snapshots every database and volume, then
      // removes the Dokku resources. Failures come back through deletionStatus.
      await onDelete(project.id, confirmName, { forceDestroyData })
      setShowConfirm(false)
      setConfirmName('')
    } catch (err) {
      const error = err as Error & { code?: string }
      setDeleteError(error.message)
      if (error.code === 'snapshot_required') setNeedsAcknowledgement(true)
    } finally { setDeleting(false) }
  }

  const handleClose = () => {
    setShowConfirm(false)
    setConfirmName('')
    setDeleteError(null)
    setNeedsAcknowledgement(false)
  }

  return (
    <>
      <div className="relative group h-full">
        <button
          onClick={(e) => {
            e.stopPropagation()
            handleOpen()
          }}
          className="h-full w-full text-left bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] hover:border-[rgba(139,92,246,0.2)] rounded-xl p-5 min-h-[170px] transition-all hover:bg-[rgba(255,255,255,0.04)]"
        >
          <div className="flex items-start justify-between mb-3">
            <h3 className="min-w-0 truncate text-base font-semibold text-white group-hover:text-violet-200">{project.name}</h3>
            <span
              className={`mr-6 text-[10px] px-2 py-0.5 rounded-full font-medium capitalize ${
                project.environment === 'production'
                  ? 'bg-white/5 text-[#b7b7c5]'
                  : project.environment === 'staging'
                  ? 'bg-[rgba(59,130,246,0.08)] text-rail-blue'
                  : 'bg-[rgba(255,255,255,0.04)] text-[#A0A0B0]'
              }`}
            >
              {project.environment}
            </span>
          </div>

          {deletionPending && <p role="status" className="text-xs text-amber-300 mb-2">Deleting project… You can leave this page.</p>}
          {deletionStalled && <p role="status" className="text-xs text-amber-300 mb-2">Deletion stalled. Retry deletion to finish removing this project.</p>}
          {project.deletionStatus === 'failed' && <p role="alert" className="text-xs text-red-300 mb-2">Deletion failed: {project.deletionError} Retry deletion after resolving the error.</p>}
          <p className="text-xs leading-relaxed text-[#9393a5] mb-5 min-h-8 line-clamp-2">{project.description || 'No description.'}</p>

          <div className="flex flex-wrap items-center gap-x-3 gap-y-2 text-xs text-[#a0a0b0] [&>span]:whitespace-nowrap">
            <span className="flex items-center gap-1">
              <Box size={10} /> {total} {total === 1 ? 'service' : 'services'}
            </span>
            {appCount > 0 && <span>{appCount} app{appCount > 1 ? 's' : ''}</span>}
            {dbCount > 0 && <span>{dbCount} database{dbCount > 1 ? 's' : ''}</span>}
            {cacheCount > 0 && <span>{cacheCount} cache</span>}
            <ArrowUpRight size={15} className="ml-auto text-violet-300 opacity-0 group-hover:opacity-100 group-focus-within:opacity-100" />
          </div>
        </button>

        <button
          onClick={(e) => {
            e.stopPropagation()
            handleDeleteClick()
          }}
          type="button"
          className="absolute top-4 right-4 inline-flex min-h-8 min-w-8 items-center justify-center opacity-0 group-hover:opacity-100 group-focus-within:opacity-100 focus-visible:opacity-100 rounded-lg text-white/50 hover:text-red-400 hover:bg-white/4 transition-all"
          disabled={deletionPending}
          title={deletionPending ? 'Project deletion is in progress' : 'Delete project'}
          aria-label={deletionPending ? 'Project deletion is in progress' : `Delete project ${project.name}`}
        >
          <Trash2 size={16} />
        </button>
      </div>

      <Dialog open={showConfirm} onOpenChange={(open) => { if (!deleting) { if (!open) handleClose(); else setShowConfirm(true) } }}>
        <DialogContent className="border-red-500/20 sm:max-w-[460px]">
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 rounded-full bg-red-500/10 flex items-center justify-center">
                <Trash2 size={18} className="text-red-400" />
              </div>
              <div>
                <DialogTitle>Delete project</DialogTitle>
                <DialogDescription className="mt-1">Review the resources affected before continuing.</DialogDescription>
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
                  'w-full px-3 py-2.5 bg-[#0B0B0D] border rounded-lg text-sm text-white outline-hidden transition-colors',
                  confirmationFieldTone(confirmName, isConfirmValid)
                )}
                autoFocus
              />
            </div>

            {needsAcknowledgement && (
              <button
                onClick={() => handleDelete(true)}
                disabled={!isConfirmValid || deleting}
                className="w-full mb-3 py-2 text-sm text-red-300 disabled:opacity-30"
              >
                Permanently delete without snapshot
              </button>
            )}
            <div className="w-full flex gap-2">
              <button
                onClick={handleClose}
                className="flex-1 py-2.5 border border-[rgba(255,255,255,0.08)] text-[#A0A0B0] text-sm rounded-lg hover:bg-[rgba(255,255,255,0.04)] transition-all"
              >
                Cancel
              </button>
              <button
                onClick={() => handleDelete(false)}
                disabled={!isConfirmValid || deleting}
                className="flex-1 py-2.5 bg-red-500 text-white text-sm font-medium rounded-lg hover:bg-red-600 transition-all disabled:opacity-30 disabled:cursor-not-allowed"
              >
                {deleting ? 'Queuing…' : needsAcknowledgement ? 'Retry snapshots' : 'Delete project'}
              </button>
            </div>
        </DialogContent>
      </Dialog>
    </>
  )
}
