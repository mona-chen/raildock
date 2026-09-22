import { useState, useMemo, useRef, useEffect, useCallback, useContext, createContext } from 'react'
import { Trash2, Loader2, Globe, Cpu, Wrench, AlertTriangle, Lock, Unlock, FileCode, Copy, Check, Github, GitBranch, ExternalLink, Search, SlidersHorizontal, Rocket } from 'lucide-react'
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
import { cn, confirmationFieldTone } from '@/lib/utils'

const tabs = [
  { key: 'general', label: 'General', icon: SlidersHorizontal },
  { key: 'source', label: 'Source', icon: GitBranch },
  { key: 'deploy', label: 'Deploy', icon: Rocket },
  // Named "Routing" rather than "Networking": the panel already has a
  // Networking tab (domains and volumes), and two different things sharing one
  // label made the settings sidebar ambiguous to read — and to click.
  { key: 'network', label: 'Routing', icon: Globe },
  { key: 'resources', label: 'Resources', icon: Cpu },
  { key: 'advanced', label: 'Advanced', icon: Wrench },
  { key: 'danger', label: 'Danger Zone', icon: AlertTriangle },
] as const

// Row titles per section, so the sidebar search can find a setting rather than
// only a section name. Searching "port" has to reach Container Port (General)
// and Port Mappings (Routing); previously it matched nothing at all because
// only the six section labels were searched. Keep in sync with the rows.
const SETTINGS_INDEX: Record<string, string[]> = {
  general: ['Display Name', 'Container Port'],
  source: [
    'Git Repository', 'Deploy Branch', 'Root Directory', 'Docker Image',
    'Start Command', 'Builder', 'Static Site', 'Publish directory',
    'Node version', 'Auto-deploy', 'Deploy Webhook',
  ],
  deploy: [
    'Restart Policy', 'Max Retries', 'Health Checks', 'Zero-downtime policy',
    'Wait', 'Timeout', 'Attempts', 'Drain window', 'Maintenance Mode', 'App Lock', 'Security',
  ],
  network: ['Proxy', 'Proxy Type', 'Port Mappings', "SSL / Let's Encrypt", 'Email', 'External Networks'],
  resources: ['CPU', 'Memory', 'Swap', 'NVIDIA GPU', 'Reservations'],
  advanced: ['Docker Options', 'Cron Jobs'],
  danger: ['Destroy Service'],
}

function ManifestBanner({ svc }: { svc: Service }) {
  const navigate = useNavigate()
  const { projectId } = useParams<{ projectId: string }>()

  if (svc.managedBy === 'ui' || !svc.managedBy) return null

  const isManifest = svc.managedBy === 'manifest'

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
      <div className="text-[11px] text-white/50 mt-1">
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

function SettingsSyncBar({ draft }: { draft: SettingsDraftState }) {
  const { status, isDirty, saveNow } = draft
  if (status === 'idle' && !isDirty) return null

  return (
    <div className="flex items-center justify-end gap-3 h-9 px-5 border-b border-white/[0.06] bg-[#0f0f13] text-[11px] flex-shrink-0">
      {status === 'saving' && (
        <span className="flex items-center gap-1.5 text-white/50">
          <Loader2 size={12} className="animate-spin" /> Saving…
        </span>
      )}
      {status === 'error' && <span className="text-red-400">Couldn’t save changes.</span>}
      {status === 'saved' && !isDirty && (
        <span className="flex items-center gap-1.5 text-[#22c55e]">
          <Check size={12} /> Saved
        </span>
      )}
      {isDirty && status !== 'saving' && (
        <button
          onClick={saveNow}
          className="px-2 py-1 rounded bg-white/[0.06] text-white/60 hover:bg-white/10 hover:text-white/80 transition-colors"
        >
          Save now
        </button>
      )}
    </div>
  )
}

export function SettingsPanel({ svc }: { svc: Service }) {
  const [tab, setTab] = useState<string>('general')
  const [filter, setFilter] = useState('')
  const draft = useSettingsDraft(svc)
  const effectiveSvc = draft.svc

  const query = filter.trim().toLowerCase()
  const rowsFor = (key: string) =>
    query ? (SETTINGS_INDEX[key] ?? []).filter((row) => row.toLowerCase().includes(query)) : []
  const visibleTabs = query
    ? tabs.filter((t) => t.label.toLowerCase().includes(query) || rowsFor(t.key).length > 0)
    : tabs

  return (
    <SettingsDraftContext.Provider value={draft}>
      <div className="flex h-full">
        <div className="w-[190px] border-r border-white/[0.06] bg-[#0f0f13] flex-shrink-0 flex flex-col">
          <div className="p-3 pb-2">
            <div className="relative">
              <Search size={12} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-[#6b6b7b]" />
              <input
                value={filter}
                onChange={(e) => setFilter(e.target.value)}
                placeholder="Filter settings…"
                aria-label="Filter settings"
                className="w-full rounded-lg bg-black/40 border border-white/[0.08] pl-7 pr-2 py-1.5 text-[12px] text-white/80 placeholder:text-[#6b6b7b] focus:outline-none focus:border-rail-purple/40"
              />
            </div>
          </div>
          <nav className="flex-1 overflow-y-auto px-2 pb-3 space-y-0.5">
            {visibleTabs.map((t) => {
              const matchedRows = rowsFor(t.key)
              const danger = t.key === 'danger'
              return (
                <div key={t.key} className={danger ? 'mt-2 border-t border-white/[0.06] pt-2' : ''}>
                  <button
                    onClick={() => setTab(t.key)}
                    aria-current={tab === t.key ? 'page' : undefined}
                    className={`w-full text-left px-3 py-2 rounded-lg text-[12px] transition-all flex items-center gap-2 ${
                      tab === t.key
                        ? danger
                          ? 'bg-red-500/10 text-red-300'
                          : 'bg-white/[0.06] text-white/85'
                        : danger
                          ? 'text-red-400/70 hover:text-red-300 hover:bg-red-500/[0.07]'
                          : 'text-white/55 hover:text-white/70 hover:bg-white/[0.03]'
                    }`}
                  >
                    <t.icon size={13} className={tab === t.key ? (danger ? 'text-red-400' : 'text-rail-purple') : ''} />
                    {t.label}
                  </button>
                  {matchedRows.length > 0 && (
                    <ul className="mb-1 ml-[26px] mt-0.5 space-y-0.5">
                      {matchedRows.map((row) => (
                        <li key={row} className="truncate text-[11px] text-[#6b6b7b]">{row}</li>
                      ))}
                    </ul>
                  )}
                </div>
              )
            })}
            {visibleTabs.length === 0 && (
              <p className="px-3 py-2 text-[11px] text-[#6b6b7b]">No settings match “{filter}”.</p>
            )}
          </nav>
        </div>
        <div className="flex-1 min-w-0 flex flex-col">
          <SettingsSyncBar draft={draft} />
          <div className="flex-1 overflow-y-auto p-5">
            {/* Cap the reading width: an unconstrained pane on a wide monitor
                stretches label and control far apart. */}
            <div className="mx-auto w-full max-w-3xl">
              <ManifestBanner svc={effectiveSvc} />
              {tab === 'general' && <GeneralSettings svc={effectiveSvc} />}
              {tab === 'source' && <SourceSettings svc={effectiveSvc} />}
              {tab === 'deploy' && <DeploySettings svc={effectiveSvc} />}
              {tab === 'network' && <NetworkSettings svc={effectiveSvc} />}
              {tab === 'resources' && <ResourceSettings svc={effectiveSvc} />}
              {tab === 'advanced' && <AdvancedSettings svc={effectiveSvc} />}
              {tab === 'danger' && <DangerZone svc={effectiveSvc} />}
            </div>
          </div>
        </div>
      </div>
    </SettingsDraftContext.Provider>
  )
}

// ── Debounced, optimistic settings sync ────────────────────
// Edits are buffered locally so a background refetch can never rewind a
// controlled input mid-typing, then flushed as a single request after a short
// pause. The panel shows a "Saving…/Saved" indicator instead of a toast per
// keystroke.
type SyncStatus = 'idle' | 'saving' | 'saved' | 'error'

interface SettingsDraftState {
  svc: Service
  setConfigPath: (path: string, value: unknown) => void
  setField: (field: keyof Service, value: unknown) => void
  status: SyncStatus
  isDirty: boolean
  saveNow: () => void
}

const SettingsDraftContext = createContext<SettingsDraftState | null>(null)

const SYNC_DEBOUNCE_MS = 600
const SYNC_SAVED_VISIBLE_MS = 2500

function useConfigUpdater(): SettingsDraftState {
  const ctx = useContext(SettingsDraftContext)
  if (!ctx) throw new Error('useConfigUpdater must be used inside SettingsPanel')
  return ctx
}

function useSettingsDraft(svc: Service): SettingsDraftState {
  const updateConfig = useUpdateServiceConfig()
  const updateService = useUpdateService()

  const [config, setConfig] = useState<Record<string, unknown>>(() => svc.config ?? {})
  const [fields, setFields] = useState<Partial<Service>>({})
  const [status, setStatus] = useState<SyncStatus>('idle')
  const [isDirty, setIsDirty] = useState(false)

  const configRef = useRef(config)
  const pendingConfig = useRef<Record<string, unknown> | null>(null)
  const pendingFields = useRef<Partial<Service>>({})
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const savedTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const inFlight = useRef(false)
  const flushRef = useRef<() => void>(() => {})

  const effectiveSvc = useMemo(
    () => ({ ...svc, ...fields, config }),
    [svc, config, fields],
  )

  const flush = useCallback(() => {
    if (timer.current) {
      clearTimeout(timer.current)
      timer.current = null
    }
    if (inFlight.current) return
    const nextConfig = pendingConfig.current
    const nextFields = pendingFields.current
    const fieldKeys = Object.keys(nextFields) as (keyof Service)[]
    if (!nextConfig && fieldKeys.length === 0) return
    pendingConfig.current = null
    pendingFields.current = {}
    inFlight.current = true
    setStatus('saving')

    let settled = 0
    let failed = false
    const jobs = (nextConfig ? 1 : 0) + (fieldKeys.length ? 1 : 0)
    const settle = () => {
      settled += 1
      if (settled < jobs) return
      inFlight.current = false
      if (failed) {
        setIsDirty(true)
        setStatus('error')
        return
      }
      if (pendingConfig.current || Object.keys(pendingFields.current).length) {
        flushRef.current()
        return
      }
      setIsDirty(false)
      setStatus('saved')
      if (savedTimer.current) clearTimeout(savedTimer.current)
      savedTimer.current = setTimeout(() => setStatus('idle'), SYNC_SAVED_VISIBLE_MS)
    }
    const fail = () => {
      failed = true
      settle()
    }
    if (nextConfig) {
      updateConfig.mutate({ id: svc.id, config: nextConfig }, { onSuccess: settle, onError: fail })
    }
    if (fieldKeys.length) {
      updateService.mutate({ id: svc.id, data: nextFields }, { onSuccess: settle, onError: fail })
    }
  }, [svc.id, updateConfig, updateService])

  useEffect(() => {
    configRef.current = config
    flushRef.current = flush
  }, [config, flush])

  const schedule = useCallback(() => {
    if (timer.current) clearTimeout(timer.current)
    timer.current = setTimeout(() => flushRef.current(), SYNC_DEBOUNCE_MS)
  }, [])

  const setConfigPath = useCallback((path: string, value: unknown) => {
    const keys = path.split('.')
    const next = { ...configRef.current } as Record<string, unknown>
    let cur: Record<string, unknown> = next
    for (let i = 0; i < keys.length - 1; i++) {
      cur[keys[i]] = { ...(cur[keys[i]] as Record<string, unknown> || {}) }
      cur = cur[keys[i]] as Record<string, unknown>
    }
    cur[keys[keys.length - 1]] = value
    setConfig(next)
    pendingConfig.current = next
    setIsDirty(true)
    setStatus('idle')
    schedule()
  }, [schedule])

  const setField = useCallback((field: keyof Service, value: unknown) => {
    pendingFields.current = { ...pendingFields.current, [field]: value }
    setFields((prev) => ({ ...prev, [field]: value }))
    setIsDirty(true)
    setStatus('idle')
    schedule()
  }, [schedule])

  const serverRef = useRef(svc)
  useEffect(() => {
    const previous = serverRef.current
    serverRef.current = svc
    if (previous.id !== svc.id) {
      pendingConfig.current = null
      pendingFields.current = {}
      setConfig(svc.config ?? {})
      setFields({})
      setIsDirty(false)
      setStatus('idle')
      return
    }
    // Adopt server truth on a background refetch, but never while the user has
    // unsaved edits or a request is still in flight.
    if (!isDirty && !inFlight.current) {
      setConfig(svc.config ?? {})
      setFields({})
    }
  }, [svc, isDirty])

  // Best-effort flush so a pending edit is not lost when the panel unmounts.
  useEffect(() => () => {
    if (timer.current) clearTimeout(timer.current)
    if (savedTimer.current) clearTimeout(savedTimer.current)
    if (pendingConfig.current || Object.keys(pendingFields.current).length) flushRef.current()
  }, [])

  return useMemo(
    () => ({ svc: effectiveSvc, setConfigPath, setField, status, isDirty, saveNow: flush }),
    [effectiveSvc, setConfigPath, setField, status, isDirty, flush],
  )
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
  const { setField } = useConfigUpdater()
  const isApp = svc.type === 'app'

  return (
    <SettingsGroup>
      <SettingCard title="Display Name" description="Renames the service in RailDock. The underlying Dokku app name does not change.">
        <TextField label="Name" hideLabel value={svc.name} placeholder="my-app" onChange={(v) => setField('name', v)} />
      </SettingCard>

      {isApp && (
        <SettingCard title="Container Port" description="Port your app listens on inside the container. Leave blank to auto-detect it.">
          <TextField
            label="Port"
            hideLabel
            type="number"
            value={svc.port?.toString() ?? ''}
            placeholder="3000"
            onChange={(v) => setField('port', v ? parseInt(v, 10) : null)}
          />
        </SettingCard>
      )}
    </SettingsGroup>
  )
}

// ── Source Settings ────────────────────────────────────────
// Repository, build and deploy-trigger settings used to sit in General, which
// left that one section holding 15 of the tab's controls across three unrelated
// topics: identity, source, and deploy behaviour.
function SourceSettings({ svc }: { svc: Service }) {
  const { setConfigPath, setField } = useConfigUpdater()
  const isApp = svc.type === 'app'

  return (
    <SettingsGroup>
      {isApp ? (
        <>
          <SourceSection svc={svc} setField={setField} />

          <SettingCard wide title="Builder" description="How RailDock builds the image for this app.">
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
              {(['railpack', 'nixpacks', 'dockerfile', 'herokuish', 'pack'] as const).map((b) => (
                <label
                  key={b}
                  className={`flex items-center gap-3 p-3 border rounded-lg cursor-pointer transition-all ${
                    svc.builder === b ? 'border-[#8b5cf6]/40 bg-[#8b5cf6]/5' : 'border-white/[0.06] bg-black/25 hover:border-white/[0.12]'
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

          <SettingCard
            wide
            title="Static Site"
            description="Serve static files instead of running a start script. A plain static site has no build step at all."
          >
            <div className={svc.staticSite?.plainStatic ? 'pb-4' : 'border-b border-white/[0.06] pb-4'}>
              <div className="flex items-center justify-between">
                <div>
                  <div className="text-[13px] text-white/70">Plain static site</div>
                  <div className="text-[11px] text-white/50">No build step — HTML/CSS/JS in the repo is served as-is</div>
                </div>
                <AccessibleToggle
                  checked={!!svc.staticSite?.plainStatic}
                  onChange={(v) => {
                    setConfigPath('staticSite.plainStatic', v)
                    if (v) {
                      setConfigPath('staticSite.publishDirectory', null)
                      setConfigPath('staticSite.nodeVersion', null)
                    }
                  }}
                  label="Plain static site"
                />
              </div>
            </div>
            {!svc.staticSite?.plainStatic && (
              <>
                <TextField
                  label="Publish directory"
                  value={svc.staticSite?.publishDirectory || ''}
                  placeholder="dist"
                  onChange={(v) => setConfigPath('staticSite.publishDirectory', v)}
                />
                <div className="flex items-center justify-between">
                  <div>
                    <div className="text-[13px] text-white/70">Single-page app fallback</div>
                    <div className="text-[11px] text-white/50">Serve index.html for unmatched client-side routes</div>
                  </div>
                  <AccessibleToggle
                    checked={svc.staticSite?.spaFallback ?? true}
                    onChange={(v) => setConfigPath('staticSite.spaFallback', v)}
                    label="SPA fallback"
                  />
                </div>
                <TextField
                  label="Node version"
                  value={svc.staticSite?.nodeVersion || ''}
                  placeholder="22"
                  onChange={(v) => setConfigPath('staticSite.nodeVersion', v)}
                />
              </>
            )}
          </SettingCard>

          <SettingCard wide title="Deploy Options">
            <div className="flex items-center justify-between">
              <div>
                <div className="text-[13px] text-white/70">Auto-deploy</div>
                <div className="text-[11px] text-white/50">Automatically deploy on git push</div>
              </div>
              <AccessibleToggle checked={svc.autoDeploy} onChange={(v) => setField('autoDeploy', v)} label="Auto-deploy" />
            </div>
            {svc.webhookUrl && (
              <div className="border-t border-white/[0.06] pt-4 mt-4">
                <div className="text-[13px] text-white/70 mb-1">Deploy Webhook</div>
                <div className="text-[11px] text-white/50 mb-2">Use this URL in your CI/CD pipeline to trigger deployments.</div>
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
      ) : (
        <SettingCard wide title="Source" description="Image and version this service runs.">
          <TextField label="Docker Image" value={svc.dockerImage || ''} placeholder="postgres:15" onChange={(v) => setField('dockerImage', v)} />
          <TextField label="Version" value={svc.version || ''} onChange={(v) => setField('version', v)} />
        </SettingCard>
      )}
    </SettingsGroup>
  )
}

function SourceSection({ svc, setField }: { svc: Service; setField: (field: keyof Service, value: unknown) => void }) {
  const { data: sources } = useGitSources()
  const source = useMemo(() => findGitSourceForRepo(sources, svc.gitRepo), [sources, svc.gitRepo])
  const repoFullName = parseRepoFullName(svc.gitRepo) || svc.gitRepo || ''

  if (svc.gitRepo) {
    return (
      <>
        <SettingCard wide title="Git Repository">
          <div className="flex items-center gap-3 min-w-0">
            <div className="w-8 h-8 rounded-md bg-white/[0.06] flex items-center justify-center flex-shrink-0">
              <Github size={15} className="text-white/70" />
            </div>
            <div className="min-w-0 flex-1">
              <div className="text-[12px] font-medium text-white/80 truncate">{repoFullName}</div>
              <a
                href={svc.gitRepo}
                target="_blank"
                rel="noreferrer"
                className="text-[11px] text-white/45 hover:text-[#8b5cf6] inline-flex items-center gap-1"
              >
                View repository <ExternalLink size={10} />
              </a>
            </div>
            <button
              onClick={() => setField('gitRepo', '')}
              className="px-2.5 py-1 text-[11px] text-white/50 hover:text-white/80 hover:bg-white/[0.06] rounded-md border border-white/[0.08] transition-colors flex-shrink-0"
            >
              Disconnect
            </button>
          </div>
        </SettingCard>

        <SettingCard title="Deploy Branch" description="Changes pushed to this branch deploy automatically.">
          <BranchField repoFullName={repoFullName} sourceId={source?.id} branch={svc.branch || 'main'} onChange={(v) => setField('branch', v)} />
        </SettingCard>

        <SettingCard title="Root Directory" description="Where the app code lives inside the repository.">
          <DirectoryField repoFullName={repoFullName} sourceId={source?.id} branch={svc.branch || 'main'} directory={svc.rootDirectory || '.'} onChange={(v) => setField('rootDirectory', v)} />
        </SettingCard>
      </>
    )
  }

  return (
    <>
      <SettingCard title="Git Repository" description="Connect a GitHub repository to enable branch and directory selectors.">
        <TextField
          label="Repository URL"
          hideLabel
          value={svc.gitRepo || ''}
          placeholder="https://github.com/user/repo"
          onChange={(v) => setField('gitRepo', v)}
        />
      </SettingCard>

      <SettingCard title="Docker Image" description="Override the deployed image (optional).">
        <TextField label="Image" hideLabel value={svc.dockerImage || ''} placeholder="nginx:alpine" onChange={(v) => setField('dockerImage', v)} />
      </SettingCard>

      <SettingCard title="Start Command" description="Override the container start command (optional).">
        <TextField label="Command" hideLabel value={svc.startCommand || ''} placeholder="bundle exec puma" onChange={(v) => setField('startCommand', v)} />
      </SettingCard>
    </>
  )
}

function BranchField({ repoFullName, sourceId, branch, onChange }: { repoFullName: string; sourceId?: string; branch: string; onChange: (v: string) => void }) {
  const { data, isLoading, error } = useGitSourceBranches(sourceId, repoFullName)
  const branches = data?.branches || []
  const canSelect = !!sourceId && branches.length > 0

  return (
    <div>
      {canSelect ? (
        <Select value={branch} onValueChange={onChange}>
          <SelectTrigger className="w-full bg-black/40 border border-white/[0.08] rounded-lg px-3 py-1.5 text-[12px] text-white/80 focus:outline-none focus:border-[#8b5cf6]/40">
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
            className="w-full bg-black/40 border border-white/[0.08] rounded-lg px-3 py-1.5 text-[12px] text-white/80 focus:outline-none focus:border-[#8b5cf6]/40"
            placeholder="main"
          />
          {isLoading && <Loader2 size={14} className="absolute right-3 top-1/2 -translate-y-1/2 text-white/50 animate-spin" />}
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
      {canSelect ? (
        <Select value={directory || '.'} onValueChange={onChange}>
          <SelectTrigger className="w-full bg-black/40 border border-white/[0.08] rounded-lg px-3 py-1.5 text-[12px] text-white/80 focus:outline-none focus:border-[#8b5cf6]/40">
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
            className="w-full bg-black/40 border border-white/[0.08] rounded-lg px-3 py-1.5 text-[12px] text-white/80 focus:outline-none focus:border-[#8b5cf6]/40"
            placeholder="./"
          />
          {isLoading && <Loader2 size={14} className="absolute right-3 top-1/2 -translate-y-1/2 text-white/50 animate-spin" />}
          {error && <div className="text-[10px] text-red-300/70 mt-1">Could not load directories</div>}
        </div>
      )}
    </div>
  )
}

// ── Deploy Settings ────────────────────────────────────────
function DeploySettings({ svc }: { svc: Service }) {
  const { setConfigPath, setField } = useConfigUpdater()
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
    <SettingsGroup>
      <SettingCard title="Restart Policy" description="What Docker does when the container exits.">
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
      </SettingCard>

      <SettingCard title="Max Retries" description="Restart attempts before Docker gives up.">
        <TextField label="Max Retries" hideLabel type="number" value={String(svc.restartMaxRetries)} onChange={(v) => setField('restartMaxRetries', parseInt(v) || 0)} />
      </SettingCard>

      <SettingCard wide title="Health Checks" description="Keep the old container serving until its replacement is ready and connections drain.">
        <div className="flex items-start justify-between gap-4">
          <div className="text-[12px] text-white/60">Zero-downtime policy</div>
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

      <SettingCard title="Maintenance Mode" description="Serve a maintenance page for all requests.">
        <AccessibleToggle checked={svc.maintenanceMode} onChange={(v) => setField('maintenanceMode', v)} label="Maintenance mode" />
      </SettingCard>

      <SecuritySettings svc={svc} />
    </SettingsGroup>
  )
}

// ── Network Settings ───────────────────────────────────────
function NetworkSettings({ svc }: { svc: Service }) {
  const { setConfigPath, setField } = useConfigUpdater()
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
    <SettingsGroup>
      <SettingCard title="Proxy" description="Route public traffic to this service.">
        <AccessibleToggle checked={proxy.enabled} onChange={(v) => setConfigPath('proxy.enabled', v)} label="Proxy enabled" />
      </SettingCard>

      {proxy.enabled && (
        <>
          <SettingCard title="Proxy Type" description="Which proxy Dokku configures for this app.">
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
          </SettingCard>
        </>
      )}

      <SettingCard wide title="Port Mappings" description="Publish container ports on the host.">
        {proxy.portMappings.length > 0 ? (
          <div className="space-y-2 mb-3">
            {proxy.portMappings.map((pm, i) => (
              <div key={i} className="flex items-center gap-2 bg-black/25 border border-white/[0.06] rounded-lg p-2">
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
          <div className="text-[12px] text-white/50 mb-3">No port mappings configured</div>
        )}
        <button
          onClick={addPort}
          className="px-3 py-1.5 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[12px] hover:bg-[#8b5cf6]/25 transition-all"
        >
          Add Port Mapping
        </button>
      </SettingCard>

      <SettingCard wide title="SSL / Let's Encrypt" description="Issue and renew TLS certificates automatically.">
        <div className="flex items-center justify-between gap-3">
          <div className="text-[12px] text-white/60">Auto-generate certificates</div>
          <AccessibleToggle checked={letsencrypt.enabled} onChange={(v) => setConfigPath('letsencrypt.enabled', v)} label="Let's Encrypt" />
        </div>
        {letsencrypt.enabled && (
          <>
            <TextField label="Email" value={letsencrypt.email} onChange={(v) => setConfigPath('letsencrypt.email', v)} />
            <div className="flex items-center justify-between gap-3">
              <div className="text-[12px] text-white/60">Staging mode</div>
              <AccessibleToggle checked={letsencrypt.staging} onChange={(v) => setConfigPath('letsencrypt.staging', v)} label="Staging" />
            </div>
            <div className="flex items-center justify-between gap-3">
              <div className="text-[12px] text-white/60">Auto-renew</div>
              <AccessibleToggle checked={letsencrypt.autoRenew} onChange={(v) => setConfigPath('letsencrypt.autoRenew', v)} label="Auto-renew" />
            </div>
          </>
        )}
      </SettingCard>

      <SettingCard wide title="External Networks" description="Connect this service to Docker networks from other projects or stacks. It becomes reachable by container name on them.">
        {connectableNetworks.length > 0 ? (
          <div className="space-y-1.5">
            {connectableNetworks.map((net) => {
              const isChecked = externalNetworks.includes(net.name)
              return (
                <label
                  key={net.name}
                  className="flex items-center gap-2.5 p-2 rounded-lg bg-black/25 border border-white/[0.06] cursor-pointer hover:border-white/[0.12] transition-colors"
                >
                  <input
                    type="checkbox"
                    checked={isChecked}
                    onChange={() => toggleExternalNetwork(net.name)}
                    className="rounded border-white/20 bg-black/40 text-[#8b5cf6] focus:ring-[#8b5cf6]/40"
                  />
                  <div className="flex-1 min-w-0">
                    <div className="text-[12px] text-white/70 truncate">{net.name}</div>
                    <div className="text-[10px] text-white/50">
                      {net.driver}{net.containers?.length != null ? ` · ${net.containers.length} container(s)` : ''}
                    </div>
                  </div>
                </label>
              )
            })}
          </div>
        ) : (
          <div className="text-[12px] text-white/50">
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
    </SettingsGroup>
  )
}

// ── Resource Settings ──────────────────────────────────────
function ResourceSettings({ svc }: { svc: Service }) {
  const { setConfigPath } = useConfigUpdater()
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
    <SettingsGroup>
      {svc.processTypes && svc.processTypes.length > 0 ? (
        svc.processTypes.map((pt) => {
          const limit = limits.find((r) => r.processType === pt.name) || { processType: pt.name }
          const reserve = reservations.find((r) => r.processType === pt.name) || { processType: pt.name }
          return (
            <SettingCard key={pt.name} wide title={`Process: ${pt.name}`}>
              <div className="space-y-3">
                <div className="text-[11px] font-medium text-white/45">Limits</div>
                <div className="grid grid-cols-2 gap-2">
                  <ResourceInput label="CPU" value={(limit as unknown as Record<string, string>).cpu || ''} onChange={(v) => updateLimit(pt.name, 'cpu', v)} />
                  <ResourceInput label="Memory" value={(limit as unknown as Record<string, string>).memory || ''} onChange={(v) => updateLimit(pt.name, 'memory', v)} />
                  <ResourceInput label="Swap" value={(limit as unknown as Record<string, string>).memorySwap || ''} onChange={(v) => updateLimit(pt.name, 'memorySwap', v)} />
                  <ResourceInput label="NVIDIA GPU" value={String((limit as unknown as Record<string, unknown>).nvidiaGpu || '')} onChange={(v) => updateLimit(pt.name, 'nvidiaGpu', v)} />
                </div>
                <div className="text-[11px] font-medium text-white/45">Reservations</div>
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
        <SettingCard wide title="Resources">
          <div className="text-[12px] text-white/50">No process types configured. Deploy this service to detect process types.</div>
        </SettingCard>
      )}
    </SettingsGroup>
  )
}

// ── Advanced Settings ──────────────────────────────────────
function AdvancedSettings({ svc }: { svc: Service }) {
  const { setConfigPath } = useConfigUpdater()
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
    <SettingsGroup>
      <SettingCard wide title="Docker Options" description="Extra flags passed to Docker for this app.">
        {options.length > 0 ? (
          <div className="space-y-2 mb-3">
            {options.map((opt, i) => (
              <div key={i} className="flex items-center gap-2 bg-black/25 border border-white/[0.06] rounded-lg p-2.5 group">
                <span className="text-[10px] px-1.5 py-0.5 bg-white/[0.06] text-white/50 rounded uppercase">{opt.phase}</span>
                <span className="text-[12px] text-white/60 font-mono flex-1 truncate">{opt.option}</span>
                <button onClick={() => removeOption(i)} className="p-1 hover:bg-white/[0.06] rounded text-white/20 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity">
                  <Trash2 size={12} />
                </button>
              </div>
            ))}
          </div>
        ) : (
          <div className="text-[12px] text-white/50 mb-3">No docker options configured</div>
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

      <SettingCard wide title="Cron Jobs" description="Scheduled commands run inside the app container.">
        {jobs.length > 0 ? (
          <div className="space-y-2 mb-3">
            {jobs.map((job, i) => (
              <div key={i} className="flex items-center gap-2 bg-black/25 border border-white/[0.06] rounded-lg p-2.5 group">
                <span className="text-[10px] px-1.5 py-0.5 bg-[#8b5cf6]/10 text-[#8b5cf6] rounded font-mono">{job.schedule}</span>
                <span className="text-[12px] text-white/60 font-mono flex-1 truncate">{job.command}</span>
                <button onClick={() => removeJob(i)} className="p-1 hover:bg-white/[0.06] rounded text-white/20 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity">
                  <Trash2 size={12} />
                </button>
              </div>
            ))}
          </div>
        ) : (
          <div className="text-[12px] text-white/50 mb-3">No cron jobs configured</div>
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
    </SettingsGroup>
  )
}

// ── Danger Zone ────────────────────────────────────────────
function DangerZone({ svc }: { svc: Service }) {
  const navigate = useNavigate()
  const destroyService = useDestroyService()
  const [showConfirm, setShowConfirm] = useState(false)
  const [confirmName, setConfirmName] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [needsAcknowledgement, setNeedsAcknowledgement] = useState(false)

  const isConfirmValid = confirmName === svc.name

  const handleDestroy = (forceDestroyData = false) => {
    if (!isConfirmValid) return
    setError(null)
    destroyService.mutate(
      { id: svc.id, confirm: confirmName, forceDestroyData },
      {
        onSuccess: () => {
          setShowConfirm(false)
          setConfirmName('')
          navigate(`/dashboard`) // go back to projects list after destroy
        },
        onError: (err: Error & { code?: string }) => {
          // The backend refuses to delete data unless a verified snapshot
          // exists — or the user explicitly accepts permanent loss.
          if (err.code === 'snapshot_required') {
            setNeedsAcknowledgement(true)
            setError(err.message)
          } else {
            setError(err.message)
          }
        },
      },
    )
  }

  const handleClose = () => {
    setShowConfirm(false)
    setConfirmName('')
    setError(null)
    setNeedsAcknowledgement(false)
  }

  return (
    <>
      <div>
        <div className="bg-red-500/5 border border-red-500/20 rounded-lg p-4 space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-[13px] text-white/70">Destroy Service</div>
              <div className="text-[11px] text-white/50 mt-0.5">
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
                <p className="text-xs text-[#8a8a99]">This action cannot be undone</p>
              </div>
            </div>

            <p className="text-sm text-[#A0A0B0] mb-4">
              You are about to permanently destroy{' '}
              <span className="font-medium text-white">{svc.name}</span>
              . This will remove the Dokku app and all data including databases, storage, and logs.
            </p>

            <p className="text-[11px] text-[#8a8a99] mb-4">
              RailDock takes a verified snapshot on a configured backup destination before deleting data. If no
              destination is verified, the deletion is refused until you acknowledge the loss.
            </p>

            {error && (
              <div className="mb-4 text-[11px] text-red-300 bg-red-500/10 border border-red-500/20 rounded-lg p-2.5">
                {error}
              </div>
            )}

            <div className="mb-4">
              <label className="text-[11px] text-[#8a8a99] block mb-1.5">
                Type <span className="font-mono font-medium text-white">{svc.name}</span> to confirm
              </label>
              <input
                value={confirmName}
                onChange={(e) => setConfirmName(e.target.value)}
                aria-label={`Type ${svc.name} to confirm`}
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
                onClick={() => handleDestroy(needsAcknowledgement)}
                disabled={!isConfirmValid || destroyService.isPending}
                className="flex-1 py-2.5 bg-red-500 text-white text-sm font-medium rounded-lg hover:bg-red-600 transition-all disabled:opacity-30 disabled:cursor-not-allowed"
              >
                {needsAcknowledgement ? 'Destroy Without Snapshot' : 'Destroy Service'}
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
    <SettingCard title="App Lock" description="Block deployments and rebuilds. Use during maintenance or migrations.">
      <div className="flex items-center justify-between gap-3">
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
      {isLocked && <div className="text-[11px] text-amber-400/60">Deployments are blocked while the app is locked.</div>}
    </SettingCard>
  )
}

// ── Reusable UI Primitives ─────────────────────────────────
// One row per setting: label and hint on the left, the control on the right.
// Rows do not draw their own card — SettingsGroup owns the only border, and
// `divide-y` draws the hairline between rows. `wide` is for rows whose control
// needs the full width (lists, grids, repeatable fields).
function SettingCard({ title, description, wide = false, children }: { title?: string; description?: string; wide?: boolean; children: React.ReactNode }) {
  const heading = Boolean(title || description)
  if (!heading) {
    return <div className="px-4 py-3.5">{children}</div>
  }
  return (
    <div className={wide ? 'px-4 py-3.5' : 'flex flex-col gap-3 px-4 py-3.5 sm:flex-row sm:items-start sm:justify-between sm:gap-8'}>
      <div className={wide ? '' : 'min-w-0 sm:max-w-[52%]'}>
        {title && <div className="text-[13px] font-medium text-white/85">{title}</div>}
        {description && <div className="mt-0.5 text-[11px] leading-snug text-white/40">{description}</div>}
      </div>
      <div className={cn('flex min-w-0 flex-col gap-2.5', wide ? 'mt-3' : 'sm:w-[300px] sm:flex-shrink-0')}>{children}</div>
    </div>
  )
}

// Rows share a single bordered container with hairline dividers between them,
// rather than each setting drawing its own card. Cards are for distinct things
// (a danger zone, a group of rows); a card per setting reads as noise.
function SettingsGroup({ children }: { children: React.ReactNode }) {
  return (
    <div className="divide-y divide-white/[0.055] overflow-hidden rounded-lg border border-white/[0.06] bg-[#17171b]">
      {children}
    </div>
  )
}

// `hideLabel` is for the few cards whose title already names the control, so it
// is not labelled twice ("Container Port" then "Port"). The label stays on the
// input itself for assistive tech.
function TextField({ label, value, placeholder, type = 'text', hideLabel = false, onChange }: { label: string; value: string; placeholder?: string; type?: string; hideLabel?: boolean; onChange: (v: string) => void }) {
  return (
    <div>
      {!hideLabel && <div className="text-[11px] text-white/50 mb-1">{label}</div>}
      <input
        type={type}
        value={value}
        placeholder={placeholder}
        aria-label={label}
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
      className="px-3 py-2 bg-white/5 text-white/50 rounded-lg text-[11px] hover:bg-white/10 hover:text-white/60 transition-all flex items-center gap-1.5"
    >
      {isCopied ? <Check size={12} className="text-[#22c55e]" /> : <Copy size={12} />}
      {isCopied ? 'Copied' : 'Copy'}
    </button>
  )
}

function ResourceInput({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  return (
    <div>
      <div className="text-[11px] text-white/50">{label}</div>
      <input
        type="text"
        value={value}
        placeholder="—"
        aria-label={label}
        onChange={(e) => onChange(e.target.value)}
        className="w-full mt-1 bg-black/40 border border-white/[0.08] rounded px-2 py-1 text-[12px] font-mono text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
      />
    </div>
  )
}
