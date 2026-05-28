import { useState } from 'react'
import { Folder, Plus, Search, Box, Trash2 } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { useProjects, useCreateProject, useDestroyProject } from '@/hooks/useProjects'

import { useCanvasStore } from '@/stores/useCanvasStore'
import OnboardingChecklist from '@/components/OnboardingChecklist'

export default function ProjectsPage() {
  const navigate = useNavigate()
  const { data: projects = [], isLoading } = useProjects()
  const createProject = useCreateProject()
  const destroyProject = useDestroyProject()
  const setActiveProject = useCanvasStore((s) => s.setActiveService)

  const [search, setSearch] = useState('')
  const [showCreate, setShowCreate] = useState(false)
  const [newName, setNewName] = useState('')
  const [newDesc, setNewDesc] = useState('')
  const [newEnv, setNewEnv] = useState<'production' | 'staging' | 'development'>('production')

  const filtered = projects.filter((p) =>
    p.name.toLowerCase().includes(search.toLowerCase()) ||
    p.description.toLowerCase().includes(search.toLowerCase())
  )

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
            <p className="text-sm text-[#4A4A55]">Manage your applications and services</p>
          </div>
          <button
            onClick={() => setShowCreate(true)}
            className="flex items-center gap-2 px-4 py-2.5 bg-rail-purple text-white text-sm font-medium rounded-xl hover:bg-rail-purple-dark transition-all"
          >
            <Plus size={16} /> New Project
          </button>
        </div>

        <div className="flex items-center bg-[rgba(255,255,255,0.04)] border border-[rgba(255,255,255,0.06)] rounded-xl px-4 py-2.5 gap-3 max-w-md mb-6">
          <Search size={16} className="text-[#4A4A55]" />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search projects..."
            className="bg-transparent text-sm text-white placeholder-[#4A4A55] outline-none w-full"
          />
        </div>

        {isLoading ? (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {Array.from({ length: 3 }).map((_, i) => (
              <div key={i} className="h-40 bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-2xl animate-pulse" />
            ))}
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {filtered.map((project) => (
              <ProjectCard key={project.id} project={project} onOpen={handleOpenProject} onDelete={destroyProject.mutate} />
            ))}
          </div>
        )}

        {filtered.length === 0 && !isLoading && (
          <div className="text-center py-16 text-[#4A4A55]">
            <Folder size={48} className="mx-auto mb-4 opacity-30" />
            <p className="text-sm">No projects found</p>
            <button onClick={() => setShowCreate(true)} className="mt-3 text-rail-purple text-sm hover:underline">
              Create your first project
            </button>
          </div>
        )}
      </div>

      {showCreate && (
        <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-center justify-center px-4" onClick={() => setShowCreate(false)}>
          <div className="bg-[#18181B] border border-[rgba(255,255,255,0.08)] rounded-2xl p-6 w-full max-w-[420px]" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-base font-semibold text-white mb-1">New Project</h3>
            <p className="text-xs text-[#4A4A55] mb-4">Create a new project to organize your services</p>
            <div className="space-y-3">
              <div>
                <label htmlFor="project-name" className="text-[11px] text-[#6B6B7B] block mb-1.5">Project Name</label>
                <input
                  id="project-name"
                  value={newName}
                  onChange={(e) => setNewName(e.target.value)}
                  className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-rail-purple"
                  placeholder="my-project"
                />
              </div>
              <div>
                <label htmlFor="project-description" className="text-[11px] text-[#6B6B7B] block mb-1.5">Description</label>
                <input
                  id="project-description"
                  value={newDesc}
                  onChange={(e) => setNewDesc(e.target.value)}
                  className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-rail-purple"
                  placeholder="What is this project about?"
                />
              </div>
              <div>
                <label htmlFor="project-environment" className="text-[11px] text-[#6B6B7B] block mb-1.5">Environment</label>
                <select
                  id="project-environment"
                  value={newEnv}
                  onChange={(e) => setNewEnv(e.target.value as 'production' | 'staging' | 'development')}
                  className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-rail-purple appearance-none cursor-pointer"
                >
                  <option value="production">Production</option>
                  <option value="staging">Staging</option>
                  <option value="development">Development</option>
                </select>
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
  onDelete: (id: string) => void
}) {
  const { total, app: appCount, database: dbCount, cache: cacheCount } = project.serviceCounts
  const [showConfirm, setShowConfirm] = useState(false)

  return (
    <>
      <div className="relative group">
        <button
          onClick={() => onOpen(project.id)}
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
          <p className="text-xs text-[#4A4A55] mb-4 line-clamp-2">{project.description}</p>

          <div className="flex items-center gap-3 text-[10px] text-[#6B6B7B]">
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
            setShowConfirm(true)
          }}
          className="absolute top-3 right-3 opacity-0 group-hover:opacity-100 p-1.5 rounded-lg text-white/30 hover:text-red-400 hover:bg-white/[0.04] transition-all"
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
                <p className="text-xs text-[#6B6B7B]">This action cannot be undone</p>
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

            <div className="w-full flex gap-2">
              <button
                onClick={() => setShowConfirm(false)}
                className="flex-1 py-2.5 border border-[rgba(255,255,255,0.08)] text-[#A0A0B0] text-sm rounded-lg hover:bg-[rgba(255,255,255,0.04)] transition-all"
              >
                Cancel
              </button>
              <button
                onClick={() => {
                  setShowConfirm(false)
                  onDelete(project.id)
                }}
                className="flex-1 py-2.5 bg-red-500 text-white text-sm font-medium rounded-lg hover:bg-red-600 transition-all"
              >
                Delete Project
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}
