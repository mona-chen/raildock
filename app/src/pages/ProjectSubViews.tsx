import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { ExternalLink, FolderGit2, KeyRound, Server, Settings, Trash2, Eye, EyeOff } from 'lucide-react'
import { useProject, useUpdateProjectSharedVars } from '@/hooks/useProjects'
import { useServers } from '@/hooks/useServers'
import type { Server as ServerRecord } from '@/types'

export function ProjectSettingsView() {
  const { projectId = '' } = useParams<{ projectId: string }>()
  const { data: project } = useProject(projectId)
  const { data: servers = [] } = useServers()
  const server = servers.find((candidate) => candidate.id === project?.serverId)

  return (
    <div className="h-full flex flex-col overflow-hidden">
      <div className="px-6 py-4 border-b border-white/[0.06]">
        <div className="flex items-center gap-3">
          <Settings size={18} className="text-rail-purple" />
          <div>
            <h1 className="text-base font-semibold text-white">Project Settings</h1>
            <p className="text-[11px] text-white/35 mt-0.5">
              Configuration owned by this project
            </p>
          </div>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-6">
        <div className="max-w-3xl mx-auto space-y-5">
          <SharedVarsSection />
          <ServerSection server={server} />
          <PlatformSourcesCard />
        </div>
      </div>
    </div>
  )
}

function SharedVarsSection() {
  const { projectId = '' } = useParams<{ projectId: string }>()
  const { data: project } = useProject(projectId)
  const updateVars = useUpdateProjectSharedVars()
  const [newKey, setNewKey] = useState('')
  const [newValue, setNewValue] = useState('')
  const [revealed, setRevealed] = useState<Set<string>>(new Set())
  const vars = project?.sharedVars || []

  const toggleReveal = (key: string) => {
    setRevealed((prev) => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })
  }

  const handleAdd = () => {
    const key = newKey.trim()
    if (!key || !projectId) return

    const next = [...vars.filter((variable) => variable.key !== key), { key, value: newValue }]
    updateVars.mutate({ id: projectId, vars: next }, {
      onSuccess: () => {
        setNewKey('')
        setNewValue('')
      },
    })
  }

  const handleRemove = (key: string) => {
    updateVars.mutate({ id: projectId, vars: vars.filter((variable) => variable.key !== key) })
  }

  return (
    <section className="bg-[#16161a] border border-white/[0.06] rounded-xl overflow-hidden">
      <div className="p-4 border-b border-white/[0.06]">
        <div className="flex items-center gap-2">
          <KeyRound size={14} className="text-rail-purple" />
          <h2 className="text-sm font-medium text-white">Shared Variables</h2>
          <span className="ml-auto text-[10px] text-white/30">{vars.length} variables</span>
        </div>
        <p className="text-[11px] text-white/35 mt-1">
          Reference these in the manifest as <code className="text-white/55">${'{{ shared.KEY }}'}</code>.
          Values stay hidden after saving.
        </p>
      </div>

      {vars.length > 0 && (
        <div className="divide-y divide-white/[0.05]">
          {vars.map((variable) => {
              const isRevealed = revealed.has(variable.key)
              return (
                <div key={variable.key} className="px-4 py-3 flex items-center gap-3 group">
                  <code className="text-[12px] text-white/70 flex-1">{variable.key}</code>
                  <span className="text-[11px] font-mono text-white/40 break-all">
                    {isRevealed ? variable.value : '••••••••••••'}
                  </span>
                  <button
                    type="button"
                    onClick={() => toggleReveal(variable.key)}
                    className="p-1.5 rounded text-white/25 hover:text-white/60 hover:bg-white/[0.06] opacity-0 group-hover:opacity-100 transition-all"
                    aria-label={isRevealed ? `Hide ${variable.key}` : `Reveal ${variable.key}`}
                    title={isRevealed ? 'Hide value' : 'Show value'}
                  >
                    {isRevealed ? <EyeOff size={12} /> : <Eye size={12} />}
                  </button>
                  <button
                    type="button"
                    onClick={() => handleRemove(variable.key)}
                    disabled={updateVars.isPending}
                    className="p-1.5 rounded text-white/20 hover:text-red-400 hover:bg-red-500/10 opacity-0 group-hover:opacity-100 transition-all"
                    aria-label={`Remove ${variable.key}`}
                  >
                    <Trash2 size={12} />
                  </button>
                </div>
              )
            })}
        </div>
      )}

      <div className="p-4 bg-black/15 grid grid-cols-1 sm:grid-cols-[1fr_1fr_auto] gap-2">
        <input
          type="text"
          placeholder="VARIABLE_NAME"
          value={newKey}
          onChange={(event) => setNewKey(event.target.value.toUpperCase())}
          className="bg-black/30 border border-white/[0.08] rounded-lg px-3 py-2 text-[12px] font-mono text-white/70 outline-none focus:border-rail-purple/50"
        />
        <input
          type="password"
          placeholder="Value"
          value={newValue}
          onChange={(event) => setNewValue(event.target.value)}
          onKeyDown={(event) => event.key === 'Enter' && handleAdd()}
          className="bg-black/30 border border-white/[0.08] rounded-lg px-3 py-2 text-[12px] font-mono text-white/70 outline-none focus:border-rail-purple/50"
        />
        <button
          type="button"
          onClick={handleAdd}
          disabled={updateVars.isPending || !newKey.trim()}
          className="px-4 py-2 bg-rail-purple text-white rounded-lg text-[12px] font-medium disabled:opacity-40"
        >
          {updateVars.isPending ? 'Saving...' : 'Add variable'}
        </button>
      </div>
    </section>
  )
}

function ServerSection({ server }: { server?: ServerRecord }) {
  return (
    <section className="bg-[#16161a] border border-white/[0.06] rounded-xl p-4">
      <div className="flex items-start gap-3">
        <div className="w-9 h-9 rounded-lg bg-rail-purple/10 flex items-center justify-center">
          <Server size={17} className="text-rail-purple" />
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <h2 className="text-sm font-medium text-white">Runtime Server</h2>
            {server && (
              <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400">
                {server.status}
              </span>
            )}
          </div>
          <p className="text-[11px] text-white/35 mt-1">
            {server ? `${server.name} · ${server.host}` : 'No server is assigned to this project.'}
          </p>
        </div>
        <Link to="/dashboard/servers" className="text-[11px] text-rail-purple flex items-center gap-1">
          Manage <ExternalLink size={11} />
        </Link>
      </div>
    </section>
  )
}

function PlatformSourcesCard() {
  return (
    <section className="bg-[#16161a] border border-white/[0.06] rounded-xl p-4">
      <div className="flex items-start gap-3">
        <div className="w-9 h-9 rounded-lg bg-white/[0.04] flex items-center justify-center">
          <FolderGit2 size={17} className="text-white/45" />
        </div>
        <div className="min-w-0 flex-1">
          <h2 className="text-sm font-medium text-white">Git Sources</h2>
          <p className="text-[11px] text-white/35 mt-1">
            Git accounts and app installations are platform integrations. Repositories are selected when configuring each service.
          </p>
        </div>
        <Link
          to="/dashboard/settings?tab=git-sources"
          className="text-[11px] text-rail-purple flex items-center gap-1 whitespace-nowrap"
        >
          Platform settings <ExternalLink size={11} />
        </Link>
      </div>
    </section>
  )
}
