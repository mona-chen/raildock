import { useState } from 'react'
import { Globe, Trash2, ShieldCheck, ShieldAlert, ShieldQuestion, Info } from 'lucide-react'
import { useAddDomain, useRemoveDomain, useGenerateDomain } from '@/hooks/useServices'
import type { Service, Domain } from '@/types'

function normalizeHostname(value: string): string {
  return value
    .trim()
    .replace(/^https?:\/\//i, '')
    .replace(/:\d+$/, '')
    .replace(/\/.*$/, '')
    .toLowerCase()
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

export default function DomainsTab({ svc }: { svc: Service }) {
  const addDomain = useAddDomain()
  const removeDomain = useRemoveDomain()
  const generateDomain = useGenerateDomain()
  const [newDomain, setNewDomain] = useState('')
  const [targetPort, setTargetPort] = useState(svc.detectedPort || 80)

  return (
    <div className="p-5 space-y-4">
      <div className="flex items-center justify-between">
        <div className="text-[14px] font-medium text-white/70">Domains</div>
        <button
          onClick={() => generateDomain.mutate(svc.id)}
          disabled={generateDomain.isPending}
          className="flex items-center gap-1.5 px-3 py-1.5 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[12px] hover:bg-[#8b5cf6]/25 transition-all disabled:opacity-50"
        >
          <Globe size={13} />
          {generateDomain.isPending ? 'Generating...' : 'Generate Domain'}
        </button>
      </div>

      {svc.domains.length > 0 ? (
        <div className="space-y-2">
          {svc.domains.map((d) => (
            <div key={d.hostname} className="space-y-0">
              <div className="flex items-center gap-3 bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3 group">
                <Globe size={15} className="text-white/30" />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="text-[13px] text-white/70 truncate">{d.hostname}</span>
                    {d.wildcard && (
                      <span className="text-[10px] px-1.5 bg-[#f59e0b]/10 text-[#f59e0b] rounded-full">Wildcard</span>
                    )}
                  </div>
                  <div className="text-[11px] text-white/30">→ :{d.targetPort || svc.detectedPort || 80}</div>
                </div>
                <SslBadge domain={d} />
                {d.temporary && (
                  <span className="text-[10px] px-1.5 bg-[#8b5cf6]/10 text-[#8b5cf6] rounded-full">Auto</span>
                )}
                <button
                  onClick={() => removeDomain.mutate({ id: svc.id, hostname: normalizeHostname(d.hostname) })}
                  className="ml-auto p-1.5 hover:bg-white/[0.06] rounded text-white/20 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity"
                >
                  <Trash2 size={12} />
                </button>
              </div>
              <SslAlert domain={d} />
            </div>
          ))}
        </div>
      ) : (
        <div className="text-[13px] text-white/30 py-4 text-center">No domains configured</div>
      )}

      <div className="border-t border-white/[0.06] pt-4">
        <div className="text-[12px] text-white/40 mb-2">Add custom domain</div>
        <div className="flex gap-2">
          <input
            type="text"
            placeholder="example.com or *.example.com"
            value={newDomain}
            onChange={(e) => setNewDomain(e.target.value)}
            className="flex-1 bg-black/40 border border-white/[0.08] rounded-lg px-3 py-2 text-[13px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
          />
          <input
            type="number"
            placeholder="Port"
            value={targetPort}
            onChange={(e) => setTargetPort(Number(e.target.value))}
            className="w-20 bg-black/40 border border-white/[0.08] rounded-lg px-3 py-2 text-[13px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
          />
          <button
            onClick={() => {
              const hostname = normalizeHostname(newDomain)
              if (hostname) {
                addDomain.mutate({ id: svc.id, hostname, port: 443, targetPort })
                setNewDomain('')
              }
            }}
            className="px-4 py-2 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[13px] hover:bg-[#8b5cf6]/25 transition-all"
          >
            Add
          </button>
        </div>
      </div>
    </div>
  )
}
