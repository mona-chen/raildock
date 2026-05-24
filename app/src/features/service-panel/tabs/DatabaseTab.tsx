import { useCopy } from '@/hooks/useCopy'
import { useDatabaseInfo } from '@/hooks/useServices'
import type { Service } from '@/types'

export default function DatabaseTab({ svc, serviceId }: { svc: Service; serviceId: string }) {
  const { data: info, isLoading } = useDatabaseInfo(serviceId)
  const { copiedKey, copy } = useCopy(2000)

  const connectionUrl = info?.url || info?.dsn || svc.envVars.find((e) => e.key.includes('URL'))?.value

  const connectionFields = [
    { label: 'Host', value: info?.host },
    { label: 'Port', value: info?.port?.toString() },
    { label: 'Username', value: info?.username },
    { label: 'Password', value: info?.password },
    { label: 'Database', value: info?.database },
  ].filter((f) => f.value)

  const quickConnect = (() => {
    const { subtype, username, password, host, port, database } = {
      subtype: svc.subtype,
      username: info?.username,
      password: info?.password,
      host: info?.host,
      port: info?.port,
      database: info?.database,
    }
    if (!host || !port) return null
    switch (subtype) {
      case 'postgres':
        return `psql ${connectionUrl || `postgresql://${username}:${password}@${host}:${port}/${database}`}`
      case 'redis':
        return `redis-cli -h ${host} -p ${port} ${password ? `-a ${password}` : ''}`
      case 'mysql':
        return `mysql -h ${host} -P ${port} -u ${username || 'root'} ${password ? `-p${password}` : ''} ${database || ''}`
      case 'mongo':
        return `mongosh ${connectionUrl || `mongodb://${username}:${password}@${host}:${port}/${database}`}`
      default:
        return null
    }
  })()

  return (
    <div className="p-5 space-y-4">
      <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4">
        <div className="flex items-center justify-between mb-3">
          <div className="text-[13px] font-medium text-white/70">Connection</div>
          {info?.status && (
            <span
              className={`text-[11px] px-2 py-0.5 rounded-full ${
                info.status === 'running' ? 'bg-emerald-500/10 text-emerald-400' : 'bg-white/5 text-white/40'
              }`}
            >
              {info.status}
            </span>
          )}
        </div>

        {isLoading ? (
          <div className="space-y-2">
            <div className="h-8 bg-white/[0.03] rounded animate-pulse" />
            <div className="h-20 bg-white/[0.03] rounded animate-pulse" />
          </div>
        ) : connectionUrl ? (
          <>
            <div className="bg-black/20 rounded-lg p-3 mb-3 relative group">
              <div className="flex items-center justify-between mb-1">
                <div className="text-[11px] text-white/40">Connection URL</div>
                <button
                  type="button"
                  onClick={() => copy(connectionUrl, 'url')}
                  className="text-[11px] text-white/30 hover:text-white/60 transition-colors"
                >
                  {copiedKey === 'url' ? 'Copied!' : 'Copy'}
                </button>
              </div>
              <div className="text-[12px] text-white/70 font-mono break-all">{connectionUrl}</div>
            </div>

            {connectionFields.length > 0 && (
              <div className="grid grid-cols-2 gap-2 mb-3">
                {connectionFields.map((f) => (
                  <div key={f.label} className="bg-black/20 rounded-lg p-2.5 relative group">
                    <div className="flex items-center justify-between mb-0.5">
                      <div className="text-[11px] text-white/40">{f.label}</div>
                      <button
                        type="button"
                        onClick={() => copy(f.value!, f.label)}
                        className="opacity-0 group-hover:opacity-100 text-[10px] text-white/30 hover:text-white/60 transition-all"
                      >
                        {copiedKey === f.label ? 'Copied!' : 'Copy'}
                      </button>
                    </div>
                    <div className="text-[12px] text-white/70 font-mono break-all">{f.value}</div>
                  </div>
                ))}
              </div>
            )}

            {quickConnect && (
              <div className="bg-black/20 rounded-lg p-3 relative group">
                <div className="flex items-center justify-between mb-1">
                  <div className="text-[11px] text-white/40">Quick Connect</div>
                  <button
                    type="button"
                    onClick={() => copy(quickConnect, 'cmd')}
                    className="text-[11px] text-white/30 hover:text-white/60 transition-colors"
                  >
                    {copiedKey === 'cmd' ? 'Copied!' : 'Copy'}
                  </button>
                </div>
                <div className="text-[12px] text-white/70 font-mono break-all">{quickConnect}</div>
              </div>
            )}
          </>
        ) : (
          <div className="text-[12px] text-white/30">
            {info?.error || 'No connection details available. Ensure the database server is running.'}
          </div>
        )}
      </div>

      <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4">
        <div className="text-[13px] font-medium text-white/70 mb-3">Service Details</div>
        <div className="grid grid-cols-2 gap-2">
          {[
            { l: 'Type', v: svc.subtype },
            { l: 'Version', v: svc.version || info?.version || 'latest' },
            { l: 'Name', v: svc.name },
            { l: 'Status', v: svc.status },
            { l: 'Internal IP', v: info?.internal_ip },
            { l: 'Internal Hostname', v: svc.internalHostname },
            { l: 'Dokku Name', v: svc.name?.replace(/[^a-z0-9]/gi, '-').toLowerCase() },
          ]
            .filter((f) => f.v)
            .map((f) => (
              <div key={f.l} className="bg-black/20 rounded-lg p-2.5">
                <div className="text-[11px] text-white/40">{f.l}</div>
                <div className="text-[12px] text-white/70 font-mono mt-0.5 break-all">{f.v}</div>
              </div>
            ))}
        </div>
      </div>
    </div>
  )
}
