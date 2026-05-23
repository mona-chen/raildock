import { Server, HardDrive, Activity, Plus } from 'lucide-react'
import { useState } from 'react'
import { useServers, useCreateServer, useDestroyServer, useValidateServer } from '@/hooks/useServers'

export default function ServerPage() {
  const { data: servers = [], isLoading } = useServers()
  const createServer = useCreateServer()
  const destroyServer = useDestroyServer()
  const validateServer = useValidateServer()

  const [showAdd, setShowAdd] = useState(false)
  const [newName, setNewName] = useState('')
  const [newHost, setNewHost] = useState('')
  const [newSshKey, setNewSshKey] = useState('')
  const [newBaseDomain, setNewBaseDomain] = useState('')
  const [newAutoDomains, setNewAutoDomains] = useState(true)

  const handleAdd = () => {
    if (!newName.trim() || !newHost.trim()) return
    createServer.mutate({
      name: newName,
      host: newHost,
      sshKey: newSshKey,
      baseDomain: newBaseDomain || undefined,
      autoDomains: newAutoDomains,
    }, {
      onSuccess: () => {
        setNewName('')
        setNewHost('')
        setNewSshKey('')
        setNewBaseDomain('')
        setNewAutoDomains(true)
        setShowAdd(false)
      },
    })
  }

  return (
    <div className="h-full flex flex-col overflow-hidden">
      <div className="px-6 py-4 border-b border-[rgba(255,255,255,0.06)] flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Server size={18} className="text-rail-purple" />
          <h1 className="text-base font-semibold text-white">Servers</h1>
        </div>
        <button
          onClick={() => setShowAdd(true)}
          className="flex items-center gap-1.5 px-3 py-1.5 bg-rail-purple/15 text-rail-purple rounded-lg text-xs font-medium hover:bg-rail-purple/25 transition-all"
        >
          <Plus size={14} /> Add Server
        </button>
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
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>
                </button>
              </div>
            ))
          )}

          {servers.length === 0 && !isLoading && (
            <div className="text-center py-16 text-[#4A4A55]">
              <Server size={48} className="mx-auto mb-4 opacity-30" />
              <p className="text-sm">No servers connected</p>
              <button onClick={() => setShowAdd(true)} className="mt-3 text-rail-purple text-sm hover:underline">
                Connect your first server
              </button>
            </div>
          )}
        </div>
      </div>

      {showAdd && (
        <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-center justify-center" onClick={() => setShowAdd(false)}>
          <div className="bg-[#18181B] border border-[rgba(255,255,255,0.08)] rounded-2xl p-6 w-[420px]" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-base font-semibold text-white mb-1">Add Server</h3>
            <p className="text-xs text-[#4A4A55] mb-4">Connect a Dokku host via SSH</p>
            <div className="space-y-3">
              <div>
                <label className="text-[11px] text-[#6B6B7B] block mb-1.5">Server Name</label>
                <input value={newName} onChange={(e) => setNewName(e.target.value)} className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-rail-purple" placeholder="dokku-prod-01" />
              </div>
              <div>
                <label className="text-[11px] text-[#6B6B7B] block mb-1.5">Host / IP</label>
                <input value={newHost} onChange={(e) => setNewHost(e.target.value)} className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-rail-purple" placeholder="192.168.1.100" />
              </div>
              <div>
                <label className="text-[11px] text-[#6B6B7B] block mb-1.5">SSH Private Key</label>
                <textarea value={newSshKey} onChange={(e) => setNewSshKey(e.target.value)} rows={4} className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-rail-purple font-mono text-[11px]" placeholder="-----BEGIN OPENSSH PRIVATE KEY-----..." />
              </div>
              <div>
                <div className="flex items-center justify-between mb-1.5">
                  <label className="text-[11px] text-[#6B6B7B]">Base Domain (optional)</label>
                  <button
                    type="button"
                    onClick={() => setNewBaseDomain('sslip.io')}
                    className="text-[10px] px-2 py-0.5 bg-rail-purple/10 text-rail-purple rounded-full hover:bg-rail-purple/20 transition-all"
                  >
                    Use sslip.io
                  </button>
                </div>
                <input value={newBaseDomain} onChange={(e) => setNewBaseDomain(e.target.value)} className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-rail-purple" placeholder="example.com" />
                <p className="text-[10px] text-[#4A4A55] mt-1">
                  {newBaseDomain === 'sslip.io'
                    ? 'Auto-assigns app-name.{server-ip}.sslip.io (HTTP only)'
                    : 'Auto-assigns subdomains like app-name.example.com'}
                </p>
              </div>
              <div className="flex items-center gap-2">
                <input
                  id="auto-domains"
                  type="checkbox"
                  checked={newAutoDomains}
                  onChange={(e) => setNewAutoDomains(e.target.checked)}
                  className="w-3.5 h-3.5 rounded border-[rgba(255,255,255,0.15)] bg-[#0B0B0D] text-rail-purple focus:ring-rail-purple"
                />
                <label htmlFor="auto-domains" className="text-[11px] text-[#6B6B7B]">Auto-assign temporary domains for new services</label>
              </div>
            </div>
            <div className="flex gap-2 mt-5">
              <button onClick={() => setShowAdd(false)} className="flex-1 py-2.5 border border-[rgba(255,255,255,0.08)] text-[#A0A0B0] text-xs rounded-lg hover:bg-[rgba(255,255,255,0.04)]">Cancel</button>
              <button onClick={handleAdd} disabled={createServer.isPending} className="flex-1 py-2.5 bg-rail-purple text-white text-xs font-medium rounded-lg hover:bg-rail-purple-dark disabled:opacity-50">
                {createServer.isPending ? 'Adding...' : 'Add Server'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
