import { Server, HardDrive, Activity, Plus, Trash2, Settings } from 'lucide-react'
import { useState } from 'react'
import { toast } from 'sonner'
import type { Server as ServerRecord } from '@/types'
import { useServers, useDestroyServer, useValidateServer, useUpdateServer } from '@/hooks/useServers'
import { useNetworks, useValidateNetwork } from '@/hooks/useModules'
import ServerSetupWizard from '@/features/servers/ServerSetupWizard'
import { useAuthStore } from '@/stores/useAuthStore'

export default function ServerPage() {
  const { data: servers = [], isLoading } = useServers()
  const destroyServer = useDestroyServer()
  const validateServer = useValidateServer()
  const updateServer = useUpdateServer()
  const validateNetwork = useValidateNetwork()
  const organization = useAuthStore((s) => s.currentOrganization())
  const canCreateServer = organization?.role === 'owner'

  const [showAdd, setShowAdd] = useState(false)
  const [settingsServer, setSettingsServer] = useState<ServerRecord | null>(null)
  const [proxyMode, setProxyMode] = useState<'managed' | 'external'>('managed')
  const [proxyNetwork, setProxyNetwork] = useState('')
  const [httpEntrypoint, setHttpEntrypoint] = useState('web')
  const [httpsEntrypoint, setHttpsEntrypoint] = useState('websecure')
  const [certResolver, setCertResolver] = useState('')
  const [redirectMiddleware, setRedirectMiddleware] = useState('')
  const [defaultLabels, setDefaultLabels] = useState('{}')
  const { data: networks = [], isLoading: networksLoading } = useNetworks(settingsServer?.id)

  const openSettings = (server: ServerRecord) => {
    setSettingsServer(server)
    setProxyMode(server.proxyMode || 'managed')
    setProxyNetwork(server.externalProxyNetwork || '')
    setHttpEntrypoint(server.externalProxyHttpEntrypoint || 'web')
    setHttpsEntrypoint(server.externalProxyHttpsEntrypoint || 'websecure')
    setCertResolver(server.externalProxyCertResolver || '')
    setRedirectMiddleware(server.externalProxyRedirectMiddleware || '')
    setDefaultLabels(JSON.stringify(server.externalProxyDefaultLabels || {}, null, 2))
  }

  const saveSettings = () => {
    if (!settingsServer) return

    let labels: Record<string, string>
    try {
      labels = JSON.parse(defaultLabels)
    } catch {
      toast.error('Default labels must be valid JSON')
      return
    }

    updateServer.mutate({
      id: settingsServer.id,
      data: {
        proxyMode,
        externalProxyNetwork: proxyMode === 'external' ? proxyNetwork : undefined,
        externalProxyHttpEntrypoint: httpEntrypoint,
        externalProxyHttpsEntrypoint: httpsEntrypoint,
        externalProxyCertResolver: certResolver || undefined,
        externalProxyRedirectMiddleware: redirectMiddleware || undefined,
        externalProxyDefaultLabels: labels,
      },
    }, {
      onSuccess: () => setSettingsServer(null),
    })
  }

  return (
    <div className="h-full flex flex-col overflow-hidden">
      <div className="px-6 py-4 border-b border-[rgba(255,255,255,0.06)] flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Server size={18} className="text-rail-purple" />
          <h1 className="text-base font-semibold text-white">Servers</h1>
        </div>
        {canCreateServer && (
          <button
            onClick={() => setShowAdd(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-rail-purple/15 text-rail-purple rounded-lg text-xs font-medium hover:bg-rail-purple/25 transition-all"
          >
            <Plus size={14} /> Add Server
          </button>
        )}
      </div>

      <div className="flex-1 overflow-y-auto p-6">
        <div className="max-w-3xl space-y-4">
          {isLoading ? (
            Array.from({ length: 2 }).map((_, i) => (
              <div key={i} className="h-48 bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-xl animate-pulse" />
            ))
          ) : (
            servers.map((srv) => (
              <div key={srv.id} className="relative group">
                <div className="bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-xl p-5">
                  <div className="flex items-center justify-between mb-4">
                    <div className="flex items-center gap-3">
                      <div className="w-10 h-10 rounded-xl bg-[rgba(139,92,246,0.08)] flex items-center justify-center">
                        <Server size={20} className="text-rail-purple" />
                      </div>
                      <div>
                        <div className="text-sm font-semibold text-white">{srv.name}</div>
                        <div className="text-[10px] text-[#4A4A55]">{srv.host} · {srv.os}</div>
                        {srv.baseDomain && (
                          <div className="text-[10px] text-rail-purple mt-0.5">*.{srv.baseDomain}</div>
                        )}
                        {srv.publicIp && (
                          <div className="text-[10px] text-[#4A4A55] mt-0.5">IP {srv.publicIp}</div>
                        )}
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      <div className={`w-2 h-2 rounded-full ${srv.status === 'connected' ? 'bg-rail-green' : srv.status === 'error' ? 'bg-rail-red' : 'bg-rail-yellow'}`} />
                      <span className="text-[11px] text-[#6B6B7B] capitalize">{srv.status}</span>
                      {srv.status !== 'connected' && (
                        <button
                          onClick={() => validateServer.mutate(srv.id)}
                          disabled={validateServer.isPending}
                          className="text-[10px] px-2 py-0.5 bg-rail-purple/15 text-rail-purple rounded-full hover:bg-rail-purple/25 transition-all disabled:opacity-50"
                        >
                          {validateServer.isPending ? 'Validating...' : 'Validate'}
                        </button>
                      )}
                      <button
                        onClick={() => openSettings(srv)}
                        className="p-1 rounded text-white/40 hover:text-white hover:bg-white/[0.05]"
                        title="Proxy settings"
                      >
                        <Settings size={14} />
                      </button>
                    </div>
                  </div>

                  <div className="grid grid-cols-4 gap-3 mb-4">
                    <div className="bg-[rgba(255,255,255,0.02)] rounded-lg p-3 text-center">
                      <div className="text-lg font-bold text-white">{srv.projectIds.length}</div>
                      <div className="text-[10px] text-[#4A4A55]">Projects</div>
                    </div>
                    <div className="bg-[rgba(255,255,255,0.02)] rounded-lg p-3 text-center">
                      <div className="text-lg font-bold text-white">{srv.dokkuVersion}</div>
                      <div className="text-[10px] text-[#4A4A55]">Dokku</div>
                    </div>
                    <div className="bg-[rgba(255,255,255,0.02)] rounded-lg p-3 text-center">
                      <div className="text-lg font-bold text-white">{srv.dockerVersion}</div>
                      <div className="text-[10px] text-[#4A4A55]">Docker</div>
                    </div>
                    <div className="bg-[rgba(255,255,255,0.02)] rounded-lg p-3 text-center">
                      <div className="text-lg font-bold text-white capitalize">{srv.defaultProxy}</div>
                      <div className="text-[10px] text-[#4A4A55]">Proxy</div>
                    </div>
                  </div>

                  <div className="grid grid-cols-2 gap-3">
                    <div className="bg-[rgba(255,255,255,0.02)] rounded-lg p-3">
                      <div className="flex items-center gap-2 mb-2">
                        <HardDrive size={12} className="text-rail-blue" />
                        <span className="text-[10px] text-[#4A4A55]">Disk</span>
                      </div>
                      <div className="text-sm font-bold text-white">{srv.diskUsage.used}/{srv.diskUsage.total} GB</div>
                      <div className="mt-1.5 h-1 bg-[rgba(255,255,255,0.05)] rounded-full overflow-hidden">
                        <div className="h-full bg-rail-blue rounded-full" style={{ width: `${(srv.diskUsage.used / srv.diskUsage.total) * 100}%` }} />
                      </div>
                    </div>
                    <div className="bg-[rgba(255,255,255,0.02)] rounded-lg p-3">
                      <div className="flex items-center gap-2 mb-2">
                        <Activity size={12} className="text-rail-purple" />
                        <span className="text-[10px] text-[#4A4A55]">Memory</span>
                      </div>
                      <div className="text-sm font-bold text-white">{srv.memoryUsage.used}/{srv.memoryUsage.total} GB</div>
                      <div className="mt-1.5 h-1 bg-[rgba(255,255,255,0.05)] rounded-full overflow-hidden">
                        <div className="h-full bg-rail-purple rounded-full" style={{ width: `${(srv.memoryUsage.used / srv.memoryUsage.total) * 100}%` }} />
                      </div>
                    </div>
                  </div>
                </div>

                <button
                  onClick={() => {
                    if (confirm(`Remove server "${srv.name}"?`)) destroyServer.mutate(srv.id)
                  }}
                  className="absolute top-3 right-3 opacity-0 group-hover:opacity-100 p-1.5 rounded-lg text-white/30 hover:text-red-400 hover:bg-white/[0.04] transition-all"
                  title="Remove server"
                >
                  <Trash2 size={14} />
                </button>
              </div>
            ))
          )}

          {servers.length === 0 && !isLoading && (
            <div className="text-center py-16 text-[#4A4A55]">
              <Server size={48} className="mx-auto mb-4 opacity-30" />
              <p className="text-sm">No servers connected</p>
              {canCreateServer ? (
                <button onClick={() => setShowAdd(true)} className="mt-3 text-rail-purple text-sm hover:underline">
                  Connect your first server
                </button>
              ) : (
                <p className="mt-3 text-[11px]">Only organization owners can connect servers.</p>
              )}
            </div>
          )}
        </div>
      </div>

      {showAdd && <ServerSetupWizard isOpen={showAdd} onClose={() => setShowAdd(false)} />}

      {settingsServer && (
        <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-center justify-center px-4" onClick={() => setSettingsServer(null)}>
          <div className="bg-[#18181B] border border-[rgba(255,255,255,0.08)] rounded-2xl p-6 w-full max-w-[560px] max-h-[90vh] overflow-y-auto" onClick={(event) => event.stopPropagation()}>
            <h3 className="text-base font-semibold text-white">Proxy Settings</h3>
            <p className="text-xs text-[#6B6B7B] mt-1 mb-5">{settingsServer.name}</p>

            <div className="space-y-4">
              <div>
                <label htmlFor="proxy-mode" className="text-[11px] text-[#6B6B7B] block mb-1.5">Proxy Mode</label>
                <select id="proxy-mode" value={proxyMode} onChange={(event) => setProxyMode(event.target.value as 'managed' | 'external')} className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-white/10 rounded-lg text-sm text-white">
                  <option value="managed">RailDock managed</option>
                  <option value="external">Existing Traefik</option>
                </select>
              </div>

              {proxyMode === 'external' && (
                <>
                  <div>
                    <div className="flex items-center justify-between mb-1.5">
                      <label htmlFor="proxy-network" className="text-[11px] text-[#6B6B7B]">Traefik Docker Network</label>
                      <button
                        type="button"
                        disabled={!proxyNetwork || validateNetwork.isPending}
                        onClick={() => validateNetwork.mutate({ serverId: settingsServer.id, network: proxyNetwork })}
                        className="text-[10px] text-rail-purple disabled:opacity-40"
                      >
                        {validateNetwork.isPending ? 'Checking...' : 'Verify network'}
                      </button>
                    </div>
                    <select id="proxy-network" value={proxyNetwork} onChange={(event) => setProxyNetwork(event.target.value)} className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-white/10 rounded-lg text-sm text-white">
                      <option value="">{networksLoading ? 'Discovering networks...' : 'Select a network'}</option>
                      {networks.filter((network) => network.selectable).map((network) => (
                        <option key={network.name} value={network.name}>
                          {network.name}{network.recommended ? ' (Traefik detected)' : ''}
                        </option>
                      ))}
                    </select>
                  </div>

                  <div className="grid grid-cols-2 gap-3">
                    <ProxyInput id="http-entrypoint" label="HTTP entrypoint" value={httpEntrypoint} onChange={setHttpEntrypoint} />
                    <ProxyInput id="https-entrypoint" label="HTTPS entrypoint" value={httpsEntrypoint} onChange={setHttpsEntrypoint} />
                    <ProxyInput id="cert-resolver" label="Certificate resolver" value={certResolver} onChange={setCertResolver} placeholder="letsencrypt" />
                    <ProxyInput id="redirect-middleware" label="Redirect middleware" value={redirectMiddleware} onChange={setRedirectMiddleware} placeholder="redirect-to-https" />
                  </div>

                  <div>
                    <label htmlFor="default-labels" className="text-[11px] text-[#6B6B7B] block mb-1.5">Default Traefik labels (JSON)</label>
                    <textarea id="default-labels" value={defaultLabels} onChange={(event) => setDefaultLabels(event.target.value)} rows={5} className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-white/10 rounded-lg text-xs text-white font-mono" />
                  </div>

                  <p className="text-[10px] text-[#6B6B7B]">
                    RailDock will not start, stop, or reconfigure the existing Traefik container. Services attach to this network when redeployed.
                  </p>
                </>
              )}
            </div>

            <div className="flex gap-2 mt-6">
              <button onClick={() => setSettingsServer(null)} className="flex-1 py-2.5 border border-white/10 text-[#A0A0B0] text-xs rounded-lg">Cancel</button>
              <button onClick={saveSettings} disabled={updateServer.isPending || (proxyMode === 'external' && !proxyNetwork)} className="flex-1 py-2.5 bg-rail-purple text-white text-xs font-medium rounded-lg disabled:opacity-50">
                {updateServer.isPending ? 'Saving...' : 'Save Settings'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

function ProxyInput({ id, label, value, onChange, placeholder }: {
  id: string
  label: string
  value: string
  onChange: (value: string) => void
  placeholder?: string
}) {
  return (
    <div>
      <label htmlFor={id} className="text-[11px] text-[#6B6B7B] block mb-1.5">{label}</label>
      <input id={id} value={value} onChange={(event) => onChange(event.target.value)} placeholder={placeholder} className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-white/10 rounded-lg text-sm text-white" />
    </div>
  )
}
