import { useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import {
  FolderGit2, Trash2, Server, KeyRound, ExternalLink,
} from 'lucide-react'
import { useServices } from '@/hooks/useServices'
import { useGitSources, useConnectGitSource, useDisconnectGitSource } from '@/hooks/useGitSources'
import { useProject, useUpdateProjectSharedVars } from '@/hooks/useProjects'
import { useServers } from '@/hooks/useServers'
import { CopyButton } from '@/components/ui/CopyButton'

const WEBHOOK_URL = typeof window !== 'undefined'
  ? `${window.location.protocol}//${window.location.host}/api/webhooks/deploy`
  : ''

// ── Project Settings View ────────────────────
// Combines Shared Variables, Git Sources, and Server info
// into a single project-level settings page.

export function ProjectSettingsView() {
  const { projectId } = useParams<{ projectId: string }>()
  const { data: project } = useProject(projectId || '')
  const { data: servers = [] } = useServers()
  const server = servers[0]

  return (
    <div className="h-full flex flex-col overflow-hidden">
      <div className="px-6 py-4 border-b border-[rgba(255,255,255,0.06)]">
        <div className="flex items-center gap-3">
          <Server size={18} className="text-rail-purple" />
          <h1 className="text-base font-semibold text-white">Project Settings</h1>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-6">
        <div className="max-w-2xl mx-auto space-y-6">
          <SharedVarsSection />
          <GitSourcesSection />
          <ServerSection server={server} />
        </div>
      </div>
    </div>
  )
}

// ── Shared Variables Section ─────────────────

function SharedVarsSection() {
  const { projectId } = useParams<{ projectId: string }>()
  const { data: project } = useProject(projectId || '')
  const updateVars = useUpdateProjectSharedVars()
  const [newKey, setNewKey] = useState('')
  const [newValue, setNewValue] = useState('')

  const vars = project?.sharedVars || []

  const handleAdd = () => {
    if (!newKey.trim() || !projectId) return
    const next = [...vars, { key: newKey.trim(), value: newValue }]
    updateVars.mutate({ id: projectId, vars: next }, {
      onSuccess: () => { setNewKey(''); setNewValue('') },
    })
  }

  const handleRemove = (key: string) => {
    if (!projectId) return
    const next = vars.filter((v) => v.key !== key)
    updateVars.mutate({ id: projectId, vars: next })
  }

  return (
    <div>
      <div className="flex items-center gap-2 mb-3">
        <KeyRound size={14} className="text-rail-purple" />
        <h2 className="text-sm font-medium text-white">Shared Variables</h2>
      </div>
      <p className="text-[11px] text-[#4A4A55] mb-3">
        Project-level environment variables shared across all services
      </p>

      {vars.length > 0 && (
        <div className="space-y-2 mb-4">
          {vars.map((v) => (
            <div key={v.key} className="bg-[#16161a] border border-white/[0.06] rounded-lg p-3 flex items-center gap-3 group">
              <div className="flex-1 min-w-0">
                <div className="text-[13px] text-white/70 font-mono">{v.key}</div>
                <div className="text-[11px] text-white/40 font-mono truncate">{v.value}</div>
              </div>
              <button
                onClick={() => handleRemove(v.key)}
                className="p-1 hover:bg-white/[0.06] rounded text-white/20 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity"
              >
                <Trash2 size={12} />
              </button>
            </div>
          ))}
        </div>
      )}

      <div className="bg-[#16161a] border border-white/[0.06] rounded-xl p-4">
        <div className="text-[13px] font-medium text-white/70 mb-3">Add Variable</div>
        <div className="flex gap-2">
          <input
            type="text"
            placeholder="KEY_NAME"
            value={newKey}
            onChange={(e) => setNewKey(e.target.value)}
            className="flex-1 bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] font-mono text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
          />
          <input
            type="text"
            placeholder="value"
            value={newValue}
            onChange={(e) => setNewValue(e.target.value)}
            className="flex-1 bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] font-mono text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
          />
          <button
            onClick={handleAdd}
            disabled={updateVars.isPending || !newKey.trim()}
            className="px-3 py-1.5 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[12px] hover:bg-[#8b5cf6]/25 transition-all disabled:opacity-50"
          >
            {updateVars.isPending ? 'Adding...' : 'Add'}
          </button>
        </div>
      </div>
    </div>
  )
}

// ── Git Sources Section ──────────────────────

function GitSourcesSection() {
  const { data: gitSources = [] } = useGitSources()
  const { projectId } = useParams<{ projectId: string }>()
  const { data: svcs = [] } = useServices(projectId || '')
  const connect = useConnectGitSource()
  const disconnect = useDisconnectGitSource()
  const [modalOpen, setModalOpen] = useState(false)
  const [modalProvider, setModalProvider] = useState('')
  const [token, setToken] = useState('')
  const connected = gitSources.filter((g) => g.connected)

  const openConnect = (provider: string) => {
    setModalProvider(provider)
    setToken('')
    setModalOpen(true)
  }

  const handleConnect = () => {
    if (!token.trim()) return
    connect.mutate({ provider: modalProvider, token }, {
      onSuccess: () => setModalOpen(false),
    })
  }

  return (
    <div>
      <div className="flex items-center gap-2 mb-3">
        <FolderGit2 size={14} className="text-rail-purple" />
        <h2 className="text-sm font-medium text-white">Git Sources</h2>
      </div>
      <p className="text-[11px] text-[#4A4A55] mb-3">
        Connected repositories and deployments
      </p>

      {connected.length > 0 ? (
        <div className="space-y-4">
          {connected.map((gs) => (
            <div key={gs.id} className="bg-[#16161a] border border-white/[0.06] rounded-xl p-4">
              <div className="flex items-center gap-2 mb-3">
                <FolderGit2 size={16} className="text-[#8b5cf6]" />
                <span className="text-[14px] font-medium text-white/70">{gs.provider}</span>
                <span className="text-[11px] px-2 py-0.5 bg-[#22c55e]/10 text-[#22c55e] rounded-full">connected</span>
                <span className="text-[12px] text-white/40">{gs.username}</span>
                <button
                  onClick={() => disconnect.mutate(gs.id)}
                  disabled={disconnect.isPending}
                  className="ml-auto text-[11px] px-2 py-1 text-white/30 hover:text-red-400 transition-colors disabled:opacity-50"
                >
                  {disconnect.isPending ? 'Disconnecting...' : 'Disconnect'}
                </button>
              </div>
              <div className="space-y-2">
                {gs.repos.map((r) => {
                  const linkedSvc = svcs.find((s) => s.gitRepo === r.fullName)
                  return (
                    <div
                      key={r.id}
                      className="bg-black/20 rounded-lg p-3 flex items-center gap-3"
                    >
                      <div className="flex-1">
                        <div className="text-[13px] text-white/70">{r.fullName}</div>
                        <div className="text-[11px] text-white/40">
                          {r.defaultBranch} {r.private && '· private'}
                        </div>
                      </div>
                      {linkedSvc ? (
                        <span className="text-[11px] px-2 py-0.5 bg-[#8b5cf6]/10 text-[#8b5cf6] rounded-full">
                          deploys to {linkedSvc.name}
                        </span>
                      ) : (
                        <button type="button" className="text-[11px] px-2 py-1 bg-white/[0.06] text-white/50 rounded hover:bg-white/[0.1]">
                          Link
                        </button>
                      )}
                    </div>
                  )
                })}
              </div>
              <div className="mt-3 bg-black/20 rounded-lg p-3">
                <div className="text-[11px] text-white/40 mb-1">Webhook URL — paste into {gs.provider} repository settings</div>
                <div className="flex gap-2">
                  <code className="flex-1 text-[11px] font-mono text-white/50 bg-black/40 rounded px-2 py-1 truncate">{WEBHOOK_URL}</code>
                  <CopyButton text={WEBHOOK_URL} size={11} className="text-[11px] px-2 py-1 bg-white/[0.06] text-white/50 rounded hover:bg-white/[0.1]" title="Copy webhook URL" />
                </div>
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="text-[13px] text-white/30">No git sources connected</div>
      )}

      {gitSources
        .filter((g) => !g.connected)
        .map((gs) => (
          <div
            key={gs.id}
            className="bg-[#16161a] border border-white/[0.06] rounded-xl p-4 flex items-center justify-between mt-3"
          >
            <div className="flex items-center gap-2">
              <FolderGit2 size={16} className="text-white/30" />
              <span className="text-[13px] text-white/50 capitalize">{gs.provider}</span>
            </div>
            <button
              type="button"
              onClick={() => openConnect(gs.provider)}
              className="text-[12px] px-3 py-1.5 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg hover:bg-[#8b5cf6]/25 transition-all"
            >
              Connect
            </button>
          </div>
        ))}

      {/* Connect Modal */}
      {modalOpen && (
        <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-center justify-center" onClick={() => setModalOpen(false)}>
          <div className="bg-[#18181B] border border-[rgba(255,255,255,0.08)] rounded-2xl p-6 w-[420px]" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-base font-semibold text-white mb-1">Connect {modalProvider}</h3>
            <p className="text-xs text-[#4A4A55] mb-4">Enter your personal access token</p>
            <div className="space-y-3">
              <div>
                <label className="text-[11px] text-[#6B6B7B] block mb-1.5">Access Token</label>
                <input
                  type="password"
                  value={token}
                  onChange={(e) => setToken(e.target.value)}
                  className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-rail-purple"
                  placeholder="ghp_xxxxxxxxxxxx"
                  onKeyDown={(e) => e.key === 'Enter' && handleConnect()}
                />
              </div>
            </div>
            <div className="flex gap-2 mt-5">
              <button type="button" onClick={() => setModalOpen(false)} className="flex-1 py-2.5 border border-[rgba(255,255,255,0.08)] text-[#A0A0B0] text-xs rounded-lg hover:bg-[rgba(255,255,255,0.04)]">Cancel</button>
              <button type="button" onClick={handleConnect} disabled={connect.isPending || !token.trim()} className="flex-1 py-2.5 bg-rail-purple text-white text-xs font-medium rounded-lg hover:bg-rail-purple-dark disabled:opacity-50">
                {connect.isPending ? 'Connecting...' : 'Connect'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

// ── Server Section ───────────────────────────

function ServerSection({ server }: { server?: { id: string; name: string; host: string; status: string; dokkuVersion?: string; dockerVersion?: string; os?: string; defaultProxy?: string; diskUsage?: { used: number; total: number }; memoryUsage?: { used: number; total: number } } }) {
  if (!server) {
    return (
      <div>
        <div className="flex items-center gap-2 mb-3">
          <Server size={14} className="text-rail-purple" />
          <h2 className="text-sm font-medium text-white">Server</h2>
        </div>
        <div className="text-[13px] text-white/30">No server connected</div>
      </div>
    )
  }

  return (
    <div>
      <div className="flex items-center gap-2 mb-3">
        <Server size={14} className="text-rail-purple" />
        <h2 className="text-sm font-medium text-white">Server</h2>
      </div>

      <div className="bg-[#16161a] border border-white/[0.06] rounded-xl p-4 mb-4">
        <div className="flex items-center gap-3 mb-3">
          <div className="w-10 h-10 rounded-xl bg-[#8b5cf6]/10 flex items-center justify-center">
            <Server size={20} className="text-[#8b5cf6]" />
          </div>
          <div>
            <div className="text-[16px] font-semibold text-white/90">{server.name}</div>
            <div className="text-[12px] text-white/40">{server.host}</div>
          </div>
          <span className="text-[11px] px-2 py-0.5 bg-[#22c55e]/10 text-[#22c55e] rounded-full ml-auto">
            {server.status}
          </span>
        </div>
        <div className="grid grid-cols-2 gap-3">
          {[
            { l: 'Dokku Version', v: server.dokkuVersion },
            { l: 'Docker Version', v: server.dockerVersion },
            { l: 'OS', v: server.os },
            { l: 'Proxy', v: server.defaultProxy },
          ].map((i) => (
            <div key={i.l} className="bg-black/20 rounded-lg p-2.5">
              <div className="text-[11px] text-white/40">{i.l}</div>
              <div className="text-[12px] text-white/70 mt-0.5">{i.v}</div>
            </div>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3 mb-4">
        <div className="bg-[#16161a] border border-white/[0.06] rounded-xl p-4">
          <div className="text-[12px] text-white/40 mb-2">Disk Usage</div>
          <div className="text-[18px] font-semibold text-white/80">
            {server.diskUsage?.used || 0} / {server.diskUsage?.total || 100} GB
          </div>
          <div className="mt-2 h-2 bg-white/[0.06] rounded-full overflow-hidden">
            <div
              className="h-full bg-[#8b5cf6] rounded-full"
              style={{
                width: `${((server.diskUsage?.used || 0) / (server.diskUsage?.total || 100)) * 100}%`,
              }}
            />
          </div>
        </div>
        <div className="bg-[#16161a] border border-white/[0.06] rounded-xl p-4">
          <div className="text-[12px] text-white/40 mb-2">Memory Usage</div>
          <div className="text-[18px] font-semibold text-white/80">
            {server.memoryUsage?.used || 0} / {server.memoryUsage?.total || 128} GB
          </div>
          <div className="mt-2 h-2 bg-white/[0.06] rounded-full overflow-hidden">
            <div
              className="h-full bg-[#22c55e] rounded-full"
              style={{
                width: `${((server.memoryUsage?.used || 0) / (server.memoryUsage?.total || 128)) * 100}%`,
              }}
            />
          </div>
        </div>
      </div>

      <Link
        to="/dashboard/servers"
        className="inline-flex items-center gap-1.5 text-[12px] text-[#8b5cf6] hover:text-[#a78bfa] transition-colors"
      >
        Manage servers <ExternalLink size={12} />
      </Link>
    </div>
  )
}
