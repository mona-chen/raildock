import { useState, useMemo } from 'react'
import { Trash2, Loader2, Globe, Server, Cpu, Wrench, AlertTriangle, Lock, Unlock, FileCode, Copy, Check, Github, GitBranch, Folder, ExternalLink } from 'lucide-react'
import { useNavigate, useParams } from 'react-router-dom'
import type { GitSource, Service } from '@/types'
import { useUpdateService, useUpdateServiceConfig, useDestroyService } from '@/hooks/useServices'
import { useCopy } from '@/hooks/useCopy'
import { api } from '@/lib/api'
import AccessibleToggle from '@/features/shared/AccessibleToggle'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { useGitSources, useGitSourceBranches, useGitSourceDirectories } from '@/hooks/useGitSources'
import { useProject } from '@/hooks/useProjects'
import { useServers } from '@/hooks/useServers'
import { useNetworks } from '@/hooks/useModules'

const tabs = [
  { key: 'general', label: 'General', icon: Server },
  { key: 'deploy', label: 'Deploy', icon: Server },
  { key: 'network', label: 'Networking', icon: Globe },
  { key: 'resources', label: 'Resources', icon: Cpu },
  { key: 'advanced', label: 'Advanced', icon: Wrench },
  { key: 'danger', label: 'Danger Zone', icon: AlertTriangle },
] as const

function ManifestBanner({ svc }: { svc: Service }) {
  const navigate = useNavigate()
  const { projectId } = useParams<{ projectId: string }>()

  if (svc.managedBy === 'ui' || !svc.managedBy) return null

  const isManifest = svc.managedBy === 'manifest'
  const isHybrid = svc.managedBy === 'hybrid'

  return (
    <div className={`mb-4 p-3 rounded-lg border ${
      isManifest
        ? 'bg-[#8b5cf6]/5 border-[#8b5cf6]/15'
        : 'bg-amber-500/5 border-amber-500/15'
    }`}>
      <div className="flex items-center gap-2">
        <FileCode size={14} className={isManifest ? 'text-[#8b5cf6]' : 'text-amber-400'} />
        <span className={`text-[12px] font-medium ${isManifest ? 'text-[#8b5cf6]' : 'text-amber-400'}`}>
          {isManifest ? 'Managed by Manifest' : 'Hybrid Mode'}
        </span>
      </div>
      <div className="text-[11px] text-white/40 mt-1">
        {isManifest
          ? 'This service is fully controlled by the project manifest. Edit in the Manifest Editor to make changes.'
          : 'This service is mostly managed by the manifest, but UI overrides are allowed for certain fields.'}
      </div>
      <button
        onClick={() => navigate(`/dashboard/project/${projectId}/manifest`)}
        className={`mt-2 text-[11px] hover:underline ${isManifest ? 'text-[#8b5cf6]' : 'text-amber-400'}`}
      >
        Open Manifest Editor →
      </button>
    </div>
  )
}

export function SettingsPanel({ svc }: { svc: Service }) {
  const [tab, setTab] = useState<string>('general')

  return (
    <div className="flex h-full">
      <div className="w-[180px] border-r border-white/[0.06] bg-[#0f0f13] p-3 space-y-0.5 flex-shrink-0">
        {tabs.map((t) => (
          <button
            key={t.key}
            onClick={() => setTab(t.key)}
            className={`w-full text-left px-3 py-2 rounded-lg text-[12px] transition-all flex items-center gap-2 ${
              tab === t.key ? 'bg-white/[0.06] text-white/70' : 'text-white/40 hover:text-white/60'
            }`}
          >
            <t.icon size={13} />
            {t.label}
          </button>
        ))}
      </div>
      <div className="flex-1 overflow-y-auto p-5">
        <ManifestBanner svc={svc} />
        {tab === 'general' && <GeneralSettings svc={svc} />}
        {tab === 'deploy' && <DeploySettings svc={svc} />}
        {tab === 'network' && <NetworkSettings svc={svc} />}
        {tab === 'resources' && <ResourceSettings svc={svc} />}
        {tab === 'advanced' && <AdvancedSettings svc={svc} />}
        {tab === 'danger' && <DangerZone svc={svc} />}
      </div>
    </div>
  )
}

// ── Helper: update config nested property ──────────────────
function useConfigUpdater(svc: Service) {
  const updateConfig = useUpdateServiceConfig()
  const updateService = useUpdateService()

  const setConfigPath = (path: string, value: unknown) => {
    const keys = path.split('.')
    const next = { ...svc.config } as Record<string, unknown>
    let cur: Record<string, unknown> = next
    for (let i = 0; i < keys.length - 1; i++) {
      cur[keys[i]] = { ...(cur[keys[i]] as Record<string, unknown> || {}) }
      cur = cur[keys[i]] as Record<string, unknown>
    }
    cur[keys[keys.length - 1]] = value
    updateConfig.mutate({ id: svc.id, config: next })
  }

  const setField = (field: keyof Service, value: unknown) => {
    updateService.mutate({ id: svc.id, data: { [field]: value } })
  }

  return { setConfigPath, setField, isPending: updateConfig.isPending || updateService.isPending }
}

// ── Git helpers ────────────────────────────────────────────
function parseRepoFullName(repo?: string): string | null {
  if (!repo) return null
  const urlMatch = repo.match(/github\.com[:/]([^/]+)\/([^/]+?)(?:\.git)?$/)
  if (urlMatch) return `${urlMatch[1]}/${urlMatch[2]}`
  const parts = repo.split('/').filter(Boolean)
  if (parts.length === 2) return `${parts[0]}/${parts[1].replace(/\.git$/, '')}`
  return null
}

function findGitSourceForRepo(sources: GitSource[] | undefined, repo?: string): GitSource | undefined {
  const fullName = parseRepoFullName(repo)
  if (!fullName || !sources) return undefined
  return sources.find((source) =>
    source.repos.some((r) => r.fullName === fullName || parseRepoFullName(r.fullName) === fullName)
  )
}

// ── General Settings ───────────────────────────────────────
function GeneralSettings({ svc }: { svc: Service }) {
  const { setConfigPath, setField } = useConfigUpdater(svc)
  const isApp = svc.type === 'app'

  return (
    <div className="space-y-5">
      <SettingCard title="Display Name" description="Renames the service in RailDock. The underlying Dokku app name does not change.">
        <TextField label="Name" value={svc.name} placeholder="my-app" onChange={(v) => setField('name', v)} />
      </SettingCard>

      {isApp && (
        <SettingCard title="Container Port" description="The port your app listens on inside the container. Leave blank to auto-detect (defaults to 5000). Set this when your app uses a fixed port like 3000.">
          <TextField
            label="Port"
            type="number"
            value={svc.port?.toString() ?? ''}
            placeholder="3000"
            onChange={(v) => setField('port', v ? parseInt(v, 10) : null)}
          />
        </SettingCard>
      )}

      {isApp && (
        <>
          <div>
            <SectionTitle>Source</SectionTitle>
            <SourceSection svc={svc} setField={setField} />
          </div>

          <SettingCard title="Builder" description="How your app is built">
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
              {(['railpack', 'nixpacks', 'dockerfile', 'herokuish', 'pack'] as const).map((b) => (
                <label
                  key={b}
                  className={`flex items-center gap-3 p-3 border rounded-lg cursor-pointer transition-all ${
                    svc.builder === b ? 'border-[#8b5cf6]/40 bg-[#8b5cf6]/5' : 'border-white/[0.06] bg-[#1a1a1e] hover:border-white/[0.12]'
                  }`}
                >
                  <input
                    type="radio"
                    name="builder"
                    checked={svc.builder === b}
                    onChange={() => setField('builder', b)}
                    className="accent-[#8b5cf6]"
                  />
                  <span className="text-[13px] text-white/70 capitalize">{b}</span>
                </label>
              ))}
            </div>
          </SettingCard>

          <SettingCard title="Deploy Options">
            <div className="flex items-center justify-between">
              <div>
                <div className="text-[13px] text-white/70">Auto-deploy</div>
                <div className="text-[11px] text-white/40">Automatically deploy on git push</div>
              </div>
              <AccessibleToggle checked={svc.autoDeploy} onChange={(v) => setField('autoDeploy', v)} label="Auto-deploy" />
            </div>
            {svc.webhookUrl && (
              <div className="border-t border-white/[0.06] pt-4 mt-4">
                <div className="text-[13px] text-white/70 mb-1">Deploy Webhook</div>
                <div className="text-[11px] text-white/40 mb-2">Use this URL in your CI/CD pipeline to trigger deployments.</div>
                <div className="flex items-center gap-2">
                  <code className="flex-1 bg-black/30 rounded-lg px-3 py-2 text-[11px] font-mono text-white/50 truncate">
                    {svc.webhookUrl}
                  </code>
                  <CopyButton text={svc.webhookUrl} />
                </div>
              </div>
            )}
          </SettingCard>
        </>
      )}

      {!isApp && (
        <SettingCard title="Source">
          <TextField label="Docker Image" value={svc.dockerImage || ''} placeholder="postgres:15" onChange={(v) => setField('dockerImage', v)} />
          <TextField label="Version" value={svc.version || ''} onChange={(v) => setField('version', v)} />
        </SettingCard>
      )}
    </div>
  )
}

function SourceSection({ svc, setField }: { svc: Service; setField: (field: keyof Service, value: unknown) => void }) {
  const { data: sources } = useGitSources()
  const source = useMemo(() => findGitSourceForRepo(sources, svc.gitRepo), [sources, svc.gitRepo])
  const repoFullName = parseRepoFullName(svc.gitRepo) || svc.gitRepo || ''

  return (
    <div className="space-y-4">
      {svc.gitRepo ? (
        <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-4">
          <div className="flex items-center justify-between gap-3">
            <div className="flex items-center gap-3 min-w-0">
              <div className="w-9 h-9 rounded-lg bg-white/[0.06] flex items-center justify-center flex-shrink-0">
                <Github size={18} className="text-white/70" />
              </div>
              <div className="min-w-0">
                <div className="text-[13px] font-medium text-white/80 truncate">{repoFullName}</div>
                <a
                  href={svc.gitRepo}
                  target="_blank"
                  rel="noreferrer"
                  className="text-[11px] text-white/40 hover:text-[#8b5cf6] flex items-center gap-1"
                >
                  View repository <ExternalLink size={10} />
                </a>
              </div>
            </div>
            <button
              onClick={() => setField('gitRepo', '')}
              className="px-3 py-1.5 text-[12px] text-white/50 hover:text-white/80 hover:bg-white/[0.06] rounded-lg transition-all border border-white/[0.08] flex-shrink-0"
            >
              Disconnect
            </button>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4 pt-4 border-t border-white/[0.06]">
            <BranchField repoFullName={repoFullName} sourceId={source?.id} branch={svc.branch || 'main'} onChange={(v) => setField('branch', v)} />
            <DirectoryField repoFullName={repoFullName} sourceId={source?.id} branch={svc.branch || 'main'} directory={svc.rootDirectory || '.'} onChange={(v) => setField('rootDirectory', v)} />
          </div>
        </div>
      ) : (
        <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-4 space-y-3">
          <TextField
            label="Git Repository"
            value={svc.gitRepo || ''}
            placeholder="https://github.com/user/repo"
            onChange={(v) => setField('gitRepo', v)}
          />
          <div className="text-[11px] text-white/40">Connect a GitHub repository to enable branch and directory selectors.</div>
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <SettingCard title="Docker Image" description="Override the deployed image (optional)">
          <TextField label="Image" value={svc.dockerImage || ''} placeholder="nginx:alpine" onChange={(v) => setField('dockerImage', v)} />
        </SettingCard>
        <SettingCard title="Start Command" description="Override the container start command (optional)">
          <TextField label="Command" value={svc.startCommand || ''} placeholder="bundle exec puma" onChange={(v) => setField('startCommand', v)} />
        </SettingCard>
      </div>
    </div>
  )
}

function BranchField({ repoFullName, sourceId, branch, onChange }: { repoFullName: string; sourceId?: string; branch: string; onChange: (v: string) => void }) {
  const { data, isLoading, error } = useGitSourceBranches(sourceId, repoFullName)
  const branches = data?.branches || []
  const canSelect = !!sourceId && branches.length > 0

  return (
    <div>
      <div className="flex items-center gap-2 mb-1.5">
        <GitBranch size={13} className="text-white/40" />
        <span className="text-[12px] text-white/60">Deploy Branch</span>
      </div>
      <div className="text-[11px] text-white/35 mb-2">Changes pushed to this branch will deploy automatically.</div>
      {canSelect ? (
        <Select value={branch} onValueChange={onChange}>
          <SelectTrigger className="w-full bg-black/40 border border-white/[0.08] rounded-lg px-3 py-2 text-[13px] text-white/80 focus:outline-none focus:border-[#8b5cf6]/40">
            <SelectValue placeholder="Select branch" />
          </SelectTrigger>
          <SelectContent>
            {branches.map((b) => (
              <SelectItem key={b} value={b}>{b}</SelectItem>
            ))}
          </SelectContent>
        </Select>
      ) : (
        <div className="relative">
          <input
            type="text"
            value={branch}
            onChange={(e) => onChange(e.target.value)}
            className="w-full bg-black/40 border border-white/[0.08] rounded-lg px-3 py-2 text-[13px] text-white/80 focus:outline-none focus:border-[#8b5cf6]/40"
            placeholder="main"
          />
          {isLoading && <Loader2 size={14} className="absolute right-3 top-1/2 -translate-y-1/2 text-white/30 animate-spin" />}
          {error && <div className="text-[10px] text-red-300/70 mt-1">Could not load branches</div>}
        </div>
      )}
    </div>
  )
}

function DirectoryField({ repoFullName, sourceId, branch, directory, onChange }: { repoFullName: string; sourceId?: string; branch: string; directory: string; onChange: (v: string) => void }) {
  const { data, isLoading, error } = useGitSourceDirectories(sourceId, repoFullName, branch)
  const directories = data?.directories || []
  const canSelect = !!sourceId && directories.length > 0

  return (
    <div>
      <div className="flex items-center gap-2 mb-1.5">
        <Folder size={13} className="text-white/40" />
        <span className="text-[12px] text-white/60">Root Directory</span>
      </div>
      <div className="text-[11px] text-white/35 mb-2">Where your app code lives inside the repository.</div>
      {canSelect ? (
        <Select value={directory || '.'} onValueChange={onChange}>
          <SelectTrigger className="w-full bg-black/40 border border-white/[0.08] rounded-lg px-3 py-2 text-[13px] text-white/80 focus:outline-none focus:border-[#8b5cf6]/40">
            <SelectValue placeholder="Select directory" />
          </SelectTrigger>
          <SelectContent className="max-h-[240px]">
            {directories.map((d) => (
              <SelectItem key={d} value={d}>{d === '.' ? '/' : `/${d}`}</SelectItem>
            ))}
          </SelectContent>
        </Select>
      ) : (
        <div className="relative">
          <input
            type="text"
            value={directory}
            onChange={(e) => onChange(e.target.value)}
            className="w-full bg-black/40 border border-white/[0.08] rounded-lg px-3 py-2 text-[13px] text-white/80 focus:outline-none focus:border-[#8b5cf6]/40"
            placeholder="./"
          />
          {isLoading && <Loader2 size={14} className="absolute right-3 top-1/2 -translate-y-1/2 text-white/30 animate-spin" />}
          {error && <div className="text-[10px] text-red-300/70 mt-1">Could not load directories</div>}
        </div>
      )}
    </div>
  )
}

// ── Deploy Settings ────────────────────────────────────────
function DeploySettings({ svc }: { svc: Service }) {
  const { setConfigPath, setField } = useConfigUpdater(svc)
  const checks = {
    enabled: svc.checks?.enabled ?? false,
    mode: svc.checks?.mode ?? 'enabled',
    wait: svc.checks?.wait ?? 5,
    timeout: svc.checks?.timeout ?? 30,
    attempts: svc.checks?.attempts ?? 5,
    waitToRetire: svc.checks?.waitToRetire ?? 60,
    skipList: svc.checks?.skipList ?? [],
  }

  return (
    <div className="space-y-4">
      <SectionTitle>Deploy</SectionTitle>

      <SettingCard title="Restart Policy">
        <Select value={svc.restartPolicy} onValueChange={(v) => setField('restartPolicy', v)}>
          <SelectTrigger className="w-full bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40">
            <SelectValue placeholder="Select restart policy" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="on-failure">On Failure</SelectItem>
            <SelectItem value="always">Always</SelectItem>
            <SelectItem value="unless-stopped">Unless Stopped</SelectItem>
            <SelectItem value="never">Never</SelectItem>
          </SelectContent>
        </Select>
        <div className="mt-2">
          <TextField label="Max Retries" type="number" value={String(svc.restartMaxRetries)} onChange={(v) => setField('restartMaxRetries', parseInt(v) || 0)} />
        </div>
      </SettingCard>

      <SettingCard title="Health Checks">
        <div className="mb-3 flex items-start justify-between gap-4">
          <div><div className="text-[13px] text-white/70">Zero-downtime policy</div><div className="mt-0.5 text-[11px] leading-4 text-white/35">Keep the old container serving until the replacement is ready and connections drain.</div></div>
          <Select value={checks.mode} onValueChange={(v) => { setConfigPath('checks.mode', v); setConfigPath('checks.enabled', v === 'enabled') }}>
            <SelectTrigger className="rounded border border-white/[0.08] bg-black/40 px-2 py-1.5 text-[11px] text-white/65 focus:outline-none focus:border-[#8b5cf6]/40">
              <SelectValue placeholder="Select check mode" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="enabled">Enabled</SelectItem>
              <SelectItem value="skipped">Skip checks</SelectItem>
              <SelectItem value="disabled">Disable rolling deploy</SelectItem>
            </SelectContent>
          </Select>
        </div>
        {checks.mode === 'disabled' && <div className="mb-3 rounded-md border border-red-500/15 bg-red-500/5 px-3 py-2 text-[11px] leading-4 text-red-300/70">Downtime expected: old containers stop before replacements start.</div>}
        {checks.mode === 'enabled' && (
          <div className="grid grid-cols-2 gap-3">
            <TextField label="Wait (seconds)" type="number" value={String(checks.wait)} onChange={(v) => setConfigPath('checks.wait', parseInt(v) || 0)} />
            <TextField label="Timeout (seconds)" type="number" value={String(checks.timeout)} onChange={(v) => setConfigPath('checks.timeout', parseInt(v) || 0)} />
            <TextField label="Attempts" type="number" value={String(checks.attempts)} onChange={(v) => setConfigPath('checks.attempts', parseInt(v) || 1)} />
            <TextField label="Drain window (seconds)" type="number" value={String(checks.waitToRetire)} onChange={(v) => setConfigPath('checks.waitToRetire', parseInt(v) || 0)} />
          </div>
        )}
      </SettingCard>

      <SettingCard title="Maintenance Mode">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-[13px] text-white/70">Maintenance Mode</div>
            <div className="text-[11px] text-white/40">Serve a maintenance page for all requests</div>
          </div>
          <AccessibleToggle checked={svc.maintenanceMode} onChange={(v) => setField('maintenanceMode', v)} label="Maintenance mode" />
        </div>
      </SettingCard>

      <SecuritySettings svc={svc} />
    </div>
  )
}

// ── Network Settings ───────────────────────────────────────
function NetworkSettings({ svc }: { svc: Service }) {
  const { setConfigPath, setField } = useConfigUpdater(svc)
  const proxy = {
    enabled: svc.proxy?.enabled ?? true,
    proxyType: svc.proxy?.proxyType ?? 'traefik',
    portMappings: svc.proxy?.portMappings ?? [],
  }
  const letsencrypt = {
    enabled: svc.letsencrypt?.enabled ?? false,
    email: svc.letsencrypt?.email ?? '',
    staging: svc.letsencrypt?.staging ?? false,
    autoRenew: svc.letsencrypt?.autoRenew ?? true,
  }

  const externalNetworks = svc.externalNetworks ?? []
  const { data: project } = useProject(svc.projectId)
  const { data: servers = [] } = useServers()
  const server = servers.find((s) => s.id === project?.serverId)
  const { data: networks = [] } = useNetworks(server?.id)
  const connectableNetworks = networks.filter((n) => n.connectable !== false)

  const toggleExternalNetwork = (networkName: string) => {
    const next = externalNetworks.includes(networkName)
      ? externalNetworks.filter((n) => n !== networkName)
      : [...externalNetworks, networkName]
    setField('externalNetworks', next)
  }

  const addPort = () => {
    const next = [...proxy.portMappings, { scheme: 'http', hostPort: 80, containerPort: 3000 }]
    setConfigPath('proxy.portMappings', next)
  }

  const updatePort = (idx: number, patch: Partial<{ scheme: string; hostPort: number; containerPort: number }>) => {
    const next = proxy.portMappings.map((pm, i) => (i === idx ? { ...pm, ...patch } : pm))
    setConfigPath('proxy.portMappings', next)
  }

  const removePort = (idx: number) => {
    const next = proxy.portMappings.filter((_, i) => i !== idx)
    setConfigPath('proxy.portMappings', next)
  }

  return (
    <div className="space-y-4">
      <SectionTitle>Networking</SectionTitle>

      <SettingCard title="Proxy">
        <div className="flex items-center justify-between mb-3">
          <div className="text-[13px] text-white/70">Enabled</div>
          <AccessibleToggle checked={proxy.enabled} onChange={(v) => setConfigPath('proxy.enabled', v)} label="Proxy enabled" />
        </div>
        {proxy.enabled && (
          <>
            <div className="mb-3">
              <div className="text-[11px] text-white/40 mb-1">Proxy Type</div>
              <Select value={proxy.proxyType} onValueChange={(v) => setConfigPath('proxy.proxyType', v)}>
                <SelectTrigger className="w-full bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40">
                  <SelectValue placeholder="Select proxy type" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="traefik">Traefik</SelectItem>
                  <SelectItem value="nginx">Nginx</SelectItem>
                  <SelectItem value="caddy">Caddy</SelectItem>
                  <SelectItem value="haproxy">HAProxy</SelectItem>
                  <SelectItem value="openresty">OpenResty</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </>
        )}
      </SettingCard>

      <SettingCard title="Port Mappings">
        {proxy.portMappings.length > 0 ? (
          <div className="space-y-2 mb-3">
            {proxy.portMappings.map((pm, i) => (
              <div key={i} className="flex items-center gap-2 bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-2">
                <Select value={pm.scheme} onValueChange={(v) => updatePort(i, { scheme: v })}>
                  <SelectTrigger className="bg-black/40 border border-white/[0.08] rounded px-2 py-1 text-[12px] text-white/70">
                    <SelectValue placeholder="scheme" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="http">http</SelectItem>
                    <SelectItem value="https">https</SelectItem>
                    <SelectItem value="grpc">grpc</SelectItem>
                  </SelectContent>
                </Select>
                <input
                  type="number"
                  value={pm.hostPort}
                  onChange={(e) => updatePort(i, { hostPort: parseInt(e.target.value) || 0 })}
                  className="w-20 bg-black/40 border border-white/[0.08] rounded px-2 py-1 text-[12px] text-white/70"
                  placeholder="host"
                />
                <span className="text-white/20">→</span>
                <input
                  type="number"
                  value={pm.containerPort}
                  onChange={(e) => updatePort(i, { containerPort: parseInt(e.target.value) || 0 })}
                  className="w-20 bg-black/40 border border-white/[0.08] rounded px-2 py-1 text-[12px] text-white/70"
                  placeholder="container"
                />
                <button onClick={() => removePort(i)} className="ml-auto p-1 hover:bg-white/[0.06] rounded text-white/20 hover:text-red-400">
                  <Trash2 size={12} />
                </button>
              </div>
            ))}
          </div>
        ) : (
          <div className="text-[12px] text-white/30 mb-3">No port mappings configured</div>
        )}
        <button
          onClick={addPort}
          className="px-3 py-1.5 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[12px] hover:bg-[#8b5cf6]/25 transition-all"
        >
          Add Port Mapping
        </button>
      </SettingCard>

      <SettingCard title="SSL / Let's Encrypt">
        <div className="flex items-center justify-between mb-3">
          <div className="text-[13px] text-white/70">Auto-generate Certificates</div>
          <AccessibleToggle checked={letsencrypt.enabled} onChange={(v) => setConfigPath('letsencrypt.enabled', v)} label="Let's Encrypt" />
        </div>
        {letsencrypt.enabled && (
          <div className="space-y-3">
            <TextField label="Email" value={letsencrypt.email} onChange={(v) => setConfigPath('letsencrypt.email', v)} />
            <div className="flex items-center justify-between">
              <div className="text-[12px] text-white/60">Staging Mode</div>
              <AccessibleToggle checked={letsencrypt.staging} onChange={(v) => setConfigPath('letsencrypt.staging', v)} label="Staging" />
            </div>
            <div className="flex items-center justify-between">
              <div className="text-[12px] text-white/60">Auto-renew</div>
              <AccessibleToggle checked={letsencrypt.autoRenew} onChange={(v) => setConfigPath('letsencrypt.autoRenew', v)} label="Auto-renew" />
            </div>
          </div>
        )}
      </SettingCard>

      <SettingCard title="External Networks">
        <div className="text-[12px] text-white/40 mb-3">
          Connect this service to Docker networks from other projects or stacks. The service will be reachable by container name on these networks.
        </div>
        {connectableNetworks.length > 0 ? (
          <div className="space-y-1.5">
            {connectableNetworks.map((net) => {
              const isChecked = externalNetworks.includes(net.name)
              return (
                <label
                  key={net.name}
                  className="flex items-center gap-2.5 p-2 rounded-lg bg-[#1a1a1e] border border-white/[0.06] cursor-pointer hover:border-white/[0.12] transition-colors"
                >
                  <input
                    type="checkbox"
                    checked={isChecked}
                    onChange={() => toggleExternalNetwork(net.name)}
                    className="rounded border-white/20 bg-black/40 text-[#8b5cf6] focus:ring-[#8b5cf6]/40"
                  />
                  <div className="flex-1 min-w-0">
                    <div className="text-[12px] text-white/70 truncate">{net.name}</div>
                    <div className="text-[10px] text-white/30">
                      {net.driver}{net.containers?.length != null ? ` · ${net.containers.length} container(s)` : ''}
                    </div>
                  </div>
                </label>
              )
            })}
          </div>
        ) : (
          <div className="text-[12px] text-white/30">
            {server ? 'No connectable networks found on this server.' : 'No server assigned to this project.'}
          </div>
        )}
        {externalNetworks.length > 0 && (
          <div className="mt-2 flex flex-wrap gap-1.5">
            {externalNetworks.map((name) => (
              <span key={name} className="inline-flex items-center gap-1 px-2 py-0.5 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded text-[11px]">
                {name}
                <button onClick={() => toggleExternalNetwork(name)} className="hover:text-white/70">
                  <Trash2 size={10} />
                </button>
              </span>
            ))}
          </div>
        )}
      </SettingCard>
    </div>
  )
}

// ── Resource Settings ──────────────────────────────────────
function ResourceSettings({ svc }: { svc: Service }) {
  const { setConfigPath } = useConfigUpdater(svc)
  const limits = svc.resourceLimits || []
  const reservations = svc.resourceReservations || []

  const updateLimit = (processType: string, field: string, value: string) => {
    const next = limits.map((r) => (r.processType === processType ? { ...r, [field]: value || undefined } : r))
    if (!next.find((r) => r.processType === processType)) {
      next.push({ processType, [field]: value })
    }
    setConfigPath('resourceLimits', next)
  }

  const updateReservation = (processType: string, field: string, value: string) => {
    const next = reservations.map((r) => (r.processType === processType ? { ...r, [field]: value || undefined } : r))
    if (!next.find((r) => r.processType === processType)) {
      next.push({ processType, [field]: value })
    }
    setConfigPath('resourceReservations', next)
  }

  return (
    <div className="space-y-4">
      <SectionTitle>Resources</SectionTitle>

      {svc.processTypes && svc.processTypes.length > 0 ? (
        svc.processTypes.map((pt) => {
          const limit = limits.find((r) => r.processType === pt.name) || { processType: pt.name }
          const reserve = reservations.find((r) => r.processType === pt.name) || { processType: pt.name }
          return (
            <SettingCard key={pt.name} title={`Process: ${pt.name}`}>
              <div className="space-y-4">
                <div className="text-[11px] text-white/40 uppercase tracking-wide">Limits</div>
                <div className="grid grid-cols-2 gap-2">
                  <ResourceInput label="CPU" value={(limit as unknown as Record<string, string>).cpu || ''} onChange={(v) => updateLimit(pt.name, 'cpu', v)} />
                  <ResourceInput label="Memory" value={(limit as unknown as Record<string, string>).memory || ''} onChange={(v) => updateLimit(pt.name, 'memory', v)} />
                  <ResourceInput label="Swap" value={(limit as unknown as Record<string, string>).memorySwap || ''} onChange={(v) => updateLimit(pt.name, 'memorySwap', v)} />
                  <ResourceInput label="NVIDIA GPU" value={String((limit as unknown as Record<string, unknown>).nvidiaGpu || '')} onChange={(v) => updateLimit(pt.name, 'nvidiaGpu', v)} />
                </div>
                <div className="text-[11px] text-white/40 uppercase tracking-wide">Reservations</div>
                <div className="grid grid-cols-2 gap-2">
                  <ResourceInput label="CPU" value={(reserve as unknown as Record<string, string>).cpu || ''} onChange={(v) => updateReservation(pt.name, 'cpu', v)} />
                  <ResourceInput label="Memory" value={(reserve as unknown as Record<string, string>).memory || ''} onChange={(v) => updateReservation(pt.name, 'memory', v)} />
                  <ResourceInput label="Swap" value={(reserve as unknown as Record<string, string>).memorySwap || ''} onChange={(v) => updateReservation(pt.name, 'memorySwap', v)} />
                </div>
              </div>
            </SettingCard>
          )
        })
      ) : (
        <SettingCard title="Resources">
          <div className="text-[12px] text-white/30">No process types configured. Deploy this service to detect process types.</div>
        </SettingCard>
      )}
    </div>
  )
}

// ── Advanced Settings ──────────────────────────────────────
function AdvancedSettings({ svc }: { svc: Service }) {
  const { setConfigPath } = useConfigUpdater(svc)
  const [newPhase, setNewPhase] = useState<'build' | 'deploy' | 'run'>('run')
  const [newOption, setNewOption] = useState('')
  const [schedule, setSchedule] = useState('')
  const [command, setCommand] = useState('')

  const options = svc.dockerOptions || []
  const jobs = (svc.config?.cron as Array<{ schedule: string; command: string }>) || []

  const addOption = () => {
    if (!newOption.trim()) return
    setConfigPath('dockerOptions', [...options, { phase: newPhase, option: newOption.trim() }])
    setNewOption('')
  }

  const removeOption = (idx: number) => {
    setConfigPath('dockerOptions', options.filter((_, i) => i !== idx))
  }

  const addJob = () => {
    if (!schedule.trim() || !command.trim()) return
    const next = [...jobs, { schedule: schedule.trim(), command: command.trim() }]
    setConfigPath('cron', next)
    setSchedule('')
    setCommand('')
  }

  const removeJob = (idx: number) => {
    const next = jobs.filter((_, i) => i !== idx)
    setConfigPath('cron', next)
  }

  return (
    <div className="space-y-4">
      <SectionTitle>Advanced</SectionTitle>

      <SettingCard title="Docker Options">
        {options.length > 0 ? (
          <div className="space-y-2 mb-3">
            {options.map((opt, i) => (
              <div key={i} className="flex items-center gap-2 bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-2.5 group">
                <span className="text-[10px] px-1.5 py-0.5 bg-white/[0.06] text-white/40 rounded uppercase">{opt.phase}</span>
                <span className="text-[12px] text-white/60 font-mono flex-1 truncate">{opt.option}</span>
                <button onClick={() => removeOption(i)} className="p-1 hover:bg-white/[0.06] rounded text-white/20 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity">
                  <Trash2 size={12} />
                </button>
              </div>
            ))}
          </div>
        ) : (
          <div className="text-[12px] text-white/30 mb-3">No docker options configured</div>
        )}
        <div className="flex gap-2">
          <Select value={newPhase} onValueChange={(v) => setNewPhase(v as 'build' | 'deploy' | 'run')}>
            <SelectTrigger className="bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] text-white/70">
              <SelectValue placeholder="phase" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="build">build</SelectItem>
              <SelectItem value="deploy">deploy</SelectItem>
              <SelectItem value="run">run</SelectItem>
            </SelectContent>
          </Select>
          <input
            type="text"
            placeholder="--add-host=host.docker.internal:host-gateway"
            value={newOption}
            onChange={(e) => setNewOption(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && addOption()}
            className="flex-1 bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] font-mono text-white/70"
          />
          <button onClick={addOption} className="px-3 py-1.5 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[12px] hover:bg-[#8b5cf6]/25 transition-all">
            Add
          </button>
        </div>
      </SettingCard>

      <SettingCard title="Cron Jobs">
        {jobs.length > 0 ? (
          <div className="space-y-2 mb-3">
            {jobs.map((job, i) => (
              <div key={i} className="flex items-center gap-2 bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-2.5 group">
                <span className="text-[10px] px-1.5 py-0.5 bg-[#8b5cf6]/10 text-[#8b5cf6] rounded font-mono">{job.schedule}</span>
                <span className="text-[12px] text-white/60 font-mono flex-1 truncate">{job.command}</span>
                <button onClick={() => removeJob(i)} className="p-1 hover:bg-white/[0.06] rounded text-white/20 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity">
                  <Trash2 size={12} />
                </button>
              </div>
            ))}
          </div>
        ) : (
          <div className="text-[12px] text-white/30 mb-3">No cron jobs configured</div>
        )}
        <div className="flex gap-2">
          <input
            type="text"
            placeholder="*/5 * * * *"
            value={schedule}
            onChange={(e) => setSchedule(e.target.value)}
            className="w-32 bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] font-mono text-white/70"
          />
          <input
            type="text"
            placeholder="rake tasks:run"
            value={command}
            onChange={(e) => setCommand(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && addJob()}
            className="flex-1 bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] font-mono text-white/70"
          />
          <button onClick={addJob} className="px-3 py-1.5 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[12px] hover:bg-[#8b5cf6]/25 transition-all">
            Add
          </button>
        </div>
      </SettingCard>
    </div>
  )
}

// ── Danger Zone ────────────────────────────────────────────
function DangerZone({ svc }: { svc: Service }) {
  const navigate = useNavigate()
  const destroyService = useDestroyService()
  const [showConfirm, setShowConfirm] = useState(false)
  const [confirmName, setConfirmName] = useState('')

  const isConfirmValid = confirmName === svc.name

  const handleDestroy = () => {
    if (!isConfirmValid) return
    setShowConfirm(false)
    setConfirmName('')
    destroyService.mutate(svc.id, {
      onSuccess: () => navigate(`/dashboard`), // go back to projects list after destroy
    })
  }

  const handleClose = () => {
    setShowConfirm(false)
    setConfirmName('')
  }

  return (
    <>
      <div className="space-y-4">
        <SectionTitle className="text-red-400">Danger Zone</SectionTitle>
        <div className="bg-red-500/5 border border-red-500/20 rounded-lg p-4 space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-[13px] text-white/70">Destroy Service</div>
              <div className="text-[11px] text-white/40 mt-0.5">
                Permanently delete {svc.name} and all associated data. This cannot be undone.
              </div>
            </div>
            <button
              onClick={() => setShowConfirm(true)}
              disabled={destroyService.isPending}
              className="px-3 py-2 bg-red-500/15 text-red-400 rounded-lg text-[12px] font-medium hover:bg-red-500/25 transition-all disabled:opacity-50 flex items-center gap-1.5"
            >
              <Trash2 size={13} />
              {destroyService.isPending ? 'Destroying...' : 'Destroy'}
            </button>
          </div>
        </div>
      </div>

      {showConfirm && (
        <div
          className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-center justify-center px-4"
          onClick={handleClose}
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
                <h3 className="text-base font-semibold text-white">Destroy Service</h3>
                <p className="text-xs text-[#6B6B7B]">This action cannot be undone</p>
              </div>
            </div>

            <p className="text-sm text-[#A0A0B0] mb-4">
              You are about to permanently destroy{' '}
              <span className="font-medium text-white">{svc.name}</span>
              . This will remove the Dokku app and all data including databases, storage, and logs.
            </p>

            <div className="mb-4">
              <label className="text-[11px] text-[#6B6B7B] block mb-1.5">
                Type <span className="font-mono font-medium text-white">{svc.name}</span> to confirm
              </label>
              <input
                value={confirmName}
                onChange={(e) => setConfirmName(e.target.value)}
                className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-red-500/50 placeholder-[#4A4A55]"
                placeholder={svc.name}
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
                onClick={handleDestroy}
                disabled={!isConfirmValid}
                className="flex-1 py-2.5 bg-red-500 text-white text-sm font-medium rounded-lg hover:bg-red-600 transition-all disabled:opacity-30 disabled:cursor-not-allowed"
              >
                Destroy Service
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}

// ── Security (App Lock) ────────────────────────────────────
function SecuritySettings({ svc }: { svc: Service }) {
  const updateService = useUpdateService()
  const [isLocked, setIsLocked] = useState(svc.locked || false)
  const [loading, setLoading] = useState(false)

  const toggleLock = async () => {
    setLoading(true)
    try {
      const newLocked = !isLocked
      if (newLocked) {
        await api.services.app_lock(svc.id)
      } else {
        await api.services.app_unlock(svc.id)
      }
      setIsLocked(newLocked)
      updateService.mutate({ id: svc.id, data: { locked: newLocked } })
    } catch (err) {
      console.error('Failed to toggle lock:', err)
    } finally {
      setLoading(false)
    }
  }

  return (
    <SettingCard title="Security">
      <div className="flex items-center justify-between">
        <div>
          <div className="text-[13px] text-white/70">App Lock</div>
          <div className="text-[11px] text-white/40 mt-0.5">Prevent deployments when locked. Use during maintenance or migrations.</div>
        </div>
        <button
          onClick={toggleLock}
          disabled={loading}
          className={`flex items-center gap-2 px-3 py-2 rounded-lg text-[12px] font-medium transition-all disabled:opacity-50 ${
            isLocked ? 'bg-amber-500/15 text-amber-400 hover:bg-amber-500/25' : 'bg-white/5 text-white/50 hover:bg-white/10 hover:text-white/70'
          }`}
        >
          {loading ? <Loader2 size={13} className="animate-spin" /> : isLocked ? <Lock size={13} /> : <Unlock size={13} />}
          {isLocked ? 'Locked' : 'Unlocked'}
        </button>
      </div>
      {isLocked && <div className="mt-3 text-[11px] text-amber-400/60 bg-amber-500/5 rounded-lg p-2">App is locked. Deployments and rebuilds are blocked.</div>}
    </SettingCard>
  )
}

// ── Reusable UI Primitives ─────────────────────────────────
function SectionTitle({ children, className = '' }: { children: React.ReactNode; className?: string }) {
  return <div className={`text-[13px] font-medium text-white/70 mb-2 ${className}`}>{children}</div>
}

function SettingCard({ title, description, children }: { title?: string; description?: string; children: React.ReactNode }) {
  return (
    <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-4 space-y-3">
      {title && <div className="text-[13px] font-medium text-white/70">{title}</div>}
      {description && <div className="text-[11px] text-white/40">{description}</div>}
      {children}
    </div>
  )
}

function TextField({ label, value, placeholder, type = 'text', onChange }: { label: string; value: string; placeholder?: string; type?: string; onChange: (v: string) => void }) {
  return (
    <div>
      <div className="text-[11px] text-white/40 mb-1">{label}</div>
      <input
        type={type}
        value={value}
        placeholder={placeholder}
        onChange={(e) => onChange(e.target.value)}
        className="w-full bg-black/40 border border-white/[0.08] rounded px-2 py-1 text-[12px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
      />
    </div>
  )
}

function CopyButton({ text }: { text: string }) {
  const { copiedKey, copy } = useCopy(2000)
  const isCopied = copiedKey === 'settings-webhook'
  return (
    <button
      onClick={() => copy(text, 'settings-webhook')}
      className="px-3 py-2 bg-white/5 text-white/40 rounded-lg text-[11px] hover:bg-white/10 hover:text-white/60 transition-all flex items-center gap-1.5"
    >
      {isCopied ? <Check size={12} className="text-[#22c55e]" /> : <Copy size={12} />}
      {isCopied ? 'Copied' : 'Copy'}
    </button>
  )
}

function ResourceInput({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  return (
    <div>
      <div className="text-[11px] text-white/40">{label}</div>
      <input
        type="text"
        value={value}
        placeholder="—"
        onChange={(e) => onChange(e.target.value)}
        className="w-full mt-1 bg-black/40 border border-white/[0.08] rounded px-2 py-1 text-[12px] font-mono text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
      />
    </div>
  )
}
