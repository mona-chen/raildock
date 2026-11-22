import { Server, Plus, Search } from 'lucide-react'
import { useState } from 'react'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from '@/components/ui/dropdown-menu'
import { toast } from 'sonner'
import type { Server as ServerRecord } from '@/types'
import ServerOverview from '@/features/servers/ServerOverview'
import { useServers, useDestroyServer, useValidateServer, useUpdateServer } from '@/hooks/useServers'
import { useNetworks, useValidateNetwork } from '@/hooks/useModules'
import ServerSetupWizard from '@/features/servers/ServerSetupWizard'
import ServerDockerImportModal from '@/features/servers/ServerDockerImportModal'
import ServerUnmanagedDatastoresModal from '@/features/servers/ServerUnmanagedDatastoresModal'
import { useAuthStore } from '@/stores/useAuthStore'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Skeleton, SkeletonCard } from '@/components/ui/skeleton'
import ErrorState from '@/features/shared/ErrorState'
import EmptyState from '@/features/shared/EmptyState'
import WorkspaceHeader from '@/features/shared/WorkspaceHeader'
import HttpTrafficPanel from '@/features/servers/HttpTrafficPanel'
import NetworkFlowSettings from '@/features/servers/NetworkFlowSettings'
import HostMetricsPanel from '@/features/servers/HostMetricsPanel'
import ConfirmDialog from '@/features/shared/ConfirmDialog'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'

export default function ServerPage() {
  const { data: servers = [], isLoading, isError, refetch } = useServers()
  const destroyServer = useDestroyServer()
  const validateServer = useValidateServer()
  const updateServer = useUpdateServer()
  const validateNetwork = useValidateNetwork()
  const organization = useAuthStore((s) => s.currentOrganization())
  const canCreateServer = organization?.role === 'owner'

  const { serverId } = useParams()
  const navigate = useNavigate()
  const [params,setParams] = useSearchParams()
  const selectedServer = servers.find(server => server.id === serverId)
  const metricsMode = params.get('tab') === 'http' ? 'http' : params.get('tab') === 'flows' ? 'flows' : 'resources'
  const [search, setSearch] = useState('')
  const filteredServers = servers.filter((server) => `${server.name} ${server.host}`.toLowerCase().includes(search.trim().toLowerCase()))
  const [showAdd, setShowAdd] = useState(false)
  const [settingsServer, setSettingsServer] = useState<ServerRecord | null>(null)
  const [importServer, setImportServer] = useState<ServerRecord | null>(null)
  const [adoptServer, setAdoptServer] = useState<ServerRecord | null>(null)
  const [removeTarget, setRemoveTarget] = useState<ServerRecord | null>(null)
  const [proxyMode, setProxyMode] = useState<'managed' | 'external'>('managed')
  const [proxyNetwork, setProxyNetwork] = useState('')
  const [httpEntrypoint, setHttpEntrypoint] = useState('web')
  const [httpsEntrypoint, setHttpsEntrypoint] = useState('websecure')
  const [certResolver, setCertResolver] = useState('')
  const [redirectMiddleware, setRedirectMiddleware] = useState('')
  const [defaultLabels, setDefaultLabels] = useState('{}')
  const { data: networks = [], isLoading: networksLoading } = useNetworks(settingsServer?.id)
  const validatingIds = validateServer.pendingIds ?? []
  const removeProjectCount = removeTarget?.projectIds?.length ?? 0

  const openRemove = (server: ServerRecord) => {
    destroyServer.reset?.()
    setRemoveTarget(server)
  }

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

      <WorkspaceHeader title={serverId ? selectedServer?.name || 'Server' : 'Servers'} description={serverId ? selectedServer?.host || 'Host observability' : 'Manage the hosts your services run on.'}>
        {canCreateServer && !serverId && (
          <button
            onClick={() => setShowAdd(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 btn-primary"
          >
            <Plus size={14} /> Connect server
          </button>
        )}
      </WorkspaceHeader>

      <div className="flex-1 overflow-y-auto p-6">
        <div className={`mx-auto ${serverId?'max-w-7xl':'max-w-5xl'} space-y-5`}>
          {serverId ? <><div className="flex items-center justify-between"><Link to="/dashboard/servers" className="text-xs text-[#a0a0b0] hover:text-white">Servers / {selectedServer?.name || 'Server'}</Link>{selectedServer&&<DropdownMenu><DropdownMenuTrigger asChild><Button size="sm" variant="ghost" className="text-xs text-[#9292a3]">Server actions</Button></DropdownMenuTrigger><DropdownMenuContent align="end" className="border-white/10 bg-[#1a1a20] text-white"><DropdownMenuItem onSelect={()=>openSettings(selectedServer)}>Proxy settings</DropdownMenuItem><DropdownMenuItem onSelect={()=>validateServer.mutate(selectedServer.id)} disabled={validatingIds.includes(selectedServer.id)}>{validatingIds.includes(selectedServer.id)?'Checking connection…':'Check connection'}</DropdownMenuItem><DropdownMenuItem onSelect={()=>setImportServer(selectedServer)}>Import containers</DropdownMenuItem><DropdownMenuItem onSelect={()=>setAdoptServer(selectedServer)}>Adopt datastores</DropdownMenuItem>{canCreateServer&&<><DropdownMenuSeparator/><DropdownMenuItem onSelect={()=>openRemove(selectedServer)} className="text-red-300">Remove server…</DropdownMenuItem></>}</DropdownMenuContent></DropdownMenu>}</div>{selectedServer?<><nav className="flex gap-6 border-b border-white/10" aria-label="Server sections">{(['resources','http','flows'] as const).map(mode=><button key={mode} onClick={()=>setParams({tab:mode})} aria-current={metricsMode===mode?'page':undefined} className={`pb-3 text-sm border-b-2 ${metricsMode===mode?'text-[#c4b5fd] border-rail-purple-light':'text-[#9292a3] border-transparent'}`}>{mode==='resources'?'Resources':mode==='http'?'HTTP traffic':'Service connections'}</button>)}</nav>{metricsMode==='resources'?<HostMetricsPanel key={selectedServer.id} serverId={selectedServer.id}/>:metricsMode==='flows'?<NetworkFlowSettings key={selectedServer.id} serverId={selectedServer.id}/>:<HttpTrafficPanel key={selectedServer.id} serverId={selectedServer.id}/>}</>:isLoading?<p role="status">Loading server…</p>:<ErrorState title="Server unavailable" message="The server could not be loaded or you no longer have access." onRetry={()=>refetch()}/>}</> : <>

          {servers.length > 0 && <div className="flex flex-wrap items-center justify-between gap-4"><div className="flex items-center gap-3 text-xs text-[#a0a0b0]"><span className="h-2 w-2 rounded-full bg-emerald-400" />{servers.filter((server) => server.status === 'connected').length} of {servers.length} connected</div><label className="flex items-center gap-2 rounded-lg border border-white/10 bg-white/2.5 px-3 py-2"><Search size={14} className="text-[#a0a0b0]" /><input aria-label="Search servers" placeholder="Find a server…" value={search} onChange={(event) => setSearch(event.target.value)} className="w-44 bg-transparent text-xs outline-hidden" /></label></div>}
          {isLoading ? (
            Array.from({ length: 2 }).map((_, i) => (
              <div key={i} className="rounded-xl border border-white/5 bg-white/2 p-5 space-y-4">
                <div className="flex items-start justify-between">
                  <div className="flex items-center gap-3">
                    <Skeleton className="size-10 rounded-xl" />
                    <div className="space-y-2">
                      <Skeleton className="h-3.5 w-32" />
                      <Skeleton className="h-3 w-24" />
                    </div>
                  </div>
                  <Skeleton className="h-5 w-20 rounded" />
                </div>
                <div className="grid grid-cols-4 gap-3">
                  {Array.from({ length: 4 }).map((_, j) => (
                    <Skeleton key={j} className="h-16 rounded-lg" />
                  ))}
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <Skeleton className="h-20 rounded-lg" />
                  <Skeleton className="h-20 rounded-lg" />
                </div>
              </div>
            ))
          ) : isError ? (
            <ErrorState
              title="Couldn't load servers"
              message="RailDock could not reach the API to list your Dokku hosts. Retry to load them."
              onRetry={() => refetch()}
            />
          ) : (
            filteredServers.map((srv) => <ServerOverview key={srv.id} server={srv}
              onResources={() => navigate(`/dashboard/servers/${srv.id}?tab=resources`)}
              onHttp={() => navigate(`/dashboard/servers/${srv.id}?tab=http`)}
              onSettings={() => openSettings(srv)} onImport={() => setImportServer(srv)} onAdopt={() => setAdoptServer(srv)} onRemove={() => openRemove(srv)}
              onValidate={() => validateServer.mutate(srv.id)} validating={validatingIds.includes(srv.id)} canRemove={canCreateServer} />)

          )}

          {servers.length > 0 && filteredServers.length === 0 && <EmptyState icon={Search} title="No matching servers" description="Try a server name or host address." action={<button type="button" onClick={() => setSearch('')} className="btn-secondary">Clear search</button>} />}
          {servers.length === 0 && !isLoading && !isError && (
            <EmptyState
              icon={Server}
              title="No servers connected"
              description="Connect a Dokku host over SSH and RailDock will run its builds and deployments there."
              action={
                canCreateServer ? (
                  <button
                    onClick={() => setShowAdd(true)}
                    className="inline-flex items-center gap-1.5 rounded-lg bg-rail-purple px-3 py-2 text-[13px] font-medium text-white hover:bg-rail-purple-dark transition-colors"
                  >
                    <Plus size={14} /> Connect a server
                  </button>
                ) : undefined
              }
              hint={canCreateServer ? undefined : 'Only organization owners can connect servers.'}
            />
          )}
          </>}
        </div>
      </div>

      {showAdd && <ServerSetupWizard isOpen={showAdd} onClose={() => setShowAdd(false)} />}

      <ConfirmDialog
        open={removeTarget !== null}
        onOpenChange={(open) => !open && setRemoveTarget(null)}
        title="Remove server?"
        description={
          <>
            RailDock will stop managing{' '}
            <span className="font-medium text-white">{removeTarget?.name}</span>. Apps and
            datastores already running on the host are left untouched, but you will lose the
            ability to deploy or back them up from here.
          </>
        }
        warning={
          removeProjectCount > 0 ? (
            <>
              {removeProjectCount} {removeProjectCount === 1 ? 'project still runs' : 'projects still run'} on this
              server. RailDock will not remove a server that projects depend on — move or delete them first.
            </>
          ) : undefined
        }
        error={destroyServer.error?.message ?? null}
        confirmLabel="Remove server"
        destructive
        confirmWord={removeTarget?.name}
        confirmWordLabel={
          <>
            Type <span className="font-mono font-medium text-white">{removeTarget?.name}</span> to confirm
          </>
        }
        pending={destroyServer.isPending}
        onConfirm={async () => {
          if (!removeTarget) return
          try {
            const removedId = removeTarget.id
            await destroyServer.mutateAsync(removedId)
            setRemoveTarget(null)
            if (serverId === removedId) navigate('/dashboard/servers')
          } catch {
            /* error toast is surfaced by the mutation hook */
          }
        }}
      />

      {importServer && (
        <ServerDockerImportModal
          serverId={importServer.id}
          serverName={importServer.name}
          onClose={() => setImportServer(null)}
        />
      )}

      {adoptServer && (
        <ServerUnmanagedDatastoresModal
          serverId={adoptServer.id}
          serverName={adoptServer.name}
          onClose={() => setAdoptServer(null)}
        />
      )}

      <Dialog open={settingsServer !== null} onOpenChange={(open) => { if (!open) setSettingsServer(null) }}>
        {settingsServer && (
          <DialogContent className="sm:max-w-[560px] max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle>Proxy settings</DialogTitle>
              <DialogDescription>{settingsServer.name}</DialogDescription>
            </DialogHeader>

            <div className="space-y-4">
              <div>
                <label htmlFor="proxy-mode" className="text-[11px] text-[#8a8a99] block mb-1.5">Proxy Mode</label>
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

              {proxyMode === 'external' && (
                <>
                  <div>
                    <div className="flex items-center justify-between mb-1.5">
                      <label htmlFor="proxy-network" className="text-[11px] text-[#8a8a99]">Traefik Docker Network</label>
                      <button
                        type="button"
                        disabled={!proxyNetwork || validateNetwork.isPending}
                        onClick={() => validateNetwork.mutate({ serverId: settingsServer.id, network: proxyNetwork })}
                        className="text-[10px] text-rail-purple disabled:opacity-40"
                      >
                        {validateNetwork.isPending ? 'Checking...' : 'Verify network'}
                      </button>
                    </div>
                    <Select value={proxyNetwork} onValueChange={setProxyNetwork}>
                      <SelectTrigger id="proxy-network">
                        <SelectValue placeholder={networksLoading ? 'Discovering networks...' : 'Select a network'} />
                      </SelectTrigger>
                      <SelectContent>
                          {networks.filter((network) => network.selectable).map((network) => (
                          <SelectItem key={network.name} value={network.name}>
                            {network.name}{network.recommended ? ' (Traefik detected)' : ''}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>

                  <div className="grid grid-cols-2 gap-3">
                    <ProxyInput id="http-entrypoint" label="HTTP entrypoint" value={httpEntrypoint} onChange={setHttpEntrypoint} />
                    <ProxyInput id="https-entrypoint" label="HTTPS entrypoint" value={httpsEntrypoint} onChange={setHttpsEntrypoint} />
                    <ProxyInput id="cert-resolver" label="Certificate resolver" value={certResolver} onChange={setCertResolver} placeholder="letsencrypt" />
                    <ProxyInput id="redirect-middleware" label="Redirect middleware" value={redirectMiddleware} onChange={setRedirectMiddleware} placeholder="redirect-to-https" />
                  </div>

                  <div>
                    <label htmlFor="default-labels" className="text-[11px] text-[#8a8a99] block mb-1.5">Default Traefik labels (JSON)</label>
                    <textarea id="default-labels" value={defaultLabels} onChange={(event) => setDefaultLabels(event.target.value)} rows={5} className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-white/10 rounded-lg text-xs text-white font-mono" />
                  </div>

                  <p className="text-[10px] text-[#8a8a99]">
                    RailDock will not start, stop, or reconfigure the existing Traefik container. Services attach to this network when redeployed.
                  </p>
                </>
              )}
            </div>

            <DialogFooter>
              <Button variant="ghost" onClick={() => setSettingsServer(null)}>Cancel</Button>
              <Button onClick={saveSettings} disabled={updateServer.isPending || (proxyMode === 'external' && !proxyNetwork)}>
                {updateServer.isPending ? 'Saving…' : 'Save settings'}
              </Button>
            </DialogFooter>
          </DialogContent>
        )}
      </Dialog>
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
      <label htmlFor={id} className="text-[11px] text-[#8a8a99] block mb-1.5">{label}</label>
      <input id={id} value={value} onChange={(event) => onChange(event.target.value)} placeholder={placeholder} className="w-full px-3 py-2.5 bg-[#0B0B0D] border border-white/10 rounded-lg text-sm text-white" />
    </div>
  )
}
