import { useState } from 'react'
import { Trash2, Loader2, Globe, Server, Cpu, Wrench, AlertTriangle, Lock, Unlock } from 'lucide-react'
import type { Service } from '@/types'
import { useUpdateService, useUpdateServiceConfig, useDestroyService } from '@/hooks/useServices'
import { api } from '@/lib/api'
import AccessibleToggle from '@/features/shared/AccessibleToggle'

const tabs = [
  { key: 'general', label: 'General', icon: Server },
  { key: 'deploy', label: 'Deploy', icon: Server },
  { key: 'network', label: 'Networking', icon: Globe },
  { key: 'resources', label: 'Resources', icon: Cpu },
  { key: 'advanced', label: 'Advanced', icon: Wrench },
  { key: 'danger', label: 'Danger Zone', icon: AlertTriangle },
] as const

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

// ── General Settings ───────────────────────────────────────
function GeneralSettings({ svc }: { svc: Service }) {
  const { setConfigPath, setField } = useConfigUpdater(svc)
  const isApp = svc.type === 'app'

  return (
    <div className="space-y-4">
      <SectionTitle>General</SectionTitle>

      {isApp && (
        <>
          <SettingCard title="Builder" description="How your app is built">
            <div className="space-y-2">
              {(['nixpacks', 'dockerfile', 'herokuish', 'pack', 'railpack'] as const).map((b) => (
                <label
                  key={b}
                  className={`flex items-center gap-3 p-3 border rounded-lg cursor-pointer transition-all ${
                    svc.builder === b ? 'border-[#8b5cf6]/40 bg-[#8b5cf6]/5' : 'border-white/[0.06] bg-[#1a1a1e]'
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

          <SettingCard title="Source">
            <div className="space-y-3">
              <TextField label="Git Repository" value={svc.gitRepo || ''} placeholder="https://github.com/user/repo" onChange={(v) => setField('gitRepo', v)} />
              <TextField label="Docker Image" value={svc.dockerImage || ''} placeholder="nginx:alpine" onChange={(v) => setField('dockerImage', v)} />
              <TextField label="Root Directory" value={svc.rootDirectory || ''} placeholder="./" onChange={(v) => setField('rootDirectory', v)} />
              <TextField label="Start Command" value={svc.startCommand || ''} placeholder="bundle exec puma" onChange={(v) => setField('startCommand', v)} />
              <TextField label="Deploy Branch" value={svc.branch || 'main'} onChange={(v) => setField('branch', v)} />
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

// ── Deploy Settings ────────────────────────────────────────
function DeploySettings({ svc }: { svc: Service }) {
  const { setConfigPath, setField } = useConfigUpdater(svc)
  const checks = svc.checks || { enabled: false, wait: 5, timeout: 30, skipList: [] }

  return (
    <div className="space-y-4">
      <SectionTitle>Deploy</SectionTitle>

      <SettingCard title="Restart Policy">
        <select
          value={svc.restartPolicy}
          onChange={(e) => setField('restartPolicy', e.target.value)}
          className="w-full bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
        >
          <option value="on-failure">On Failure</option>
          <option value="always">Always</option>
          <option value="unless-stopped">Unless Stopped</option>
        </select>
        <div className="mt-2">
          <TextField label="Max Retries" type="number" value={String(svc.restartMaxRetries)} onChange={(v) => setField('restartMaxRetries', parseInt(v) || 0)} />
        </div>
      </SettingCard>

      <SettingCard title="Health Checks">
        <div className="flex items-center justify-between mb-3">
          <div className="text-[13px] text-white/70">Zero-Downtime Checks</div>
          <AccessibleToggle checked={checks.enabled} onChange={(v) => setConfigPath('checks.enabled', v)} label="Enable health checks" />
        </div>
        {checks.enabled && (
          <div className="grid grid-cols-2 gap-3">
            <TextField label="Wait (seconds)" type="number" value={String(checks.wait)} onChange={(v) => setConfigPath('checks.wait', parseInt(v) || 0)} />
            <TextField label="Timeout (seconds)" type="number" value={String(checks.timeout)} onChange={(v) => setConfigPath('checks.timeout', parseInt(v) || 0)} />
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
  const { setConfigPath } = useConfigUpdater(svc)
  const proxy = svc.proxy || { enabled: true, proxyType: 'traefik', portMappings: [] }
  const letsencrypt = svc.letsencrypt || { enabled: false, email: '', staging: false, autoRenew: true }

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
              <select
                value={proxy.proxyType}
                onChange={(e) => setConfigPath('proxy.proxyType', e.target.value)}
                className="w-full bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
              >
                <option value="traefik">Traefik</option>
                <option value="nginx">Nginx</option>
                <option value="caddy">Caddy</option>
                <option value="haproxy">HAProxy</option>
                <option value="openresty">OpenResty</option>
              </select>
            </div>
          </>
        )}
      </SettingCard>

      <SettingCard title="Port Mappings">
        {proxy.portMappings.length > 0 ? (
          <div className="space-y-2 mb-3">
            {proxy.portMappings.map((pm, i) => (
              <div key={i} className="flex items-center gap-2 bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-2">
                <select
                  value={pm.scheme}
                  onChange={(e) => updatePort(i, { scheme: e.target.value })}
                  className="bg-black/40 border border-white/[0.08] rounded px-2 py-1 text-[12px] text-white/70"
                >
                  <option value="http">http</option>
                  <option value="https">https</option>
                  <option value="grpc">grpc</option>
                </select>
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
          <select
            value={newPhase}
            onChange={(e) => setNewPhase(e.target.value as 'build' | 'deploy' | 'run')}
            className="bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] text-white/70"
          >
            <option value="build">build</option>
            <option value="deploy">deploy</option>
            <option value="run">run</option>
          </select>
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
  const destroyService = useDestroyService()

  return (
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
            onClick={() => {
              if (confirm(`Are you sure you want to destroy "${svc.name}"? This will also remove the Dokku app and all data. This action cannot be undone.`)) {
                destroyService.mutate(svc.id)
              }
            }}
            disabled={destroyService.isPending}
            className="px-3 py-2 bg-red-500/15 text-red-400 rounded-lg text-[12px] font-medium hover:bg-red-500/25 transition-all disabled:opacity-50 flex items-center gap-1.5"
          >
            <Trash2 size={13} />
            {destroyService.isPending ? 'Destroying...' : 'Destroy'}
          </button>
        </div>
      </div>
    </div>
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
