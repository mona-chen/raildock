import { useEffect, useState } from 'react'
import { Box, Container, HardDrive, Loader2, Network, RefreshCw, X } from 'lucide-react'
import { toast } from 'sonner'
import { useServerDockerContainers, useImportDockerContainers } from '@/hooks/useServers'
import type { DockerContainer } from '@/types'

interface ServerDockerImportModalProps {
  serverId: string
  serverName: string
  onClose: () => void
}

export default function ServerDockerImportModal({ serverId, serverName, onClose }: ServerDockerImportModalProps) {
  const { data: containers = [], isLoading, isError, error, refetch } = useServerDockerContainers(serverId)
  const importContainers = useImportDockerContainers(serverId)
  const [selected, setSelected] = useState<Set<string>>(new Set())

  useEffect(() => {
    if (isError && error) {
      toast.error(`Scan failed: ${error.message}`)
    }
  }, [isError, error])

  const toggle = (id: string) => {
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  const toggleAll = () => {
    if (selected.size === containers.length) {
      setSelected(new Set())
    } else {
      setSelected(new Set(containers.map((c) => c.id)))
    }
  }

  const handleImport = () => {
    const toImport = containers.filter((c) => selected.has(c.id))
    if (toImport.length === 0) {
      toast.error('Select at least one container')
      return
    }
    importContainers.mutate({ containers: toImport }, { onSuccess: () => onClose() })
  }

  return (
    <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-center justify-center px-4" onClick={onClose}>
      <div
        className="bg-[#18181B] border border-[rgba(255,255,255,0.08)] rounded-2xl p-6 w-full max-w-[640px] max-h-[85vh] flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between mb-4">
          <div>
            <h3 className="text-base font-semibold text-white">Import Docker Containers</h3>
            <p className="text-[11px] text-[#6B6B7B]">{serverName}</p>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-lg text-white/40 hover:text-white hover:bg-white/[0.05]">
            <X size={16} />
          </button>
        </div>

        <p className="text-[11px] text-[#6B6B7B] mb-4">
          Select existing Docker containers to import as RailDock services. The container image, environment variables,
          published ports, and bind mounts are preserved. A deployment is queued automatically for each imported app.
        </p>

        <div className="flex items-center justify-between mb-3">
          <label className="flex items-center gap-2 text-[11px] text-[#A0A0B0] cursor-pointer">
            <input
              type="checkbox"
              checked={containers.length > 0 && selected.size === containers.length}
              onChange={toggleAll}
              className="w-3.5 h-3.5 rounded border-[rgba(255,255,255,0.15)] bg-[#0B0B0D] text-rail-purple focus:ring-rail-purple"
            />
            Select all
          </label>
          <button
            onClick={() => refetch()}
            disabled={isLoading}
            className="flex items-center gap-1.5 text-[11px] text-rail-purple hover:text-rail-purple-light disabled:opacity-50"
          >
            <RefreshCw size={12} className={isLoading ? 'animate-spin' : ''} /> Refresh
          </button>
        </div>

        <div className="flex-1 overflow-y-auto min-h-[200px] space-y-2 pr-1">
          {isLoading ? (
            <div className="flex items-center justify-center h-32 text-[11px] text-[#6B6B7B]">
              <Loader2 size={14} className="animate-spin mr-2" /> Scanning containers...
            </div>
          ) : containers.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-32 text-[#6B6B7B]">
              <Container size={24} className="mb-2 opacity-30" />
              <p className="text-[11px]">No running containers found</p>
            </div>
          ) : (
            containers.map((container) => (
              <ContainerRow key={container.id} container={container} selected={selected.has(container.id)} onToggle={() => toggle(container.id)} />
            ))
          )}
        </div>

        <div className="flex items-center justify-between mt-5 pt-4 border-t border-[rgba(255,255,255,0.06)]">
          <span className="text-[11px] text-[#6B6B7B]">{selected.size} selected</span>
          <div className="flex gap-2">
            <button
              onClick={onClose}
              className="px-4 py-2 border border-[rgba(255,255,255,0.08)] text-[#A0A0B0] text-xs rounded-lg hover:bg-[rgba(255,255,255,0.04)]"
            >
              Cancel
            </button>
            <button
              onClick={handleImport}
              disabled={selected.size === 0 || importContainers.isPending}
              className="px-4 py-2 bg-rail-purple text-white text-xs font-medium rounded-lg hover:bg-rail-purple-dark disabled:opacity-50 flex items-center gap-2"
            >
              {importContainers.isPending && <Loader2 size={12} className="animate-spin" />}
              Import {selected.size > 0 ? `(${selected.size})` : ''}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}

function ContainerRow({
  container,
  selected,
  onToggle,
}: {
  container: DockerContainer
  selected: boolean
  onToggle: () => void
}) {
  const publishedPorts = container.ports.filter((p) => p.hostPort)
  const portText = publishedPorts.map((p) => `${p.hostPort}:${p.containerPort}`).join(', ') || container.ports.map((p) => p.containerPort).join(', ') || '-'
  const bindMounts = container.mounts.filter((m) => m.type === 'bind')

  return (
    <div
      onClick={onToggle}
      className={`p-3 rounded-xl border cursor-pointer transition-all ${
        selected
          ? 'bg-rail-purple/10 border-rail-purple/40'
          : 'bg-[rgba(255,255,255,0.02)] border-[rgba(255,255,255,0.05)] hover:border-[rgba(255,255,255,0.12)]'
      }`}
    >
      <div className="flex items-start gap-3">
        <input
          type="checkbox"
          checked={selected}
          onChange={onToggle}
          onClick={(e) => e.stopPropagation()}
          className="mt-0.5 w-3.5 h-3.5 rounded border-[rgba(255,255,255,0.15)] bg-[#0B0B0D] text-rail-purple focus:ring-rail-purple"
        />
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <span className="text-sm font-medium text-white truncate">{container.name}</span>
            <span className={`text-[9px] px-1.5 py-0.5 rounded-full ${container.running ? 'bg-rail-green/10 text-rail-green' : 'bg-rail-red/10 text-rail-red'}`}>
              {container.status}
            </span>
            {container.serviceType === 'database' && (
              <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-rail-blue/10 text-rail-blue">{container.subtype}</span>
            )}
          </div>
          <div className="text-[10px] text-[#6B6B7B] truncate mb-2">{container.image}</div>
          <div className="flex flex-wrap gap-3 text-[10px] text-[#A0A0B0]">
            {container.ports.length > 0 && (
              <span className="flex items-center gap-1">
                <Network size={10} /> {portText}
              </span>
            )}
            {bindMounts.length > 0 && (
              <span className="flex items-center gap-1" title={bindMounts.map((m) => `${m.source} → ${m.destination}`).join('\n')}>
                <HardDrive size={10} /> {bindMounts.length} mount{bindMounts.length === 1 ? '' : 's'}
              </span>
            )}
            {Object.keys(container.env).length > 0 && (
              <span className="flex items-center gap-1">
                <Box size={10} /> {Object.keys(container.env).length} env vars
              </span>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
