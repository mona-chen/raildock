import { useState } from 'react'
import { useParams } from 'react-router-dom'
import {
  Box, Database, Globe, HardDrive, Network, Blocks, Server,
  Check, Plug, FolderGit2, Trash2, ArrowDownToLine, X, Layers,
} from 'lucide-react'
import { useServices } from '@/hooks/useServices'
import { useGitSources, useConnectGitSource, useDisconnectGitSource } from '@/hooks/useGitSources'
import { useProject, useUpdateProjectSharedVars } from '@/hooks/useProjects'
import { useModules, useNetworks, useTemplates, useDeployTemplate } from '@/hooks/useModules'
import { useServers } from '@/hooks/useServers'

// ── Shared Variables View ────────────────────
export function SharedVarsView() {
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
    <div className="p-5 overflow-y-auto h-full">
      <div className="text-[18px] font-semibold text-white/90 mb-1">Shared Variables</div>
      <div className="text-[13px] text-white/40 mb-5">Project-level environment variables shared across all services</div>

      {vars.length > 0 ? (
        <div className="space-y-2 mb-5">
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
      ) : (
        <div className="text-[13px] text-white/30 mb-5">No shared variables configured</div>
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

// ── Git View ─────────────────────────────────
const WEBHOOK_URL = typeof window !== 'undefined'
  ? `${window.location.protocol}//${window.location.host}/api/webhooks/deploy`
  : ''

export function GitView() {
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
    <div className="p-5 overflow-y-auto h-full">
      <div className="text-[18px] font-semibold text-white/90 mb-1">Git Sources</div>
      <div className="text-[13px] text-white/40 mb-5">Connected repositories and deployments</div>

      {connected.map((gs) => (
        <div key={gs.id} className="mb-6">
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
                  className="bg-[#16161a] border border-white/[0.06] rounded-lg p-3 flex items-center gap-3"
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
                    <button className="text-[11px] px-2 py-1 bg-white/[0.06] text-white/50 rounded hover:bg-white/[0.1]">
                      Link
                    </button>
                  )}
                </div>
              )
            })}
          </div>
          <div className="mt-3 bg-[#16161a] border border-white/[0.06] rounded-lg p-3">
            <div className="text-[11px] text-white/40 mb-1">Webhook URL — paste into {gs.provider} repository settings</div>
            <div className="flex gap-2">
              <code className="flex-1 text-[11px] font-mono text-white/50 bg-black/40 rounded px-2 py-1 truncate">{WEBHOOK_URL}</code>
              <button
                onClick={() => navigator.clipboard.writeText(WEBHOOK_URL)}
                className="text-[11px] px-2 py-1 bg-white/[0.06] text-white/50 rounded hover:bg-white/[0.1]"
              >
                Copy
              </button>
            </div>
          </div>
        </div>
      ))}

      {gitSources
        .filter((g) => !g.connected)
        .map((gs) => (
          <div
            key={gs.id}
            className="bg-[#16161a] border border-white/[0.06] rounded-xl p-4 flex items-center justify-between mb-3"
          >
            <div className="flex items-center gap-2">
              <FolderGit2 size={16} className="text-white/30" />
              <span className="text-[13px] text-white/50 capitalize">{gs.provider}</span>
            </div>
            <button
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
              <button onClick={() => setModalOpen(false)} className="flex-1 py-2.5 border border-[rgba(255,255,255,0.08)] text-[#A0A0B0] text-xs rounded-lg hover:bg-[rgba(255,255,255,0.04)]">Cancel</button>
              <button onClick={handleConnect} disabled={connect.isPending || !token.trim()} className="flex-1 py-2.5 bg-rail-purple text-white text-xs font-medium rounded-lg hover:bg-rail-purple-dark disabled:opacity-50">
                {connect.isPending ? 'Connecting...' : 'Connect'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

// ── Domains View ─────────────────────────────
export function DomainsView() {
  const { projectId } = useParams<{ projectId: string }>()
  const { data: svcs = [] } = useServices(projectId || '')
  const allDomains = svcs.flatMap((s) =>
    s.domains.map((d) => ({ ...d, serviceName: s.name, serviceId: s.id }))
  )

  return (
    <div className="p-5 overflow-y-auto h-full">
      <div className="text-[18px] font-semibold text-white/90 mb-1">Domains</div>
      <div className="text-[13px] text-white/40 mb-5">
        {allDomains.length} domain(s) across {svcs.length} service(s)
      </div>
      {allDomains.length > 0 ? (
        <div className="space-y-2">
          {allDomains.map((d, i) => (
            <div
              key={i}
              className="bg-[#16161a] border border-white/[0.06] rounded-lg p-3 flex items-center gap-3"
            >
              <Globe size={15} className="text-white/30" />
              <div className="flex-1">
                <div className="text-[13px] text-white/70">{d.hostname}</div>
                <div className="text-[11px] text-white/40">
                  → {d.serviceName}:{d.port}
                </div>
              </div>
              {d.ssl && (
                <span className="text-[10px] px-1.5 bg-[#22c55e]/10 text-[#22c55e] rounded-full">
                  SSL
                </span>
              )}
              {d.letsencrypt && (
                <span className="text-[10px] px-1.5 bg-[#8b5cf6]/10 text-[#8b5cf6] rounded-full">
                  LE
                </span>
              )}
            </div>
          ))}
        </div>
      ) : (
        <div className="text-center py-16 text-[13px] text-white/30">
          No domains configured. Add domains in service settings.
        </div>
      )}
    </div>
  )
}

// ── Storage View ─────────────────────────────
export function StorageView() {
  const { projectId } = useParams<{ projectId: string }>()
  const { data: svcs = [] } = useServices(projectId || '')
  const allMounts = svcs.flatMap((s) =>
    s.storageMounts.map((m) => ({ ...m, serviceName: s.name }))
  )

  return (
    <div className="p-5 overflow-y-auto h-full">
      <div className="text-[18px] font-semibold text-white/90 mb-1">Storage</div>
      <div className="text-[13px] text-white/40 mb-5">
        {allMounts.length} mount(s) across {svcs.length} service(s)
      </div>
      {allMounts.length > 0 ? (
        <div className="space-y-2">
          {allMounts.map((m, i) => (
            <div key={i} className="bg-[#16161a] border border-white/[0.06] rounded-lg p-3">
              <div className="flex items-center gap-2 mb-1">
                <HardDrive size={13} className="text-white/30" />
                <span className="text-[12px] text-white/60">{m.serviceName}</span>
              </div>
              <div className="text-[12px] text-white/40 font-mono">Host: {m.hostPath}</div>
              <div className="text-[12px] text-white/40 font-mono">Container: {m.containerPath}</div>
            </div>
          ))}
        </div>
      ) : (
        <div className="text-center py-16 text-[13px] text-white/30">
          No storage mounts. Configure in service settings.
        </div>
      )}
    </div>
  )
}

// ── Network View ─────────────────────────────
export function NetworkView() {
  const { data: networks = [] } = useNetworks()

  return (
    <div className="p-5 overflow-y-auto h-full">
      <div className="text-[18px] font-semibold text-white/90 mb-1">Docker Networks</div>
      <div className="text-[13px] text-white/40 mb-5">{networks.length} network(s)</div>
      <div className="space-y-3">
        {networks.map((n) => (
          <div key={n.name} className="bg-[#16161a] border border-white/[0.06] rounded-xl p-4">
            <div className="flex items-center gap-2 mb-2">
              <Network size={15} className="text-[#8b5cf6]" />
              <span className="text-[14px] font-medium text-white/80">{n.name}</span>
            </div>
            <div className="flex flex-wrap gap-1.5">
              {n.apps.map((a) => (
                <span
                  key={a}
                  className="text-[11px] px-2 py-0.5 bg-white/[0.04] text-white/50 rounded-full"
                >
                  {a}
                </span>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

// ── Plugins View ─────────────────────────────
export function PluginsView() {
  const { data: modules = [] } = useModules()

  return (
    <div className="p-5 overflow-y-auto h-full">
      <div className="text-[18px] font-semibold text-white/90 mb-1">Plugins & Modules</div>
      <div className="text-[13px] text-white/40 mb-5">Dokku plugins and available modules</div>

      <div className="text-[14px] font-medium text-white/70 mb-3">Baked-in Plugins</div>
      <div className="grid grid-cols-2 gap-2 mb-6">
        {[
          { n: 'nginx-vhosts', d: 'Nginx reverse proxy and vhost management', s: 'active' },
          { n: 'proxy', d: 'Proxy port mapping and load balancing', s: 'active' },
          { n: 'docker-options', d: 'Docker run/build options', s: 'active' },
          { n: 'resource', d: 'Resource limits and reservations', s: 'active' },
          { n: 'checks', d: 'Zero-downtime deployment checks', s: 'active' },
          { n: 'letsencrypt', d: 'Automatic SSL certificates', s: 'active' },
          { n: 'git', d: 'Git-based deployment', s: 'active' },
          { n: 'storage', d: 'Persistent storage mounts', s: 'active' },
          { n: 'network', d: 'Docker network management', s: 'active' },
        ].map((p) => (
          <div
            key={p.n}
            className="bg-[#16161a] border border-white/[0.06] rounded-lg p-3 flex items-center gap-3"
          >
            <div className="w-8 h-8 rounded-lg bg-[#22c55e]/10 flex items-center justify-center flex-shrink-0">
              <Check size={14} className="text-[#22c55e]" />
            </div>
            <div className="flex-1 min-w-0">
              <div className="text-[12px] text-white/70 font-mono">{p.n}</div>
              <div className="text-[11px] text-white/40 truncate">{p.d}</div>
            </div>
          </div>
        ))}
      </div>

      <div className="text-[14px] font-medium text-white/70 mb-3">Modules</div>
      <div className="space-y-3">
        {modules.map((m) => (
          <div key={m.id} className="bg-[#16161a] border border-white/[0.06] rounded-xl p-4">
            <div className="flex items-center gap-2 mb-2">
              <Plug size={15} className="text-[#8b5cf6]" />
              <span className="text-[14px] font-medium text-white/80">{m.name}</span>
              <span className="text-[10px] px-1.5 py-0.5 bg-white/[0.06] text-white/40 rounded-full capitalize">
                {m.category}
              </span>
            </div>
            <div className="text-[12px] text-white/50 mb-3">{m.description}</div>
            <div className="flex flex-wrap gap-1.5">
              {m.services.map((s) => (
                <span
                  key={s.subtype}
                  className="text-[11px] px-2 py-0.5 bg-white/[0.04] text-white/50 rounded-full"
                >
                  {s.name}
                </span>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

// ── Server View ──────────────────────────────
export function ServerView() {
  const { data: servers = [] } = useServers()
  const server = servers[0]

  if (!server)
    return <div className="p-5 text-[13px] text-white/30">No server connected</div>

  return (
    <div className="p-5 overflow-y-auto h-full">
      <div className="text-[18px] font-semibold text-white/90 mb-1">Server</div>
      <div className="text-[13px] text-white/40 mb-5">Dokku host information</div>

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

      <div className="grid grid-cols-2 gap-3">
        <div className="bg-[#16161a] border border-white/[0.06] rounded-xl p-4">
          <div className="text-[12px] text-white/40 mb-2">Disk Usage</div>
          <div className="text-[18px] font-semibold text-white/80">
            {server.diskUsage.used} / {server.diskUsage.total} GB
          </div>
          <div className="mt-2 h-2 bg-white/[0.06] rounded-full overflow-hidden">
            <div
              className="h-full bg-[#8b5cf6] rounded-full"
              style={{
                width: `${(server.diskUsage.used / server.diskUsage.total) * 100}%`,
              }}
            />
          </div>
        </div>
        <div className="bg-[#16161a] border border-white/[0.06] rounded-xl p-4">
          <div className="text-[12px] text-white/40 mb-2">Memory Usage</div>
          <div className="text-[18px] font-semibold text-white/80">
            {server.memoryUsage.used} / {server.memoryUsage.total} GB
          </div>
          <div className="mt-2 h-2 bg-white/[0.06] rounded-full overflow-hidden">
            <div
              className="h-full bg-[#22c55e] rounded-full"
              style={{
                width: `${(server.memoryUsage.used / server.memoryUsage.total) * 100}%`,
              }}
            />
          </div>
        </div>
      </div>
    </div>
  )
}


// ── Templates View ───────────────────────────
export function TemplatesView() {
  const { projectId } = useParams<{ projectId: string }>()
  const { data: templates = [] } = useTemplates()
  const deploy = useDeployTemplate()

  const handleDeploy = (templateId: string) => {
    if (!projectId) return
    deploy.mutate({ templateId, projectId })
  }

  return (
    <div className="p-5 overflow-y-auto h-full">
      <div className="text-[18px] font-semibold text-white/90 mb-1">Template Marketplace</div>
      <div className="text-[13px] text-white/40 mb-5">One-click deploy stacks to your project</div>

      <div className="space-y-3">
        {templates.map((t) => (
          <div key={t.id} className="bg-[#16161a] border border-white/[0.06] rounded-xl p-4">
            <div className="flex items-center gap-2 mb-2">
              <Layers size={15} className="text-[#8b5cf6]" />
              <span className="text-[14px] font-medium text-white/80">{t.name}</span>
              <span className="text-[10px] px-1.5 py-0.5 bg-white/[0.06] text-white/40 rounded-full capitalize">
                {t.category}
              </span>
            </div>
            <div className="text-[12px] text-white/50 mb-3">{t.description}</div>
            <div className="flex flex-wrap gap-1.5 mb-3">
              {t.services.map((s) => (
                <span
                  key={s.name}
                  className="text-[11px] px-2 py-0.5 bg-white/[0.04] text-white/50 rounded-full"
                >
                  {s.name} ({s.subtype})
                </span>
              ))}
            </div>
            <button
              onClick={() => handleDeploy(t.id)}
              disabled={deploy.isPending}
              className="text-[12px] px-3 py-1.5 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg hover:bg-[#8b5cf6]/25 transition-all disabled:opacity-50"
            >
              {deploy.isPending ? 'Deploying...' : 'Deploy'}
            </button>
          </div>
        ))}
      </div>
    </div>
  )
}
