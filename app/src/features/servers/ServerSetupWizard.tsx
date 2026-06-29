import { useEffect, useState } from 'react'
import { AlertCircle, Check, Copy, KeyRound, Loader2, Server, Terminal } from 'lucide-react'
import { toast } from 'sonner'
import { useServerBootstrap } from '@/hooks/useOrganizations'
import { useCreateServer, useTestServer, useValidateServer } from '@/hooks/useServers'
import { useAuthStore } from '@/stores/useAuthStore'
import { useCopy } from '@/hooks/useCopy'
import type { ServerTestResult } from '@/lib/api'

type Step = 'bootstrap' | 'connect'

interface ServerSetupWizardProps {
  isOpen: boolean
  onClose: () => void
}

export default function ServerSetupWizard({ isOpen, onClose }: ServerSetupWizardProps) {
  const organizationId = useAuthStore((s) => s.currentOrganizationId)
  const organization = useAuthStore((s) => s.currentOrganization())
  const canCreate = organization?.role === 'owner'

  const { data: bootstrap, isLoading: bootstrapLoading, isError: bootstrapError, error: bootstrapErrorDetail } = useServerBootstrap(organizationId)
  const testServer = useTestServer()
  const createServer = useCreateServer()
  const validateServer = useValidateServer()
  const { copiedKey, copy } = useCopy()

  const [step, setStep] = useState<Step>('bootstrap')
  const [name, setName] = useState('')
  const [host, setHost] = useState('')
  const [sshUser, setSshUser] = useState('dokku')
  const [baseDomain, setBaseDomain] = useState('')
  const [autoDomains, setAutoDomains] = useState(true)
  const [testResult, setTestResult] = useState<ServerTestResult | null>(null)
  const [showLogs, setShowLogs] = useState(false)

  const reset = () => {
    setStep('bootstrap')
    setName('')
    setHost('')
    setSshUser('dokku')
    setBaseDomain('')
    setAutoDomains(true)
    setTestResult(null)
  }

  useEffect(() => {
    if (isOpen) reset()
  }, [isOpen])

  if (!isOpen) return null

  const handleTest = () => {
    if (!host.trim()) {
      toast.error('Host / IP is required')
      return
    }
    setTestResult(null)
    setShowLogs(true)
    testServer.mutate(
      { host: host.trim(), sshUser: sshUser.trim() || 'dokku' },
      {
        onSuccess: (result) => {
          if (result.success) {
            setTestResult(result)
            toast.success('Connection test succeeded')
          } else {
            setTestResult(result)
            toast.error(result.error || 'Connection test failed')
          }
        },
        onError: (err) => toast.error(`Connection test failed: ${err.message}`),
      }
    )
  }

  const handleAdd = () => {
    if (!name.trim() || !host.trim()) return
    if (!testResult?.success) {
      toast.error('Test the connection before adding the server')
      return
    }

    createServer.mutate(
      {
        name: name.trim(),
        host: host.trim(),
        sshUser: sshUser.trim() || 'dokku',
        baseDomain: baseDomain.trim() || undefined,
        autoDomains,
        hostKey: testResult.hostKey,
        hostKeyFingerprint: testResult.hostKeyFingerprint,
      },
      {
        onSuccess: (server) => {
          validateServer.mutate(server.id)
          toast.success('Server added')
          onClose()
        },
      }
    )
  }

  const renderStepIndicator = () => (
    <div className="flex items-center gap-2 mb-6">
      <button
        onClick={() => setStep('bootstrap')}
        className={`flex items-center gap-1.5 text-[11px] font-medium px-2.5 py-1 rounded-full transition-all ${
          step === 'bootstrap' ? 'bg-rail-purple/20 text-rail-purple' : 'text-[#6B6B7B] hover:text-white'
        }`}
      >
        <span className={`w-4 h-4 rounded-full text-[9px] flex items-center justify-center ${step === 'bootstrap' ? 'bg-rail-purple text-white' : 'bg-white/10'}`}>1</span>
        Prepare server
      </button>
      <div className="w-4 h-px bg-white/10" />
      <button
        onClick={() => testResult?.success && setStep('connect')}
        disabled={!testResult?.success}
        className={`flex items-center gap-1.5 text-[11px] font-medium px-2.5 py-1 rounded-full transition-all ${
          step === 'connect' ? 'bg-rail-purple/20 text-rail-purple' : 'text-[#6B6B7B] hover:text-white'
        }`}
      >
        <span className={`w-4 h-4 rounded-full text-[9px] flex items-center justify-center ${step === 'connect' ? 'bg-rail-purple text-white' : 'bg-white/10'}`}>2</span>
        Connect
      </button>
    </div>
  )

  return (
    <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-center justify-center px-4" onClick={onClose}>
      <div className="bg-[#18181B] border border-[rgba(255,255,255,0.08)] rounded-2xl p-6 w-full max-w-[520px] max-h-[90vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center gap-3 mb-2">
          <div className="w-9 h-9 rounded-xl bg-rail-purple/10 flex items-center justify-center">
            <Server size={18} className="text-rail-purple" />
          </div>
          <div>
            <h3 className="text-base font-semibold text-white">Add Server</h3>
            <p className="text-[11px] text-[#6B6B7B]">Connect a remote Dokku host</p>
          </div>
        </div>

        {renderStepIndicator()}

        {!canCreate && (
          <div className="mb-4 p-3 rounded-lg bg-rail-red/10 border border-rail-red/20 text-[11px] text-rail-red">
            Only organization owners can add servers.
          </div>
        )}

        {step === 'bootstrap' && (
          <div className="space-y-4">
            {bootstrapError && (
              <div className="p-3 rounded-lg bg-rail-red/10 border border-rail-red/20 flex items-start gap-2">
                <AlertCircle size={14} className="text-rail-red mt-0.5 shrink-0" />
                <div className="text-[11px] text-rail-red">
                  <p className="font-medium">Could not load setup credentials</p>
                  <p className="opacity-90">{bootstrapErrorDetail?.message || 'Please check your connection and try again.'}</p>
                </div>
              </div>
            )}
            <div className="p-3 rounded-lg bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)]">
              <h4 className="text-xs font-medium text-white mb-1">1. Authorize RailDock</h4>
              <p className="text-[11px] text-[#6B6B7B] mb-3">
                Copy the public key below and add it to the remote host, or run the bootstrap script as root to install Docker, Dokku, and authorize the key automatically.
              </p>

              <div className="space-y-3">
                <div>
                  <div className="flex items-center justify-between mb-1.5">
                    <label className="text-[10px] text-[#6B6B7B] flex items-center gap-1.5">
                      <KeyRound size={11} /> Organization public key
                    </label>
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
                    rows={3}
                    className="w-full px-3 py-2.5 bg-[#161618] border border-[rgba(255,255,255,0.08)] rounded-lg text-[10px] text-white font-mono outline-none resize-none"
                  />
                </div>

                <div>
                  <div className="flex items-center justify-between mb-1.5">
                    <label className="text-[10px] text-[#6B6B7B] flex items-center gap-1.5">
                      <Terminal size={11} /> Bootstrap command
                    </label>
                    {bootstrap?.command && (
                      <button
                        onClick={() => copy(bootstrap.command, 'command')}
                        className="text-[10px] flex items-center gap-1 text-rail-purple hover:text-rail-purple-light transition-all"
                      >
                        {copiedKey === 'command' ? <Check size={11} /> : <Copy size={11} />}
                        {copiedKey === 'command' ? 'Copied' : 'Copy'}
                      </button>
                    )}
                  </div>
                  <textarea
                    readOnly
                    value={bootstrap?.command || ''}
                    placeholder={bootstrapLoading ? 'Loading bootstrap command...' : 'Bootstrap command unavailable'}
                    rows={3}
                    className="w-full px-3 py-2.5 bg-[#161618] border border-[rgba(255,255,255,0.08)] rounded-lg text-[10px] text-white font-mono outline-none resize-none"
                  />
                </div>
              </div>
            </div>

            <div className="flex justify-between items-center">
              <button
                onClick={() => setStep('connect')}
                className="text-[11px] text-[#6B6B7B] hover:text-white transition-all"
              >
                I already added the key →
              </button>
              <button
                onClick={() => setStep('connect')}
                className="px-4 py-2 bg-rail-purple text-white text-xs font-medium rounded-lg hover:bg-rail-purple-dark transition-all"
              >
                Continue
              </button>
            </div>
          </div>
        )}

        {step === 'connect' && (
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-3">
              <div className="col-span-2">
                <label htmlFor="wizard-name" className="text-[11px] text-[#6B6B7B] block mb-1.5">Server Name</label>
                <input
                  id="wizard-name"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-rail-purple"
                  placeholder="dokku-prod-01"
                />
              </div>
              <div className="col-span-2 sm:col-span-1">
                <label htmlFor="wizard-host" className="text-[11px] text-[#6B6B7B] block mb-1.5">Host / IP</label>
                <input
                  id="wizard-host"
                  value={host}
                  onChange={(e) => {
                    setHost(e.target.value)
                    setTestResult(null)
                  }}
                  className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-rail-purple"
                  placeholder="192.168.1.100"
                />
              </div>
              <div className="col-span-2 sm:col-span-1">
                <label htmlFor="wizard-ssh-user" className="text-[11px] text-[#6B6B7B] block mb-1.5">SSH User</label>
                <input
                  id="wizard-ssh-user"
                  value={sshUser}
                  onChange={(e) => {
                    setSshUser(e.target.value)
                    setTestResult(null)
                  }}
                  className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-rail-purple"
                  placeholder="dokku"
                />
              </div>
              <div className="col-span-2">
                <div className="flex items-center justify-between mb-1.5">
                  <label htmlFor="wizard-base-domain" className="text-[11px] text-[#6B6B7B]">Base Domain (optional)</label>
                  <button
                    type="button"
                    onClick={() => setBaseDomain('sslip.io')}
                    className="text-[10px] px-2 py-0.5 bg-rail-purple/10 text-rail-purple rounded-full hover:bg-rail-purple/20 transition-all"
                  >
                    Use sslip.io
                  </button>
                </div>
                <input
                  id="wizard-base-domain"
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
                  id="wizard-auto-domains"
                  type="checkbox"
                  checked={autoDomains}
                  onChange={(e) => setAutoDomains(e.target.checked)}
                  className="w-3.5 h-3.5 rounded border-[rgba(255,255,255,0.15)] bg-[#0B0B0D] text-rail-purple focus:ring-rail-purple"
                />
                <label htmlFor="wizard-auto-domains" className="text-[11px] text-[#6B6B7B]">Auto-assign temporary domains for new services</label>
              </div>
            </div>

            {testResult?.success && (
              <div className="p-3 rounded-lg bg-rail-green/10 border border-rail-green/20 space-y-2">
                <div className="flex items-center gap-2 text-rail-green text-[11px] font-medium">
                  <Check size={12} /> Connection verified
                </div>
                <div className="grid grid-cols-2 gap-2 text-[10px]">
                  <div className="text-[#6B6B7B]">Dokku <span className="text-white ml-1">{testResult.dokkuVersion || 'unknown'}</span></div>
                  <div className="text-[#6B6B7B]">Docker <span className="text-white ml-1">{testResult.dockerVersion || 'unknown'}</span></div>
                  <div className="col-span-2 text-[#6B6B7B] truncate" title={testResult.hostKeyFingerprint}>
                    Host key <span className="text-white ml-1 font-mono">{testResult.hostKeyFingerprint || 'unknown'}</span>
                  </div>
                </div>
              </div>
            )}

            {testServer.error && !testResult && (
              <div className="p-3 rounded-lg bg-rail-red/10 border border-rail-red/20 text-[11px] text-rail-red">
                {testServer.error.message}
              </div>
            )}

            {(testResult?.logs || testServer.error) && (
              <div className="border border-[rgba(255,255,255,0.08)] rounded-lg overflow-hidden">
                <button
                  onClick={() => setShowLogs((s) => !s)}
                  className="w-full flex items-center justify-between px-3 py-2 bg-[#0B0B0D] text-[11px] text-[#A0A0B0] hover:text-white"
                >
                  <span>Setup logs</span>
                  <span className="text-[10px]">{showLogs ? 'Hide' : 'Show'}</span>
                </button>
                {showLogs && (
                  <div className="p-3 bg-[#161618] max-h-40 overflow-y-auto font-mono text-[10px] text-[#A0A0B0] space-y-1">
                    {testResult?.logs?.map((line, i) => <div key={i}>{line}</div>)}
                    {testServer.error && <div className="text-rail-red">{testServer.error.message}</div>}
                  </div>
                )}
              </div>
            )}

            <div className="flex gap-2">
              <button
                onClick={() => setStep('bootstrap')}
                className="px-4 py-2 border border-[rgba(255,255,255,0.08)] text-[#A0A0B0] text-xs rounded-lg hover:bg-[rgba(255,255,255,0.04)]"
              >
                Back
              </button>
              <button
                onClick={handleTest}
                disabled={!host.trim() || testServer.isPending}
                className="flex-1 py-2 border border-rail-purple/30 text-rail-purple text-xs font-medium rounded-lg hover:bg-rail-purple/10 disabled:opacity-50 flex items-center justify-center gap-2"
              >
                {testServer.isPending && <Loader2 size={12} className="animate-spin" />}
                {testServer.isPending ? 'Testing...' : testResult?.success ? 'Test Again' : 'Test Connection'}
              </button>
              <button
                onClick={handleAdd}
                disabled={!canCreate || !testResult?.success || createServer.isPending}
                className="flex-1 py-2 bg-rail-purple text-white text-xs font-medium rounded-lg hover:bg-rail-purple-dark disabled:opacity-50"
              >
                {createServer.isPending ? 'Adding...' : 'Add Server'}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
