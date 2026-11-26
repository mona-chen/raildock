import { useState } from 'react'
import { AlertTriangle, CheckCircle2, CircleSlash, Loader2, Play, RefreshCw, RotateCw, ScrollText, Square } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import ConfirmDialog from '@/features/shared/ConfirmDialog'
import { useTraefikAction, useTraefikLogs, useTraefikOverview } from '@/hooks/useServers'
import type { Server, TraefikRoute } from '@/types'

const ROUTE_STATE: Record<TraefikRoute['state'], { label: string; className: string }> = {
  active: { label: 'Active', className: 'bg-emerald-400/10 text-emerald-300' },
  proxy_disabled: { label: 'Proxy disabled', className: 'bg-white/5 text-white/45' },
  container_stopped: { label: 'Container stopped', className: 'bg-amber-400/10 text-amber-200' },
  certificate_pending: { label: 'Certificate pending', className: 'bg-amber-400/10 text-amber-200' },
  certificate_failed: { label: 'Certificate failed', className: 'bg-red-400/10 text-red-300' },
  unknown: { label: 'Unknown', className: 'bg-white/5 text-white/45' },
}

function formatDate(value?: string | null) {
  if (!value) return '—'
  const date = new Date(value)
  return Number.isFinite(date.getTime()) ? date.toLocaleString() : '—'
}

function setting(value: unknown) {
  if (value === true) return 'Enabled'
  if (value === false) return 'Disabled'
  if (value === null || value === undefined || value === '') return '—'
  return String(value)
}

function Row({ label, value }: { label: string; value: unknown }) {
  return (
    <div className="flex items-start justify-between gap-4 border-b border-white/5 py-2.5 last:border-0">
      <span className="text-xs text-white/40">{label}</span>
      <span className="max-w-[60%] break-all text-right font-mono text-[11px] text-white/70">{setting(value)}</span>
    </div>
  )
}

export default function TraefikPanel({ server }: { server: Server }) {
  const overview = useTraefikOverview(server.id)
  const action = useTraefikAction(server.id)
  const [logsOpen, setLogsOpen] = useState(false)
  const [logContainer, setLogContainer] = useState<string | undefined>(undefined)
  const [confirmAction, setConfirmAction] = useState<'stop' | 'restart' | null>(null)
  const logs = useTraefikLogs(server.id, logsOpen, logContainer)

  if (overview.isLoading) {
    return <div className="flex items-center justify-center gap-2 py-24 text-sm text-white/45"><Loader2 size={15} className="animate-spin" /> Reading proxy state…</div>
  }

  if (overview.error || !overview.data) {
    return (
      <div role="alert" className="flex flex-col items-center gap-3 py-24 text-center">
        <AlertTriangle size={24} className="text-amber-300/70" />
        <p className="text-sm text-white/60">{overview.error?.message || 'Could not read proxy state.'}</p>
        <Button size="sm" variant="secondary" onClick={() => void overview.refetch()}>Retry</Button>
      </div>
    )
  }

  const data = overview.data
  const proxyContainers = data.containers
  const managed = data.managed
  const selectedContainer = logContainer ?? proxyContainers.find((container) => container.running)?.name ?? proxyContainers[0]?.name

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <h2 className="text-[15px] font-medium text-white/90">Proxy</h2>
            <span className={`rounded-md px-2 py-0.5 text-[10px] ${managed ? 'bg-rail-purple/15 text-rail-purple-light' : 'bg-sky-400/10 text-sky-300'}`}>
              {managed ? 'RailDock managed' : 'External · read-only'}
            </span>
          </div>
          <p className="mt-1 text-xs text-white/40">Traefik routing, containers and certificate coverage for {server.name}.</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Button size="sm" variant="ghost" className="gap-1.5" onClick={() => void overview.refetch()} disabled={overview.isFetching}>
            <RefreshCw size={13} className={overview.isFetching ? 'animate-spin' : ''} /> Refresh
          </Button>
          <Button size="sm" variant="secondary" className="gap-1.5" onClick={() => setLogsOpen(true)} disabled={!proxyContainers.length && !managed}>
            <ScrollText size={13} /> Logs
          </Button>
          {managed ? (
            <>
              <Button size="sm" variant="secondary" className="gap-1.5" onClick={() => action.mutate({ operation: 'start' })} disabled={action.isPending}>
                <Play size={13} /> Start
              </Button>
              <Button size="sm" variant="secondary" className="gap-1.5" onClick={() => setConfirmAction('restart')} disabled={action.isPending}>
                <RotateCw size={13} /> Restart
              </Button>
              <Button size="sm" variant="ghost" className="gap-1.5 text-amber-200" onClick={() => setConfirmAction('stop')} disabled={action.isPending}>
                <Square size={12} /> Stop
              </Button>
            </>
          ) : (
            <Button size="sm" variant="secondary" className="gap-1.5" onClick={() => action.mutate({ operation: 'check' })} disabled={action.isPending}>
              <RefreshCw size={13} /> Check routing
            </Button>
          )}
        </div>
      </div>

      {(action.error || data.inventoryError) && (
        <div role="alert" className="rounded-lg border border-amber-300/20 bg-amber-300/5 px-4 py-3 text-xs text-amber-200">
          {action.error?.message || data.inventoryError}
        </div>
      )}

      {managed && data.routes.length === 0 && Object.keys(data.proxyTypes || {}).length > 0 && (
        <div className="rounded-lg border border-white/8 bg-white/[0.02] px-4 py-3 text-xs leading-5 text-white/45">
          No apps on this server are routed by Traefik. Managed proxy types:{' '}
          <span className="font-mono text-white/65">{Object.entries(data.proxyTypes || {}).map(([name, count]) => `${name} (${count})`).join(', ')}</span>.
          {!data.containers.length && ' The Traefik plugin is configured but its container is not running.'}
        </div>
      )}

      <div className="grid gap-3 sm:grid-cols-3">
        {[
          ['Proxy containers', `${data.summary.runningProxyContainers}/${data.summary.proxyContainers} running`, data.summary.runningProxyContainers > 0],
          ['Routes', data.summary.routesNeedingAttention ? `${data.summary.routesNeedingAttention} need attention` : `${data.summary.activeRoutes} active`, data.summary.routesNeedingAttention === 0],
          ['Certificates', data.summary.certificatesNeedingAttention ? `${data.summary.certificatesNeedingAttention} need attention` : `${data.summary.activeCertificates} active`, data.summary.certificatesNeedingAttention === 0],
        ].map(([label, value, healthy]) => (
          <div key={String(label)} className="rounded-xl border border-white/8 bg-[#141417] p-4">
            <p className="text-[11px] text-white/35">{label}</p>
            <p className={`mt-2 text-sm font-medium ${healthy ? 'text-white/80' : 'text-amber-200'}`}>{value}</p>
          </div>
        ))}
      </div>

      <section className="overflow-hidden rounded-xl border border-white/8 bg-[#111114]">
        <div className="border-b border-white/7 px-4 py-3"><h3 className="text-sm font-medium text-white/85">Traefik containers</h3></div>
        {proxyContainers.length === 0 ? (
          <p className="px-4 py-8 text-center text-xs text-white/40">No Traefik container was found on this host.</p>
        ) : (
          <div className="divide-y divide-white/5">
            {proxyContainers.map((container) => (
              <div key={container.id || container.name} className="flex flex-wrap items-center justify-between gap-3 px-4 py-3">
                <div className="min-w-0">
                  <p className="truncate font-mono text-xs text-white/75">{container.name || 'unnamed container'}</p>
                  <p className="mt-1 truncate text-[11px] text-white/35">{container.image}</p>
                </div>
                <div className="flex flex-wrap items-center gap-3 text-[11px] text-white/45">
                  {container.ports && <span className="max-w-64 truncate font-mono" title={container.ports}>{container.ports}</span>}
                  {container.networks && <span className="max-w-56 truncate" title={container.networks}>{container.networks}</span>}
                  <span className={`flex items-center gap-1.5 ${container.running ? 'text-emerald-300' : 'text-amber-200'}`}>
                    <span className={`size-1.5 rounded-full ${container.running ? 'bg-emerald-400' : 'bg-amber-400'}`} />
                    {container.running ? 'Running' : container.state || 'Stopped'}
                  </span>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      <div className="grid gap-5 lg:grid-cols-2">
        <section className="rounded-xl border border-white/8 bg-[#111114] p-4">
          <h3 className="text-sm font-medium text-white/85">Configuration</h3>
          <div className="mt-3">
            {managed ? (
              Object.keys(data.settings).length ? (
                <>
                  <Row label="Image" value={data.settings.image} />
                  <Row label="HTTP entrypoint" value={data.settings.httpEntrypoint ?? data.entrypoints.http} />
                  <Row label="HTTPS entrypoint" value={data.settings.httpsEntrypoint ?? data.entrypoints.https} />
                  <Row label="Certificate resolver" value={data.settings.certResolver ?? data.certResolver} />
                  <Row label="ACME challenge" value={data.settings.challengeMode} />
                  <Row label="Let's Encrypt email" value={data.settings.letsencryptEmail} />
                  <Row label="DNS provider" value={data.settings.dnsProvider} />
                  <Row label="Log level" value={data.settings.logLevel} />
                  <Row label="API" value={data.settings.apiEnabled} />
                  <Row label="Dashboard" value={data.settings.dashboardEnabled} />
                </>
              ) : <p className="text-xs leading-5 text-white/40">Dokku did not return a Traefik report for this host.</p>
            ) : (
              <>
                <Row label="Docker network" value={data.network} />
                <Row label="HTTP entrypoint" value={data.entrypoints.http} />
                <Row label="HTTPS entrypoint" value={data.entrypoints.https} />
                <Row label="Certificate resolver" value={data.certResolver} />
                <Row label="Redirect middleware" value={data.redirectMiddleware} />
                <Row label="Default labels" value={`${Object.keys(data.defaultLabels || {}).length} configured`} />
                <p className="mt-3 text-[11px] leading-5 text-white/35">RailDock applies labels to services but never starts, stops, or edits this Traefik.</p>
              </>
            )}
          </div>
        </section>

        <section className="rounded-xl border border-white/8 bg-[#111114] p-4">
          <h3 className="text-sm font-medium text-white/85">Recent routing warnings</h3>
          {data.warnings.length ? (
            <div className="mt-3 space-y-3">
              {data.warnings.map((warning) => (
                <div key={warning.id} className="rounded-lg border border-amber-300/15 bg-amber-300/5 p-3">
                  <p className="text-[11px] leading-5 text-amber-100/80">{warning.message}</p>
                  <p className="mt-1 text-[10px] text-white/30">{warning.serviceName || 'Proxy'} · {formatDate(warning.createdAt)}</p>
                </div>
              ))}
            </div>
          ) : (
            <p className="mt-3 text-xs text-white/40">No proxy routing warnings were recorded.</p>
          )}
        </section>
      </div>

      <section className="overflow-hidden rounded-xl border border-white/8 bg-[#111114]">
        <div className="flex items-center justify-between border-b border-white/7 px-4 py-3">
          <h3 className="text-sm font-medium text-white/85">Routes</h3>
          <span className="text-[11px] text-white/35">{data.routes.length} hostnames</span>
        </div>
        {data.routes.length === 0 ? (
          <p className="px-4 py-8 text-center text-xs text-white/40">No domains are routed through this proxy.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-[11px]">
              <thead className="bg-white/[0.02] text-white/35">
                <tr><th className="px-4 py-2 font-normal">Hostname</th><th className="px-3 py-2 font-normal">Service</th><th className="px-3 py-2 font-normal">Backend</th><th className="px-3 py-2 font-normal">Certificate</th><th className="px-4 py-2 font-normal">State</th></tr>
              </thead>
              <tbody className="divide-y divide-white/5">
                {data.routes.map((route) => (
                  <tr key={route.id} className="align-top">
                    <td className="px-4 py-3">
                      <p className="font-mono text-white/75">{route.hostname}</p>
                      <p className="mt-1 max-w-72 truncate font-mono text-[10px] text-white/30" title={route.rule}>{route.rule}</p>
                    </td>
                    <td className="px-3 py-3 text-white/60">{route.serviceName}<p className="mt-1 text-[10px] text-white/25">{route.projectName}</p></td>
                    <td className="px-3 py-3 font-mono text-[10px] text-white/45">{route.backend || `${route.container}:${route.targetPort}`}{!route.running && route.running !== null && <span className="mt-1 block text-amber-200/70">container not running</span>}</td>
                    <td className="px-3 py-3 text-white/50">{route.ssl ? (route.sslStatus || 'unknown') : 'HTTP only'}{route.sslExpiresAt && <p className="mt-1 text-[10px] text-white/25">expires {formatDate(route.sslExpiresAt)}</p>}</td>
                    <td className="px-4 py-3"><span className={`inline-flex rounded px-2 py-0.5 text-[10px] ${ROUTE_STATE[route.state].className}`}>{ROUTE_STATE[route.state].label}</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="overflow-hidden rounded-xl border border-white/8 bg-[#111114]">
        <div className="flex items-center justify-between border-b border-white/7 px-4 py-3">
          <h3 className="text-sm font-medium text-white/85">Certificates</h3>
          <span className="text-[11px] text-white/35">{data.certificates.length} managed hostnames</span>
        </div>
        {data.certificates.length === 0 ? (
          <p className="px-4 py-8 text-center text-xs text-white/40">No SSL-enabled hostnames are configured.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-[11px]">
              <thead className="bg-white/[0.02] text-white/35"><tr><th className="px-4 py-2 font-normal">Hostname</th><th className="px-3 py-2 font-normal">Service</th><th className="px-3 py-2 font-normal">Status</th><th className="px-3 py-2 font-normal">Expires</th><th className="px-4 py-2 font-normal">Detail</th></tr></thead>
              <tbody className="divide-y divide-white/5">
                {data.certificates.map((certificate) => (
                  <tr key={certificate.id}>
                    <td className="px-4 py-3 font-mono text-white/75">{certificate.hostname}</td>
                    <td className="px-3 py-3 text-white/55">{certificate.serviceName}</td>
                    <td className="px-3 py-3"><span className={`inline-flex items-center gap-1.5 ${certificate.status === 'active' ? 'text-emerald-300' : certificate.status === 'failed' ? 'text-red-300' : 'text-amber-200'}`}>{certificate.status === 'active' ? <CheckCircle2 size={12} /> : certificate.status === 'failed' ? <AlertTriangle size={12} /> : <CircleSlash size={12} />}{certificate.status || 'unknown'}</span></td>
                    <td className="px-3 py-3 text-white/45">{formatDate(certificate.expiresAt)}</td>
                    <td className="max-w-80 px-4 py-3 text-[10px] leading-4 text-white/35">{certificate.statusMessage || (certificate.wildcard ? 'Wildcard certificate' : certificate.challengeType === 'dns' ? 'DNS challenge' : 'HTTP challenge')}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <ConfirmDialog
        open={confirmAction !== null}
        onOpenChange={(open) => { if (!open) setConfirmAction(null) }}
        title={confirmAction === 'restart' ? 'Restart managed Traefik?' : 'Stop managed Traefik?'}
        description={confirmAction === 'restart' ? 'RailDock will stop and then start Dokku\'s managed Traefik. Every app behind it will be unreachable during the restart.' : 'Every public app behind this Traefik will be unreachable until someone starts it again.'}
        warning="This proxy may front unrelated applications. Confirm the server and check the host before interrupting traffic."
        confirmWord={server.name}
        confirmLabel={confirmAction === 'restart' ? 'Restart Traefik' : 'Stop Traefik'}
        destructive
        pending={action.isPending}
        error={action.error?.message}
        onConfirm={async () => {
          if (!confirmAction) return
          await action.mutateAsync({ operation: confirmAction, confirmation: server.name })
          setConfirmAction(null)
        }}
      />

      <Dialog open={logsOpen} onOpenChange={setLogsOpen}>
        <DialogContent className="border-white/9 bg-[#19191d] text-white sm:max-w-5xl">
          <DialogHeader>
            <DialogTitle className="text-[14px]">Traefik logs</DialogTitle>
            <DialogDescription className="text-[11px] text-white/40">A redacted, bounded tail. Logs are not stored by RailDock.</DialogDescription>
          </DialogHeader>
          <div className="flex flex-wrap items-center justify-between gap-2">
            {!managed && proxyContainers.length > 1 ? (
              <select value={selectedContainer ?? ''} onChange={(event) => setLogContainer(event.target.value || undefined)} className="h-8 rounded-md border border-white/10 bg-black/25 px-2 text-xs text-white/70">
                {proxyContainers.map((container) => <option key={container.id || container.name} value={container.name ?? ''}>{container.name}</option>)}
              </select>
            ) : <span className="text-[11px] text-white/35">{selectedContainer || 'Managed Dokku proxy'}</span>}
            <Button size="sm" variant="ghost" className="gap-1.5" onClick={() => void logs.refetch()} disabled={logs.isFetching}>
              <RefreshCw size={12} className={logs.isFetching ? 'animate-spin' : ''} /> Refresh
            </Button>
          </div>
          {logs.isPending ? (
            <div className="flex items-center justify-center gap-2 py-16 text-xs text-white/45"><Loader2 size={14} className="animate-spin" /> Reading logs…</div>
          ) : logs.error ? (
            <p role="alert" className="py-10 text-center text-xs text-red-300">{logs.error.message}</p>
          ) : (
            <pre className="max-h-[55vh] overflow-auto whitespace-pre-wrap break-words rounded-lg border border-white/8 bg-black/30 p-4 font-mono text-[11px] leading-5 text-white/65">{logs.data?.output || 'No log output.'}</pre>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}
