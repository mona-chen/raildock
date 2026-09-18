import { useState } from 'react'
import { AlertTriangle, Database, Loader2, RefreshCw, X } from 'lucide-react'
import { useUnmanagedDatastores, useAdoptDatastore } from '@/hooks/useServers'
import { useProjects } from '@/hooks/useProjects'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'

interface ServerUnmanagedDatastoresModalProps {
  serverId: string
  serverName: string
  onClose: () => void
}

export default function ServerUnmanagedDatastoresModal({
  serverId,
  serverName,
  onClose,
}: ServerUnmanagedDatastoresModalProps) {
  const { data, isLoading, isError, error, refetch, isFetching } = useUnmanagedDatastores(serverId)
  const { data: projects = [] } = useProjects()
  const adopt = useAdoptDatastore(serverId)

  const [adopting, setAdopting] = useState<string | null>(null)
  const [projectId, setProjectId] = useState('')

  const resources = data?.resources ?? []
  const scanErrors = data?.errors ?? []
  const serverProjects = projects.filter((project) => project.serverId === serverId)

  const startAdopting = (name: string) => {
    setAdopting(name)
    setProjectId(serverProjects[0]?.id ?? '')
  }

  const confirmAdopt = () => {
    if (!adopting || !projectId) return
    adopt.mutate({ resourceName: adopting, projectId }, { onSuccess: () => setAdopting(null) })
  }

  return (
    <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-center justify-center px-4" onClick={onClose}>
      <div
        className="bg-[#18181B] border border-[rgba(255,255,255,0.08)] rounded-2xl p-6 w-full max-w-[640px] max-h-[85vh] flex flex-col"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="flex items-start justify-between mb-4">
          <div>
            <h3 className="text-base font-semibold text-white">Untracked datastores</h3>
            <p className="text-[11px] text-[#8a8a99] mt-0.5">{serverName}</p>
          </div>
          <div className="flex items-center gap-1">
            <button
              onClick={() => refetch()}
              disabled={isFetching}
              className="p-1.5 rounded text-white/50 hover:text-white hover:bg-white/[0.05] disabled:opacity-40"
              title="Rescan the host"
              aria-label="Rescan the host"
            >
              <RefreshCw size={14} className={isFetching ? 'animate-spin' : undefined} />
            </button>
            <button
              onClick={onClose}
              className="p-1.5 rounded text-white/50 hover:text-white hover:bg-white/[0.05]"
              aria-label="Close"
            >
              <X size={14} />
            </button>
          </div>
        </div>

        <p className="text-[11px] leading-5 text-[#8A8A99] mb-4">
          Datastores running on this host that RailDock has no service record for. They are invisible to the
          dashboard, so nothing backs them up. Adopting one records what is already there — nothing is created,
          renamed, restarted, or deleted on the host.
        </p>

        {scanErrors.length > 0 && (
          <div className="mb-4 rounded-lg border border-amber-500/20 bg-amber-500/10 p-2.5">
            {scanErrors.map((scanError) => (
              <div key={scanError} className="flex items-start gap-2 text-[11px] text-amber-200">
                <AlertTriangle size={12} className="mt-0.5 shrink-0" />
                <span className="font-mono">{scanError}</span>
              </div>
            ))}
          </div>
        )}

        <div className="flex-1 overflow-y-auto">
          {isLoading && (
            <div className="flex items-center gap-2 py-8 justify-center text-[12px] text-[#8a8a99]">
              <Loader2 size={14} className="animate-spin" /> Scanning the host…
            </div>
          )}

          {isError && (
            <div className="py-8 text-center text-[12px] text-red-300">
              Scan failed: {error?.message}
            </div>
          )}

          {!isLoading && !isError && resources.length === 0 && (
            <div className="py-10 text-center">
              <Database size={32} className="mx-auto mb-3 opacity-30 text-white" />
              <p className="text-[12px] text-[#8a8a99]">
                Every datastore on this host is tracked by RailDock.
              </p>
            </div>
          )}

          <div className="space-y-2">
            {resources.map((resource) => (
              <div key={resource.name} className="rounded-xl border border-white/[0.07] bg-white/[0.02] p-3">
                <div className="flex items-center justify-between gap-3">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <span
                        className={`h-1.5 w-1.5 shrink-0 rounded-full ${
                          resource.status === 'running' ? 'bg-emerald-400' : 'bg-white/25'
                        }`}
                      />
                      <span className="truncate font-mono text-[12px] text-white">{resource.name}</span>
                      <span className="shrink-0 rounded-full bg-white/[0.06] px-2 py-0.5 text-[10px] uppercase tracking-wide text-white/50">
                        {resource.subtype}
                      </span>
                    </div>
                    <div className="mt-1 text-[10px] text-[#8a8a99]">
                      {resource.status}
                      {resource.linkedApps.length > 0 && (
                        <> · linked to <span className="font-mono">{resource.linkedApps.join(', ')}</span></>
                      )}
                    </div>
                  </div>

                  {adopting === resource.name ? (
                    <div className="flex shrink-0 items-center gap-2">
                      <button
                        onClick={() => setAdopting(null)}
                        className="rounded-md px-2.5 py-1 text-[11px] text-white/50 hover:bg-white/[0.05]"
                      >
                        Cancel
                      </button>
                    </div>
                  ) : (
                    <button
                      onClick={() => startAdopting(resource.name)}
                      className="shrink-0 rounded-md bg-rail-purple/15 px-3 py-1.5 text-[11px] text-rail-purple hover:bg-rail-purple/25"
                    >
                      Adopt
                    </button>
                  )}
                </div>

                {adopting === resource.name && (
                  <div className="mt-3 border-t border-white/[0.06] pt-3">
                    {serverProjects.length === 0 ? (
                      <p className="text-[11px] text-amber-200">
                        This server has no projects yet — create one before adopting.
                      </p>
                    ) : (
                      <div className="flex items-center gap-2">
                        <Select value={projectId} onValueChange={setProjectId}>
                          <SelectTrigger className="h-8 flex-1 text-[11px]" aria-label="Target project">
                            <SelectValue placeholder="Choose a project" />
                          </SelectTrigger>
                          <SelectContent>
                            {serverProjects.map((project) => (
                              <SelectItem key={project.id} value={project.id}>
                                {project.name}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                        <button
                          onClick={confirmAdopt}
                          disabled={!projectId || adopt.isPending}
                          className="rounded-md bg-rail-purple px-3 py-1.5 text-[11px] font-medium text-white hover:bg-rail-purple-dark disabled:opacity-40"
                        >
                          {adopt.isPending ? 'Adopting…' : 'Confirm adoption'}
                        </button>
                      </div>
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}
