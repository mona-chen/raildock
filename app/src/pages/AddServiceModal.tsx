import { useState, useMemo } from 'react'
import { Link } from 'react-router-dom'
import {
  Box, Database, Zap, Cog, X, Plus, Rocket, ChevronLeft,
  GitBranch, Settings2, HelpCircle, FolderOpen, Check, Loader2,
} from 'lucide-react'
import { ServiceIcon } from '@/components/icons/ServiceIcons'
import { useCreateService } from '@/hooks/useServices'
import { useBuilders } from '@/hooks/useModules'
import { useGitSources, useGitSourceRepos } from '@/hooks/useGitSources'
import type { GitRepo } from '@/types'

interface AddServiceModalProps {
  projectId: string
  onClose: () => void
}

type Step = 'type' | 'app' | 'database' | 'service'

const DB_TYPES = [
  { subtype: 'postgres', name: 'PostgreSQL', description: 'Relational database', defaultVersion: '16' },
  { subtype: 'mysql', name: 'MySQL', description: 'Popular relational database', defaultVersion: '8.0' },
  { subtype: 'mongo', name: 'MongoDB', description: 'Document NoSQL database', defaultVersion: '7.0' },
  { subtype: 'redis', name: 'Redis', description: 'In-memory key-value store', defaultVersion: '7.2' },
]

const BUILDER_INFO: Record<string, { name: string; description: string; bestFor: string }> = {
  auto: {
    name: 'Auto-detect',
    description: 'Dokku checks for Dockerfile → Nixpacks → Herokuish in that order.',
    bestFor: 'Most projects — set and forget',
  },
  dockerfile: {
    name: 'Dockerfile',
    description: 'Builds your container using the Dockerfile in your repo root.',
    bestFor: 'When you need full control over the build process',
  },
  nixpacks: {
    name: 'Nixpacks',
    description: 'Auto-detects language and produces optimized images without a Dockerfile.',
    bestFor: 'Node, Python, Go, Ruby, PHP, Rust, Java, .NET, and more',
  },
  railpack: {
    name: 'Railpack',
    description: 'Railway-inspired buildpack with modern language support.',
    bestFor: 'Modern frameworks and monorepos',
  },
  herokuish: {
    name: 'Herokuish',
    description: 'Emulates Heroku buildpacks using the same detection logic.',
    bestFor: 'Legacy Heroku-compatible apps',
  },
  pack: {
    name: 'Cloud Native Buildpacks',
    description: 'Uses the cloud-native buildpack standard (Paketo, etc).',
    bestFor: 'Cloud-native and standardized builds',
  },
  lambda: {
    name: 'Lambda',
    description: 'AWS Lambda-style packaging for serverless deployments.',
    bestFor: 'Serverless functions',
  },
}

export default function AddServiceModal({ projectId, onClose }: AddServiceModalProps) {
  const createService = useCreateService()
  const { data: builders = [] } = useBuilders()
  const { data: gitSources = [] } = useGitSources()
  const [step, setStep] = useState<Step>('type')

  // Common
  const [name, setName] = useState('')

  // App
  const [sourceType, setSourceType] = useState<'git' | 'docker'>('git')
  const [gitSourceId, setGitSourceId] = useState<string>('')
  const [gitRepo, setGitRepo] = useState('')
  const [gitBranch, setGitBranch] = useState('main')
  const [builder, setBuilder] = useState('auto')
  const [dockerImage, setDockerImage] = useState('')
  const [rootDirectory, setRootDirectory] = useState('')
  const [repoSearch, setRepoSearch] = useState('')

  // Database
  const [dbType, setDbType] = useState('postgres')

  const isCreating = createService.isPending

  const selectedGitSource = gitSources.find((s) => s.id === gitSourceId)
  const { data: reposData, isLoading: reposLoading } = useGitSourceRepos(selectedGitSource?.id)
  const repos = reposData?.repos || []
  const reposSyncing = reposData?.syncing || false

  const filteredRepos = useMemo(() => {
    if (!repoSearch.trim()) return repos
    const q = repoSearch.toLowerCase()
    return repos.filter((r: GitRepo) =>
      r.fullName?.toLowerCase().includes(q)
    )
  }, [repos, repoSearch])

  const selectedRepo = useMemo(() => {
    return repos.find((r: GitRepo) => (r.cloneUrl || r.fullName) === gitRepo)
  }, [repos, gitRepo])

  const handleSelectRepo = (repo: GitRepo) => {
    setGitRepo(repo.cloneUrl || repo.fullName)
    if (repo.defaultBranch) setGitBranch(repo.defaultBranch)
  }

  const handleCreateApp = () => {
    const finalName = name.trim() || 'app'
    createService.mutate(
      {
        projectId,
        data: {
          name: finalName,
          subtype: sourceType === 'git' ? 'web' : 'docker',
          category: 'app',
          builder: sourceType === 'git' ? (builder === 'auto' ? undefined : builder) : undefined,
          git_repo: sourceType === 'git' ? gitRepo : undefined,
          branch: sourceType === 'git' ? gitBranch : undefined,
          docker_image: sourceType === 'docker' ? dockerImage : undefined,
          root_directory: sourceType === 'git' ? rootDirectory || undefined : undefined,
        },
      },
      { onSuccess: onClose }
    )
  }

  const handleCreateDatabase = () => {
    const finalName = name.trim() || `${dbType}-db`
    const db = DB_TYPES.find((d) => d.subtype === dbType)!
    createService.mutate(
      {
        projectId,
        data: {
          name: finalName,
          subtype: db.subtype,
          category: 'database',
          version: db.defaultVersion,
        },
      },
      { onSuccess: onClose }
    )
  }

  const handleCreateService = (subtype: string) => {
    const finalName = name.trim() || subtype
    createService.mutate(
      {
        projectId,
        data: { name: finalName, subtype, category: 'service' },
      },
      { onSuccess: onClose }
    )
  }

  // ── Step: Choose Type ────────────────────────
  if (step === 'type') {
    return (
      <ModalShell onClose={onClose} title="Add Service">
        <div className="space-y-2.5">
          <TypeCard
            icon={Rocket}
            color="#8b5cf6"
            title="Application"
            description="Deploy from a Git repository or Docker image"
            onClick={() => setStep('app')}
          />
          <TypeCard
            icon={Database}
            color="#3b82f6"
            title="Database"
            description="PostgreSQL, MySQL, MongoDB, or Redis"
            onClick={() => setStep('database')}
          />
          <TypeCard
            icon={Zap}
            color="#f59e0b"
            title="Cache"
            description="In-memory cache or session store"
            onClick={() => { setStep('service') }}
          />
          <TypeCard
            icon={Cog}
            color="#6b7280"
            title="Other Service"
            description="Message broker, search engine, or custom container"
            onClick={() => { setStep('service') }}
          />
        </div>
      </ModalShell>
    )
  }

  // ── Step: Application ────────────────────────
  if (step === 'app') {
    return (
      <ModalShell onClose={onClose} title="Add Application">
        <button
          onClick={() => setStep('type')}
          className="flex items-center gap-1 text-[12px] text-[#8b5cf6] hover:underline mb-3"
        >
          <ChevronLeft size={14} /> Back
        </button>

        <div className="space-y-4">
          <div>
            <label className="text-[11px] text-white/40 block mb-1.5">Name</label>
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="my-app"
              className="w-full bg-black/40 border border-white/[0.08] rounded-lg px-3 py-2 text-[13px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
            />
          </div>

          <div>
            <label className="text-[11px] text-white/40 block mb-1.5">Source</label>
            <div className="flex gap-2">
              <SourceButton active={sourceType === 'git'} onClick={() => setSourceType('git')} icon={() => <ServiceIcon subtype="git" size={14} />} label="Git Repository" />
              <SourceButton active={sourceType === 'docker'} onClick={() => setSourceType('docker')} icon={() => <ServiceIcon subtype="docker" size={14} />} label="Docker Image" />
            </div>
          </div>

          {sourceType === 'git' && (
            <div className="space-y-3">
              {/* Git Source Selector */}
              <div>
                <label className="text-[11px] text-white/40 block mb-1.5">Git Account</label>
                <select
                  value={gitSourceId}
                  onChange={(e) => {
                    setGitSourceId(e.target.value)
                    setGitRepo('')
                  }}
                  className="w-full bg-black/40 border border-white/[0.08] rounded-lg px-3 py-2 text-[13px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40 appearance-none cursor-pointer"
                >
                  <option value="">— Select connected account —</option>
                  {gitSources.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.provider} {s.username ? `(${s.username})` : ''}
                    </option>
                  ))}
                </select>
                {gitSources.length === 0 && (
                  <p className="text-[11px] text-white/30 mt-1">
                    No Git accounts connected.{" "}
                    <Link to="/dashboard/settings?tab=git-sources" className="text-[#8b5cf6] hover:underline">
                      Go to Platform Settings → Git Sources
                    </Link>{" "}
                    to connect one.
                  </p>
                )}
              </div>

              {/* Repo Picker */}
              {selectedGitSource && (
                <div>
                  <label className="text-[11px] text-white/40 block mb-1.5 flex items-center gap-1.5">
                    Repository
                    {reposSyncing && <Loader2 size={11} className="animate-spin text-white/30" />}
                  </label>
                  {reposLoading ? (
                    <div className="h-10 bg-white/[0.03] rounded-lg animate-pulse" />
                  ) : repos.length > 0 ? (
                    <>
                      <div className="relative mb-1.5">
                        <input
                          value={repoSearch}
                          onChange={(e) => setRepoSearch(e.target.value)}
                          placeholder="Search repositories..."
                          className="w-full bg-black/40 border border-white/[0.08] rounded-lg pl-7 pr-3 py-1.5 text-[12px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
                        />
                        <svg className="absolute left-2 top-1/2 -translate-y-1/2 text-white/20" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/></svg>
                      </div>
                      {filteredRepos.length === 0 ? (
                        <div className="text-[12px] text-white/30 py-3 text-center border border-dashed border-white/[0.06] rounded-lg">
                          No repositories match "{repoSearch}"
                        </div>
                      ) : (
                      <div className="max-h-40 overflow-y-auto border border-white/[0.06] rounded-lg divide-y divide-white/[0.04]">
                      {filteredRepos.map((repo: GitRepo) => (
                        <button
                          key={repo.id}
                          onClick={() => handleSelectRepo(repo)}
                          className={`w-full flex items-center gap-2 px-3 py-2 text-left text-[12px] transition-colors ${
                            gitRepo === (repo.cloneUrl || repo.fullName)
                              ? 'bg-[#8b5cf6]/10 text-[#8b5cf6]'
                              : 'text-white/60 hover:bg-white/[0.03]'
                          }`}
                        >
                          <GitBranch size={12} className={gitRepo === (repo.cloneUrl || repo.fullName) ? 'text-[#8b5cf6]' : 'text-white/30'} />
                          <span className="flex-1 truncate">{repo.fullName}</span>
                          {repo.private && (
                            <span className="text-[10px] px-1.5 py-0.5 bg-white/5 text-white/30 rounded">Private</span>
                          )}
                          {gitRepo === (repo.cloneUrl || repo.fullName) && <Check size={12} />}
                        </button>
                      ))}
                      </div>
                      )}
                    </>
                  ) : (
                    <div className="text-[12px] text-white/30 py-3 text-center border border-dashed border-white/[0.06] rounded-lg">
                      {reposSyncing
                        ? 'Syncing repositories...'
                        : 'No repositories found. Check your Git source connection.'}
                    </div>
                  )}
                </div>
              )}

              {/* Manual repo fallback */}
              {!selectedGitSource && (
                <div>
                  <label className="text-[11px] text-white/40 block mb-1.5 flex items-center gap-1.5">
                    Repository URL
                    <span title="Use the HTTPS or SSH clone URL of your repository. For private repos, make sure you've connected a Git source or added a deploy key." className="cursor-help">
                      <HelpCircle size={12} className="text-white/20 hover:text-white/40" />
                    </span>
                  </label>
                  <input
                    value={gitRepo}
                    onChange={(e) => setGitRepo(e.target.value)}
                    placeholder="https://github.com/username/repo.git"
                    className="w-full bg-black/40 border border-white/[0.08] rounded-lg px-3 py-2 text-[13px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
                  />
                </div>
              )}

              <div className="flex gap-3">
                <div className="flex-1">
                  <label className="text-[11px] text-white/40 block mb-1.5">Branch</label>
                  <input
                    value={gitBranch}
                    onChange={(e) => setGitBranch(e.target.value)}
                    placeholder="main"
                    className="w-full bg-black/40 border border-white/[0.08] rounded-lg px-3 py-2 text-[13px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
                  />
                </div>
                <div className="flex-1">
                  <label className="text-[11px] text-white/40 block mb-1.5 flex items-center gap-1.5">
                    <FolderOpen size={11} />
                    Base Directory
                  </label>
                  <input
                    value={rootDirectory}
                    onChange={(e) => setRootDirectory(e.target.value)}
                    placeholder="/ (repo root)"
                    className="w-full bg-black/40 border border-white/[0.08] rounded-lg px-3 py-2 text-[13px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
                  />
                </div>
              </div>

              {/* Builder Selection */}
              <div>
                <label className="text-[11px] text-white/40 block mb-1.5 flex items-center gap-1.5">
                  Builder
                  <span title="Builders determine how your code is turned into a container image." className="cursor-help">
                    <HelpCircle size={12} className="text-white/20 hover:text-white/40" />
                  </span>
                </label>
                <div className="grid grid-cols-2 gap-2">
                  {(['auto', ...builders.map((b) => b.id)] as string[]).map((b) => {
                    const info = BUILDER_INFO[b] || { name: b, description: '', bestFor: '' }
                    const isActive = builder === b
                    return (
                      <button
                        key={b}
                        onClick={() => setBuilder(b)}
                        className={`text-left p-2.5 rounded-lg border transition-all ${
                          isActive
                            ? 'border-[#8b5cf6]/40 bg-[#8b5cf6]/10'
                            : 'border-white/[0.06] bg-[#1a1a1e] hover:border-white/[0.1]'
                        }`}
                      >
                        <div className={`text-[12px] font-medium ${isActive ? 'text-[#8b5cf6]' : 'text-white/70'}`}>
                          {info.name}
                        </div>
                        <div className="text-[10px] text-white/30 mt-0.5 leading-tight">
                          {info.bestFor}
                        </div>
                      </button>
                    )
                  })}
                </div>
                <div className="text-[11px] text-white/30 bg-white/[0.03] rounded-lg px-3 py-2 mt-2">
                  {BUILDER_INFO[builder]?.description || builders.find((b) => b.id === builder)?.description}
                </div>
              </div>
            </div>
          )}

          {sourceType === 'docker' && (
            <div>
              <label className="text-[11px] text-white/40 block mb-1.5">Docker Image</label>
              <input
                value={dockerImage}
                onChange={(e) => setDockerImage(e.target.value)}
                placeholder="nginx:alpine"
                className="w-full bg-black/40 border border-white/[0.08] rounded-lg px-3 py-2 text-[13px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
              />
              <div className="text-[11px] text-white/30 mt-1.5">
                Dokku will pull and deploy this image directly.
              </div>
            </div>
          )}

          <button
            onClick={handleCreateApp}
            disabled={isCreating || (sourceType === 'git' && !gitRepo.trim()) || (sourceType === 'docker' && !dockerImage.trim())}
            className="w-full py-2.5 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[13px] font-medium hover:bg-[#8b5cf6]/25 transition-all disabled:opacity-50 flex items-center justify-center gap-2"
          >
            <Plus size={14} />
            {isCreating ? 'Creating...' : 'Create Application'}
          </button>
        </div>
      </ModalShell>
    )
  }

  // ── Step: Database ───────────────────────────
  if (step === 'database') {
    return (
      <ModalShell onClose={onClose} title="Add Database">
        <button
          onClick={() => setStep('type')}
          className="flex items-center gap-1 text-[12px] text-[#8b5cf6] hover:underline mb-3"
        >
          <ChevronLeft size={14} /> Back
        </button>

        <div className="space-y-4">
          <div>
            <label className="text-[11px] text-white/40 block mb-1.5">Name</label>
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="my-app-db"
              className="w-full bg-black/40 border border-white/[0.08] rounded-lg px-3 py-2 text-[13px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
            />
          </div>

          <div>
            <label className="text-[11px] text-white/40 block mb-1.5">Database Type</label>
            <div className="space-y-2">
              {DB_TYPES.map((db) => (
                <button
                  key={db.subtype}
                  onClick={() => setDbType(db.subtype)}
                  className={`w-full flex items-center gap-3 p-3 border rounded-lg text-left transition-all ${
                    dbType === db.subtype
                      ? 'border-[#3b82f6]/40 bg-[#3b82f6]/5'
                      : 'border-white/[0.06] bg-[#1a1a1e] hover:border-white/[0.1]'
                  }`}
                >
                  <ServiceIcon subtype={db.subtype} size={18} />
                  <div className="flex-1">
                    <div className="text-[13px] text-white/70">{db.name}</div>
                    <div className="text-[11px] text-white/40">{db.description} · v{db.defaultVersion}</div>
                  </div>
                  {dbType === db.subtype && (
                    <div className="w-4 h-4 rounded-full bg-[#3b82f6]/20 flex items-center justify-center">
                      <div className="w-2 h-2 rounded-full bg-[#3b82f6]" />
                    </div>
                  )}
                </button>
              ))}
            </div>
          </div>

          <button
            onClick={handleCreateDatabase}
            disabled={isCreating}
            className="w-full py-2.5 bg-[#3b82f6]/15 text-[#3b82f6] rounded-lg text-[13px] font-medium hover:bg-[#3b82f6]/25 transition-all disabled:opacity-50 flex items-center justify-center gap-2"
          >
            <Plus size={14} />
            {isCreating ? 'Creating...' : 'Create Database'}
          </button>
        </div>
      </ModalShell>
    )
  }

  // ── Step: Service / Cache ────────────────────
  return (
    <ModalShell onClose={onClose} title="Add Service">
      <button
        onClick={() => setStep('type')}
        className="flex items-center gap-1 text-[12px] text-[#8b5cf6] hover:underline mb-3"
      >
        <ChevronLeft size={14} /> Back
      </button>

      <div className="space-y-4">
        <div>
          <label className="text-[11px] text-white/40 block mb-1.5">Name</label>
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="my-service"
            className="w-full bg-black/40 border border-white/[0.08] rounded-lg px-3 py-2 text-[13px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
          />
        </div>

        <div className="space-y-2">
          <ServiceOption
            icon={() => <ServiceIcon subtype="redis" size={18} />}
            name="Redis"
            description="In-memory cache and session store"
            onClick={() => handleCreateService('redis')}
            isCreating={isCreating}
          />
          <ServiceOption
            icon={() => <ServiceIcon subtype="rabbitmq" size={18} />}
            name="RabbitMQ"
            description="Message broker and queue system"
            onClick={() => handleCreateService('rabbitmq')}
            isCreating={isCreating}
          />
          <ServiceOption
            icon={() => <ServiceIcon subtype="minio" size={18} />}
            name="MinIO"
            description="S3-compatible object storage"
            onClick={() => handleCreateService('minio')}
            isCreating={isCreating}
          />
        </div>
      </div>
    </ModalShell>
  )
}

// ── UI Components ──────────────────────────────

function ModalShell({ title, onClose, children }: { title: string; onClose: () => void; children: React.ReactNode }) {
  return (
    <div
      className="absolute inset-0 z-[60] flex items-center justify-center"
      style={{ backgroundColor: 'rgba(0,0,0,0.6)' }}
      onClick={onClose}
    >
      <div
        className="bg-[#16161a] border border-white/[0.08] rounded-xl w-[520px] max-h-[80%] flex flex-col shadow-2xl"
        onClick={(e) => e.stopPropagation()}
        data-no-pan
      >
        <div className="flex items-center justify-between p-4 border-b border-white/[0.06]">
          <div className="text-[15px] font-semibold text-white/90">{title}</div>
          <button
            onClick={onClose}
            className="p-1.5 hover:bg-white/[0.06] rounded-lg text-white/30 hover:text-white/60"
          >
            <X size={16} />
          </button>
        </div>
        <div className="p-4 overflow-y-auto">{children}</div>
      </div>
    </div>
  )
}

function TypeCard({ icon: Icon, color, title, description, onClick }: {
  icon: React.ElementType
  color: string
  title: string
  description: string
  onClick: () => void
}) {
  return (
    <button
      onClick={onClick}
      className="w-full flex items-center gap-3 p-3.5 bg-[#1a1a1e] border border-white/[0.06] rounded-xl hover:border-white/[0.12] transition-all text-left group"
    >
      <div
        className="w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0 transition-all"
        style={{ backgroundColor: `${color}15` }}
      >
        <Icon size={20} style={{ color }} />
      </div>
      <div className="flex-1">
        <div className="text-[14px] text-white/80 font-medium group-hover:text-white/90">{title}</div>
        <div className="text-[12px] text-white/40">{description}</div>
      </div>
      <Plus size={16} className="text-white/20 group-hover:text-white/40 transition-colors" />
    </button>
  )
}

function SourceButton({ active, onClick, icon: Icon, label }: {
  active: boolean
  onClick: () => void
  icon: React.ElementType
  label: string
}) {
  return (
    <button
      onClick={onClick}
      className={`flex-1 flex items-center justify-center gap-2 py-2.5 rounded-lg text-[12px] font-medium transition-all border ${
        active
          ? 'border-[#8b5cf6]/40 bg-[#8b5cf6]/10 text-[#8b5cf6]'
          : 'border-white/[0.06] bg-[#1a1a1e] text-white/50 hover:text-white/70'
      }`}
    >
      <Icon size={14} />
      {label}
    </button>
  )
}

function ServiceOption({ icon: Icon, name, description, onClick, isCreating }: {
  icon: React.ElementType
  name: string
  description: string
  onClick: () => void
  isCreating: boolean
}) {
  return (
    <button
      onClick={onClick}
      disabled={isCreating}
      className="w-full flex items-center gap-3 p-3 bg-[#1a1a1e] border border-white/[0.06] rounded-lg hover:border-white/[0.1] transition-all text-left disabled:opacity-50"
    >
      <Icon size={16} className="text-white/40" />
      <div className="flex-1">
        <div className="text-[13px] text-white/70">{name}</div>
        <div className="text-[11px] text-white/40">{description}</div>
      </div>
      <Plus size={14} className="text-white/30" />
    </button>
  )
}
