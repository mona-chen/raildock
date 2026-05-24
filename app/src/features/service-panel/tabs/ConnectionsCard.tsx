import { useState } from 'react'
import { Link2, Unlink, Copy, Check } from 'lucide-react'
import { useCopy } from '@/hooks/useCopy'
import { ServiceIcon } from '@/components/icons/ServiceIcons'
import { useUnlinkService, useLinkedByServices } from '@/hooks/useServices'
import type { Service } from '@/types'

function maskConnectionUrl(url: string): string {
  try {
    const u = new URL(url)
    if (u.password) u.password = '••••••••'
    return u.toString()
  } catch {
    return url
  }
}

function quickConnectCommand(subtype: string, url: string): string {
  try {
    const u = new URL(url)
    const host = u.hostname
    const port = u.port
    const user = u.username
    const db = u.pathname.replace(/^\//, '')
    switch (subtype) {
      case 'postgres': return `psql "${url}"`
      case 'mysql': return `mysql -h ${host} -P ${port} -u ${user} -p ${db}`
      case 'mongo': return `mongosh "${url}"`
      case 'redis': return `redis-cli -h ${host} -p ${port} --tls`
      default: return ''
    }
  } catch {
    return ''
  }
}

export default function ConnectionsCard({ svc, serviceId }: { svc: Service; serviceId: string }) {
  const unlinkService = useUnlinkService()
  const { data: linkedByServices } = useLinkedByServices(serviceId)
  const { copiedKey, copy } = useCopy(1500)
  const [expanded, setExpanded] = useState<string | null>(null)

  const connectionVars = (svc.envVars || []).filter(
    (ev) => ev.isDokkuInternal && ev.key.match(/^(DATABASE_URL|REDIS_URL|MONGO_URL|MYSQL_URL)/i)
  )

  const isDb = svc.type === 'database'

  return (
    <div className="space-y-4">
      {!isDb && (
        <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4">
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-2">
              <Link2 size={14} className="text-[#8b5cf6]" />
              <div className="text-[13px] font-medium text-white/70">Connections</div>
            </div>
            <span className="text-[10px] px-2 py-0.5 bg-white/5 text-white/40 rounded">
              {connectionVars.length}
            </span>
          </div>

          {connectionVars.length === 0 ? (
            <div className="text-[12px] text-white/30 py-2">No databases linked. Use the canvas to link a service.</div>
          ) : (
            <div className="space-y-3">
              {connectionVars.map((ev) => {
                const cmd = quickConnectCommand(svc.subtype, ev.value)
                const isExpanded = expanded === ev.key
                return (
                  <div key={ev.key} className="bg-black/30 border border-white/[0.04] rounded-lg p-3">
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-2">
                        <ServiceIcon subtype={ev.key.includes('REDIS') ? 'redis' : ev.key.includes('MONGO') ? 'mongo' : ev.key.includes('MYSQL') ? 'mysql' : 'postgres'} size={13} />
                        <span className="text-[12px] font-medium text-white/60">{ev.key}</span>
                      </div>
                      <div className="flex items-center gap-1">
                        <button
                          onClick={() => copy(ev.value, ev.key)}
                          className="p-1.5 rounded hover:bg-white/[0.06] text-white/30 hover:text-white/60 transition-colors"
                          title="Copy connection string"
                        >
                          {copiedKey === ev.key ? <Check size={12} className="text-[#22c55e]" /> : <Copy size={12} />}
                        </button>
                      </div>
                    </div>

                    <div className="font-mono text-[11px] text-white/40 break-all bg-black/20 rounded px-2.5 py-2 mb-2">
                      {maskConnectionUrl(ev.value)}
                    </div>

                    {cmd && (
                      <button
                        onClick={() => setExpanded(isExpanded ? null : ev.key)}
                        className="text-[11px] text-[#8b5cf6]/70 hover:text-[#8b5cf6] transition-colors"
                      >
                        {isExpanded ? 'Hide' : 'Show'} quick-connect CLI
                      </button>
                    )}
                    {isExpanded && cmd && (
                      <div className="mt-2 relative">
                        <div className="font-mono text-[11px] text-white/50 bg-black/30 rounded px-2.5 py-2 pr-8">
                          {cmd}
                        </div>
                        <button
                          onClick={() => copy(cmd, `${ev.key}-cmd`)}
                          className="absolute right-1.5 top-1.5 p-1 rounded hover:bg-white/[0.06] text-white/20 hover:text-white/50 transition-colors"
                        >
                          {copiedKey === `${ev.key}-cmd` ? <Check size={10} className="text-[#22c55e]" /> : <Copy size={10} />}
                        </button>
                      </div>
                    )}
                  </div>
                )
              })}
            </div>
          )}
        </div>
      )}

      {isDb && (
        <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4">
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-2">
              <Link2 size={14} className="text-[#8b5cf6]" />
              <div className="text-[13px] font-medium text-white/70">Connected Apps</div>
            </div>
            <span className="text-[10px] px-2 py-0.5 bg-white/5 text-white/40 rounded">
              {linkedByServices?.length || 0}
            </span>
          </div>

          {!linkedByServices || linkedByServices.length === 0 ? (
            <div className="text-[12px] text-white/30 py-2">No apps are using this database yet.</div>
          ) : (
            <div className="space-y-2">
              {linkedByServices.map((app) => (
                <div key={app.id} className="flex items-center justify-between bg-black/30 border border-white/[0.04] rounded-lg px-3 py-2">
                  <div className="flex items-center gap-2">
                    <ServiceIcon subtype={app.subtype} dockerImage={app.dockerImage} size={13} />
                    <span className="text-[12px] text-white/60">{app.name}</span>
                    <span className="text-[10px] text-white/30">{app.subtype}</span>
                  </div>
                  <button
                    onClick={() => unlinkService.mutate({ id: app.id, targetId: serviceId })}
                    disabled={unlinkService.isPending}
                    className="p-1.5 rounded hover:bg-white/[0.06] text-white/20 hover:text-red-400 transition-colors disabled:opacity-50"
                    title="Unlink"
                  >
                    <Unlink size={12} />
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  )
}
