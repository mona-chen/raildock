import { useState, useMemo } from 'react'
import { Globe, Trash2, ShieldCheck, ShieldAlert, ShieldQuestion, Info, Copy, Check, ExternalLink, AlertTriangle, ChevronDown } from 'lucide-react'
import { useAddDomain, useRemoveDomain, useGenerateDomain } from '@/hooks/useServices'
import { useCopy } from '@/hooks/useCopy'
import type { Service, Domain } from '@/types'

interface NormalizedInput {
  hostname: string
  error?: string
  hadProtocol: boolean
  hadPort: string | null
  hadPath: string | null
}

function normalizeHostnameInput(value: string): NormalizedInput {
  const raw = value.trim()
  if (!raw) return { hostname: '', hadProtocol: false, hadPort: null, hadPath: null }

  let working = raw
  let hadProtocol = false
  let hadPort: string | null = null
  let hadPath: string | null = null

  // Strip protocol
  const protocolMatch = working.match(/^https?:\/\//i)
  if (protocolMatch) {
    hadProtocol = true
    working = working.slice(protocolMatch[0].length)
  }

  // Split host from path first
  const pathIdx = working.indexOf('/')
  if (pathIdx !== -1) {
    hadPath = working.slice(pathIdx)
    working = working.slice(0, pathIdx)
  }

  // Strip port
  const portMatch = working.match(/:(\d+)$/)
  if (portMatch) {
    hadPort = portMatch[1]
    working = working.slice(0, -portMatch[0].length)
  }

  const hostname = working.toLowerCase()

  // Basic hostname validation: allow wildcard prefix, alphanumerics, hyphens, dots
  const isValid =
    hostname.length > 0 &&
    hostname.length <= 253 &&
    /^\*?(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$/i.test(hostname)

  let error: string | undefined
  if (!isValid) {
    error = 'Enter a valid hostname like example.com or *.example.com'
  }

  return { hostname, error, hadProtocol, hadPort, hadPath }
}

function SslBadge({ domain }: { domain: Domain }) {
  const status = domain.sslStatus || (domain.ssl ? 'pending' : 'none')

  switch (status) {
    case 'active':
      return (
        <span
          className="text-[10px] px-1.5 bg-[#22c55e]/10 text-[#22c55e] rounded-full flex items-center gap-1"
          title={domain.sslExpiresAt ? `Valid until ${new Date(domain.sslExpiresAt).toLocaleDateString()}` : 'SSL active'}
        >
          <ShieldCheck size={10} /> SSL
        </span>
      )
    case 'pending':
      return (
        <span
          className="text-[10px] px-1.5 bg-[#eab308]/10 text-[#eab308] rounded-full flex items-center gap-1"
          title="Certificate provisioning..."
        >
          <ShieldQuestion size={10} /> SSL
        </span>
      )
    case 'failed':
      return (
        <span
          className="text-[10px] px-1.5 bg-[#ef4444]/10 text-[#ef4444] rounded-full flex items-center gap-1"
          title={domain.sslStatusMessage || 'SSL failed'}
        >
          <ShieldAlert size={10} /> SSL
        </span>
      )
    default:
      return (
        <span
          className="text-[10px] px-1.5 bg-white/5 text-white/40 rounded-full"
          title="No SSL — HTTP only"
        >
          HTTP
        </span>
      )
  }
}

function SslAlert({ domain }: { domain: Domain }) {
  if (domain.sslStatus !== 'failed' || !domain.sslStatusMessage) return null

  return (
    <div className="flex items-start gap-2 mt-2 p-2.5 bg-[#ef4444]/5 border border-[#ef4444]/20 rounded-lg">
      <Info size={14} className="text-[#ef4444] mt-0.5 flex-shrink-0" />
      <div className="text-[11px] text-[#ef4444]/80 leading-relaxed">
        {domain.sslStatusMessage}
      </div>
    </div>
  )
}

function DomainRow({ domain, svc, onRemove }: { domain: Domain; svc: Service; onRemove: () => void }) {
  const { copy, copiedKey } = useCopy(1500)
  const scheme = domain.ssl ? 'https' : 'http'
  const url = `${scheme}://${domain.hostname}`
  const targetPort = domain.targetPort || svc.detectedPort || svc.port || 80
  const isRoutingMismatch = Boolean(
    svc.detectedPort && domain.targetPort && domain.targetPort !== svc.detectedPort
  )

  return (
    <div className="space-y-0">
      <div className="flex items-center gap-3 bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-3 group hover:border-white/[0.10] transition-colors">
        <Globe size={15} className="text-white/30 flex-shrink-0" />
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <a
              href={url}
              target="_blank"
              rel="noreferrer"
              className="text-[13px] text-white/70 hover:text-[#8b5cf6] truncate transition-colors"
              title={url}
            >
              {domain.hostname}
            </a>
            {domain.wildcard && (
              <span className="text-[10px] px-1.5 bg-[#f59e0b]/10 text-[#f59e0b] rounded-full">Wildcard</span>
            )}
            {domain.temporary && (
              <span className="text-[10px] px-1.5 bg-[#8b5cf6]/10 text-[#8b5cf6] rounded-full">Auto-generated</span>
            )}
          </div>
          <div className="flex items-center gap-2 mt-0.5">
            <span className="text-[11px] text-white/30">→ container port {targetPort}</span>
            {isRoutingMismatch && (
              <span className="text-[10px] text-amber-400/80 flex items-center gap-1" title="Domain target port differs from the app's detected port. Redeploy to align them.">
                <AlertTriangle size={10} /> mismatch
              </span>
            )}
          </div>
        </div>
        <SslBadge domain={domain} />
        <div className="flex items-center gap-0.5 opacity-100 sm:opacity-0 sm:group-hover:opacity-100 transition-opacity">
          <button
            onClick={() => copy(url, domain.hostname)}
            className="p-1.5 hover:bg-white/[0.06] rounded text-white/20 hover:text-white/60 transition-colors"
            title="Copy URL"
          >
            {copiedKey === domain.hostname ? <Check size={12} className="text-[#22c55e]" /> : <Copy size={12} />}
          </button>
          <a
            href={url}
            target="_blank"
            rel="noreferrer"
            className="p-1.5 hover:bg-white/[0.06] rounded text-white/20 hover:text-white/60 transition-colors"
            title="Open URL"
          >
            <ExternalLink size={12} />
          </a>
          <button
            onClick={() => {
              if (confirm(`Remove domain ${domain.hostname}?`)) {
                onRemove()
              }
            }}
            className="p-1.5 hover:bg-white/[0.06] rounded text-white/20 hover:text-red-400 transition-colors"
            title="Remove domain"
          >
            <Trash2 size={12} />
          </button>
        </div>
      </div>
      <SslAlert domain={domain} />
    </div>
  )
}

export default function DomainsTab({ svc }: { svc: Service }) {
  const addDomain = useAddDomain()
  const removeDomain = useRemoveDomain()
  const generateDomain = useGenerateDomain()
  const [input, setInput] = useState('')
  const [showAdvanced, setShowAdvanced] = useState(false)
  const [targetPort, setTargetPort] = useState<string>(
    String(svc.detectedPort || svc.port || '')
  )

  const normalized = useMemo(() => normalizeHostnameInput(input), [input])
  const detectedOrDefault = svc.detectedPort || svc.port || 80

  const handleAdd = () => {
    if (!normalized.hostname || normalized.error) return

    const payload: { id: string; hostname: string; port: number; targetPort?: number } = {
      id: svc.id,
      hostname: normalized.hostname,
      port: 443,
    }

    const explicitTarget = targetPort ? parseInt(targetPort, 10) : undefined
    if (explicitTarget && explicitTarget !== detectedOrDefault) {
      payload.targetPort = explicitTarget
    }

    addDomain.mutate(payload)
    setInput('')
    setTargetPort(String(svc.detectedPort || svc.port || ''))
    setShowAdvanced(false)
  }

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter' && normalized.hostname && !normalized.error) {
      handleAdd()
    }
  }

  return (
    <div className="p-5 space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <div className="text-[14px] font-medium text-white/70">Domains</div>
          <div className="text-[11px] text-white/40">
            {svc.domains.length === 0
              ? 'No domains configured'
              : `${svc.domains.length} domain${svc.domains.length === 1 ? '' : 's'} configured`}
          </div>
        </div>
        <button
          onClick={() => generateDomain.mutate(svc.id)}
          disabled={generateDomain.isPending}
          className="flex items-center gap-1.5 px-3 py-1.5 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[12px] hover:bg-[#8b5cf6]/25 transition-all disabled:opacity-50"
        >
          <Globe size={13} />
          {generateDomain.isPending ? 'Generating...' : 'Generate Domain'}
        </button>
      </div>

      <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4 space-y-3">
        <label className="text-[12px] text-white/50 block">Add custom domain</label>
        <div className="flex gap-2">
          <div className="flex-1 min-w-0 relative">
            <input
              type="text"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="example.com or *.example.com"
              className="w-full bg-black/40 border border-white/[0.08] rounded-lg px-3 py-2 text-[13px] text-white/70 placeholder:text-white/20 focus:outline-none focus:border-[#8b5cf6]/40"
            />
          </div>
          <button
            onClick={handleAdd}
            disabled={!normalized.hostname || Boolean(normalized.error) || addDomain.isPending}
            className="px-4 py-2 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[13px] hover:bg-[#8b5cf6]/25 transition-all disabled:opacity-50"
          >
            {addDomain.isPending ? 'Adding...' : 'Add'}
          </button>
        </div>

        {input && (
          <div className="space-y-1">
            {normalized.error ? (
              <div className="text-[11px] text-red-400 flex items-center gap-1">
                <AlertTriangle size={11} />
                {normalized.error}
              </div>
            ) : (
              <div className="text-[11px] text-white/40">
                Will be saved as{' '}
                <span className="text-white/70 font-medium">{normalized.hostname}</span>
                {(normalized.hadProtocol || normalized.hadPort || normalized.hadPath) && (
                  <span className="text-white/30">
                    {' '}
                    (stripped
                    {normalized.hadProtocol ? ' protocol' : ''}
                    {normalized.hadPort ? ` port :${normalized.hadPort}` : ''}
                    {normalized.hadPath ? ' path' : ''})
                  </span>
                )}
              </div>
            )}
          </div>
        )}

        <button
          onClick={() => setShowAdvanced((v) => !v)}
          className="flex items-center gap-1 text-[11px] text-white/40 hover:text-white/60 transition-colors"
        >
          <ChevronDown size={12} className={showAdvanced ? 'rotate-180' : ''} />
          Advanced
        </button>

        {showAdvanced && (
          <div className="space-y-2 pt-1">
            <label className="text-[11px] text-white/40 block">Target container port</label>
            <div className="flex items-center gap-2">
              <input
                type="number"
                value={targetPort}
                onChange={(e) => setTargetPort(e.target.value)}
                placeholder={String(detectedOrDefault)}
                className="w-28 bg-black/40 border border-white/[0.08] rounded-lg px-3 py-1.5 text-[13px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
              />
              <span className="text-[11px] text-white/30">
                Leave blank to use {detectedOrDefault === 80 ? 'the detected port' : detectedOrDefault}
              </span>
            </div>
          </div>
        )}
      </div>

      {svc.domains.length > 0 ? (
        <div className="space-y-2">
          {svc.domains.map((d) => (
            <DomainRow
              key={d.hostname}
              domain={d}
              svc={svc}
              onRemove={() => removeDomain.mutate({ id: svc.id, hostname: d.hostname })}
            />
          ))}
        </div>
      ) : (
        <div className="text-center py-8 border border-dashed border-white/[0.06] rounded-xl">
          <Globe size={24} className="mx-auto text-white/20 mb-2" />
          <div className="text-[13px] text-white/50">No domains yet</div>
          <div className="text-[11px] text-white/30 mt-0.5">
            Add a custom domain or generate a temporary one to expose this service.
          </div>
        </div>
      )}
    </div>
  )
}
