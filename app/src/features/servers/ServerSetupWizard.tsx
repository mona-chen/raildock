import { useEffect, useState } from 'react'
import { AlertCircle, Check, Copy, Loader2, Server, Terminal } from 'lucide-react'
import { toast } from 'sonner'
import { useServerBootstrap } from '@/hooks/useOrganizations'
import { useProvisionServer } from '@/hooks/useServers'
import { useServerSetupLogs } from '@/hooks/useServerSetupLogs'
import { useAuthStore } from '@/stores/useAuthStore'
import { useCopy } from '@/hooks/useCopy'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'

interface ServerSetupWizardProps {
  isOpen: boolean
  onClose: () => void
}

export default function ServerSetupWizard({ isOpen, onClose }: ServerSetupWizardProps) {
  const organizationId = useAuthStore((s) => s.currentOrganizationId)
  const organization = useAuthStore((s) => s.currentOrganization())
  const canCreate = organization?.role === 'owner'

  const { data: bootstrap, isLoading: bootstrapLoading, isError: bootstrapError, error: bootstrapErrorDetail } = useServerBootstrap(organizationId)
  const provisionServer = useProvisionServer()
  const { copiedKey, copy } = useCopy()

  const [name, setName] = useState('')
  const [host, setHost] = useState('')
  const [sshUser, setSshUser] = useState('dokku')
  const [adminUser, setAdminUser] = useState('root')
  const [proxyMode, setProxyMode] = useState<'managed' | 'external'>('managed')
  const [baseDomain, setBaseDomain] = useState('')
  const [autoDomains, setAutoDomains] = useState(true)
  const [setupId, setSetupId] = useState<string | null>(null)

  const { logs: provisionLogs, state: provisionState, error: provisionError, serverId: provisionServerId } = useServerSetupLogs(setupId)

  useEffect(() => {
    if (provisionState === 'completed') {
      toast.success('Server connected')
      setTimeout(onClose, 1500)
    }
  }, [provisionState, onClose])

  const reset = () => {
    setName('')
    setHost('')
    setSshUser('dokku')
    setAdminUser('root')
    setProxyMode('managed')
    setBaseDomain('')
    setAutoDomains(true)
    setSetupId(null)
  }

  useEffect(() => {
    if (isOpen) reset()
  }, [isOpen])

  if (!isOpen) return null

  const scriptUrl = typeof window !== 'undefined' ? window.location.origin : ''
  const bootstrapCommand =
    bootstrap?.publicKey && scriptUrl
      ? `curl -fsSL ${scriptUrl}/bootstrap.sh | ${proxyMode === 'external' ? "PROXY_MODE='external' " : ''}bash -s -- '${bootstrap.publicKey.replace(/'/g, "'\"'\"'")}'`
      : bootstrap?.command || ''

  function generateSetupId(): string {
    const crypto = window.crypto
    if (crypto?.randomUUID) {
      return crypto.randomUUID()
    }
    const bytes = crypto?.getRandomValues ? crypto.getRandomValues(new Uint8Array(16)) : new Uint8Array(16).map(() => Math.floor(Math.random() * 256))
    bytes[6] = (bytes[6] & 0x0f) | 0x40
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, '0'))
    return `${hex.slice(0, 4).join('')}-${hex.slice(4, 6).join('')}-${hex.slice(6, 8).join('')}-${hex.slice(8, 10).join('')}-${hex.slice(10, 16).join('')}`
  }

  const handleValidate = () => {
    if (!canCreate) {
      toast.error('Only organization owners can connect servers')
      return
    }
    if (!name.trim() || !host.trim()) {
      toast.error('Server name and host are required')
      return
    }

    const id = generateSetupId()
    setSetupId(id)
    provisionServer.mutate({
      host: host.trim(),
      adminUser: adminUser.trim() || 'root',
      name: name.trim(),
      baseDomain: baseDomain.trim() || undefined,
      autoDomains,
      proxyMode,
      setupId: id,
    })
  }

  const isBusy = provisionState === 'live' || provisionState === 'connecting' || provisionServer.isPending

  return (
    <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-center justify-center px-4" onClick={onClose}>
      <div className="bg-[#18181B] border border-[rgba(255,255,255,0.08)] rounded-2xl p-6 w-full max-w-[520px] max-h-[90vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center gap-3 mb-2">
          <div className="w-9 h-9 rounded-xl bg-rail-purple/10 flex items-center justify-center">
            <Server size={18} className="text-rail-purple" />
          </div>
          <div>
            <h3 className="text-base font-semibold text-white">Add Server</h3>
            <p className="text-[11px] text-[#6B6B7B]">Connect a remote host to RailDock</p>
          </div>
        </div>

        {!canCreate && (
          <div className="mb-4 p-3 rounded-lg bg-rail-red/10 border border-rail-red/20 text-[11px] text-rail-red">
            Only organization owners can connect servers.
          </div>
        )}

        {bootstrapError && (
          <div className="mb-4 p-3 rounded-lg bg-rail-red/10 border border-rail-red/20 flex items-start gap-2">
            <AlertCircle size={14} className="text-rail-red mt-0.5 shrink-0" />
            <div className="text-[11px] text-rail-red">
              <p className="font-medium">Could not load setup credentials</p>
              <p className="opacity-90">{bootstrapErrorDetail?.message || 'Please check your connection and try again.'}</p>
            </div>
          </div>
        )}

        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2">
              <label htmlFor="server-name" className="text-[11px] text-[#6B6B7B] block mb-1.5">Server Name</label>
              <input
                id="server-name"
                value={name}
                onChange={(e) => setName(e.target.value)}
                className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-rail-purple"
                placeholder="raildock-prod-01"
              />
            </div>
            <div className="col-span-2 sm:col-span-1">
              <label htmlFor="server-host" className="text-[11px] text-[#6B6B7B] block mb-1.5">Host / IP</label>
              <input
                id="server-host"
                value={host}
                onChange={(e) => setHost(e.target.value)}
                className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-rail-purple"
                placeholder="192.168.1.100"
              />
            </div>
            <div className="col-span-2 sm:col-span-1">
              <label htmlFor="admin-user" className="text-[11px] text-[#6B6B7B] block mb-1.5">Admin User</label>
              <input
                id="admin-user"
                value={adminUser}
                onChange={(e) => setAdminUser(e.target.value)}
                className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-rail-purple"
                placeholder="root"
              />
              <p className="text-[10px] text-[#4A4A55] mt-1">Must have passwordless sudo or root access.</p>
            </div>
            <div className="col-span-2 sm:col-span-1">
              <label htmlFor="ssh-user" className="text-[11px] text-[#6B6B7B] block mb-1.5">Deployment User</label>
              <input
                id="ssh-user"
                value={sshUser}
                onChange={(e) => setSshUser(e.target.value)}
                className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-rail-purple"
                placeholder="dokku"
              />
            </div>
            <div className="col-span-2 sm:col-span-1">
              <label htmlFor="proxy-mode" className="text-[11px] text-[#6B6B7B] block mb-1.5">Proxy Mode</label>
              <Select value={proxyMode} onValueChange={(value) => setProxyMode(value as 'managed' | 'external')}>
                <SelectTrigger id="proxy-mode">
                  <SelectValue placeholder="Select proxy mode" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="managed">RailDock managed</SelectItem>
                  <SelectItem value="external">Existing reverse proxy</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="col-span-2">
              <div className="flex items-center justify-between mb-1.5">
                <label htmlFor="base-domain" className="text-[11px] text-[#6B6B7B]">Base Domain (optional)</label>
                <button
                  type="button"
                  onClick={() => setBaseDomain('sslip.io')}
                  className="text-[10px] px-2 py-0.5 bg-rail-purple/10 text-rail-purple rounded-full hover:bg-rail-purple/20 transition-all"
                >
                  Use sslip.io
                </button>
              </div>
              <input
                id="base-domain"
                value={baseDomain}
                onChange={(e) => setBaseDomain(e.target.value)}
                className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-rail-purple"
                placeholder="example.com"
              />
              <p className="text-[10px] text-[#4A4A55] mt-1">
                {baseDomain === 'sslip.io' ? 'Auto-assigns app-name.{server-ip}.sslip.io (HTTP only)' : 'Auto-assigns subdomains like app-name.example.com'}
              </p>
            </div>
            <div className="col-span-2 flex items-center gap-2">
              <input
                id="auto-domains"
                type="checkbox"
                checked={autoDomains}
                onChange={(e) => setAutoDomains(e.target.checked)}
                className="w-3.5 h-3.5 rounded border-[rgba(255,255,255,0.15)] bg-[#0B0B0D] text-rail-purple focus:ring-rail-purple"
              />
              <label htmlFor="auto-domains" className="text-[11px] text-[#6B6B7B]">Auto-assign temporary domains for new services</label>
            </div>
          </div>

          <div className="p-3 rounded-lg bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)]">
            <p className="text-[11px] text-white font-medium mb-3 flex items-center gap-1.5">
              <Terminal size={12} /> Manual setup
            </p>

            <div className="space-y-3">
              <div>
                <div className="flex items-center justify-between mb-1.5">
                  <label className="text-[10px] text-[#6B6B7B]">Organization public key</label>
                  {bootstrap?.publicKey && (
                    <button
                      onClick={() => copy(bootstrap.publicKey, 'public-key')}
                      className="text-[10px] flex items-center gap-1 text-rail-purple hover:text-rail-purple-light transition-all"
                    >
                      {copiedKey === 'public-key' ? <Check size={11} /> : <Copy size={11} />}
                      {copiedKey === 'public-key' ? 'Copied' : 'Copy'}
                    </button>
                  )}
                </div>
                <textarea
                  readOnly
                  value={bootstrap?.publicKey || ''}
                  placeholder={bootstrapLoading ? 'Loading public key...' : 'Public key unavailable'}
                  rows={2}
                  style={{ whiteSpace: 'nowrap' }}
                  className="w-full px-3 py-2.5 bg-[#161618] border border-[rgba(255,255,255,0.08)] rounded-lg text-[10px] text-white font-mono outline-none resize-none"
                />
                <p className="text-[10px] text-[#4A4A55] mt-1">
                  Add this to <code className="text-[#6B6B7B]">~/.ssh/authorized_keys</code> for the admin user and the deployment user (e.g. <code className="text-[#6B6B7B]">/home/dokku/.ssh/authorized_keys</code>).
                </p>
              </div>

              <div>
                <div className="flex items-center justify-between mb-1.5">
                  <label className="text-[10px] text-[#6B6B7B]">Bootstrap command</label>
                  {bootstrapCommand && (
                    <button
                      onClick={() => copy(bootstrapCommand, 'command')}
                      className="text-[10px] flex items-center gap-1 text-rail-purple hover:text-rail-purple-light transition-all"
                    >
                      {copiedKey === 'command' ? <Check size={11} /> : <Copy size={11} />}
                      {copiedKey === 'command' ? 'Copied' : 'Copy'}
                    </button>
                  )}
                </div>
                <textarea
                  readOnly
                  value={bootstrapCommand}
                  placeholder={bootstrapLoading ? 'Loading bootstrap command...' : 'Bootstrap command unavailable'}
                  rows={3}
                  style={{ whiteSpace: 'nowrap' }}
                  className="w-full px-3 py-2.5 bg-[#161618] border border-[rgba(255,255,255,0.08)] rounded-lg text-[10px] text-white font-mono outline-none resize-none"
                />
                <p className="text-[10px] text-[#4A4A55] mt-1">
                  Or run this one-liner as <strong>root</strong> to install Docker/Dokku and authorize the key automatically.
                </p>
              </div>
            </div>
          </div>

          {setupId && (
            <div className="border border-[rgba(255,255,255,0.08)] rounded-lg overflow-hidden">
              <div className="w-full flex items-center justify-between px-3 py-2 bg-[#0B0B0D] text-[11px] text-[#A0A0B0]">
                <span>Validation logs</span>
                <span className="text-[10px]">
                  {provisionState === 'completed' && 'Completed'}
                  {provisionState === 'failed' && 'Failed'}
                  {(provisionState === 'live' || provisionState === 'connecting') && 'Streaming...'}
                  {!provisionState && 'Waiting...'}
                </span>
              </div>
              <div className="p-3 bg-[#161618] max-h-48 overflow-y-auto font-mono text-[10px] text-[#A0A0B0] space-y-1">
                {provisionLogs.length === 0 && !provisionError && <div className="text-[#4A4A55]">Waiting for logs...</div>}
                {provisionLogs.map((log, i) => (
                  <div key={i} className={log.stream === 'stderr' ? 'text-rail-red' : ''}>{log.line}</div>
                ))}
                {provisionError && <div className="text-rail-red">{provisionError}</div>}
                {provisionServerId && (
                  <div className="text-rail-green">Server connected (ID: {provisionServerId})</div>
                )}
              </div>
            </div>
          )}

          {provisionState === 'failed' && (
            <div className="p-3 rounded-lg bg-rail-red/10 border border-rail-red/20 flex items-start gap-2">
              <AlertCircle size={14} className="text-rail-red mt-0.5 shrink-0" />
              <div className="text-[11px] text-rail-red">
                <p className="font-medium">Validation failed</p>
                <p className="opacity-90">Run the manual bootstrap command above as root, then try again.</p>
              </div>
            </div>
          )}

          <div className="flex gap-2">
            <button
              onClick={onClose}
              className="px-4 py-2 border border-[rgba(255,255,255,0.08)] text-[#A0A0B0] text-xs rounded-lg hover:bg-[rgba(255,255,255,0.04)]"
            >
              Cancel
            </button>
            <button
              onClick={handleValidate}
              disabled={!canCreate || !name.trim() || !host.trim() || isBusy}
              className="flex-1 py-2 bg-rail-purple text-white text-xs font-medium rounded-lg hover:bg-rail-purple-dark disabled:opacity-50 flex items-center justify-center gap-2"
            >
              {isBusy && <Loader2 size={12} className="animate-spin" />}
              {isBusy ? 'Connecting...' : 'Validate Server'}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
