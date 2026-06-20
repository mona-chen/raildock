import { useState } from 'react'
import { Box, X, Play, Square, RotateCw, Rocket, Wrench } from 'lucide-react'
import { ServiceIcon, getServiceColor } from '@/components/icons/ServiceIcons'
import {
  useService,
  useDeployService,
  useStartService,
  useStopService,
  useRestartService,
  useRebuildService,
} from '@/hooks/useServices'
import LogsTab from '@/features/service-panel/tabs/LogsTab'
import InteractiveTerminal from '@/features/service-panel/tabs/InteractiveTerminal'
import { SettingsPanel } from '@/features/service-settings/SettingsPanel'
import OverviewTab from '@/features/service-panel/tabs/OverviewTab'
import DeployTab from '@/features/service-panel/tabs/DeployTab'
import DatabaseTab from '@/features/service-panel/tabs/DatabaseTab'
import BackupsTab from '@/features/service-panel/tabs/BackupsTab'
import VariablesTab from '@/features/service-panel/tabs/VariablesTab'
import MetricsTab from '@/features/service-panel/tabs/MetricsTab'
import DomainsTab from '@/features/service-panel/tabs/DomainsTab'
import StorageTab from '@/features/service-panel/tabs/StorageTab'
import { useWebSocketDeployments } from '@/hooks/useWebSocketDeployments'
import { realtimeStateLabel } from '@/hooks/useRealtimeState'

interface ServicePanelProps {
  serviceId: string
  onClose: () => void
}

export default function ServicePanel({ serviceId, onClose }: ServicePanelProps) {
  const { data: svc, isLoading, isError, error, refetch } = useService(serviceId)
  const [tab, setTab] = useState('overview')
  const deployService = useDeployService()
  const startService = useStartService()
  const stopService = useStopService()
  const restartService = useRestartService()
  const rebuildService = useRebuildService()
  const deploymentRealtime = useWebSocketDeployments(serviceId)

  const handleDeploy = () => {
    setTab('deploy')
    deployService.mutate(serviceId)
  }

  if (isLoading) {
    return (
      <div
        data-service-panel
        className="absolute right-0 top-0 bottom-0 w-full max-w-[800px] bg-[#131318] border-l border-white/[0.06] flex flex-col z-50 shadow-2xl shadow-black/40"
      >
        <div className="flex items-center justify-between px-5 py-3 border-b border-white/[0.06] flex-shrink-0">
          <div className="flex items-center gap-3">
            <button
              onClick={onClose}
              className="w-7 h-7 rounded-lg bg-white/[0.06] flex items-center justify-center hover:bg-white/[0.1]"
              aria-label="Close panel"
              type="button"
            >
              <X size={15} className="text-white/60" />
            </button>
            <div className="w-32 h-4 bg-white/[0.04] rounded animate-pulse" />
          </div>
        </div>
        <div className="flex-1 p-5 space-y-4">
          <div className="h-24 bg-white/[0.02] rounded-xl animate-pulse" />
          <div className="h-32 bg-white/[0.02] rounded-xl animate-pulse" />
          <div className="h-48 bg-white/[0.02] rounded-xl animate-pulse" />
        </div>
      </div>
    )
  }

  if (isError || !svc) {
    return (
      <div
        data-service-panel
        className="absolute right-0 top-0 bottom-0 w-full max-w-[800px] bg-[#131318] border-l border-white/[0.06] flex flex-col z-50 shadow-2xl shadow-black/40"
      >
        <div className="flex items-center justify-between px-5 py-3 border-b border-white/[0.06] flex-shrink-0">
          <div className="flex items-center gap-3">
            <button
              onClick={onClose}
              className="w-7 h-7 rounded-lg bg-white/[0.06] flex items-center justify-center hover:bg-white/[0.1]"
              aria-label="Close panel"
              type="button"
            >
              <X size={15} className="text-white/60" />
            </button>
            <span className="text-[15px] font-semibold text-white/90">Service unavailable</span>
          </div>
        </div>
        <div className="flex-1 flex flex-col items-center justify-center p-8 text-center">
          <div className="w-12 h-12 rounded-full bg-red-500/10 flex items-center justify-center mb-4">
            <Box size={24} className="text-red-400" />
          </div>
          <p className="text-white/60 text-[14px] mb-2">Failed to load service details</p>
          {error && <p className="text-white/40 text-[12px] mb-6 max-w-md">{error.message}</p>}
          <button
            type="button"
            onClick={() => refetch()}
            className="px-4 py-2 bg-white/[0.06] text-white/70 rounded-lg text-[13px] hover:bg-white/[0.1] transition-colors"
          >
            Retry
          </button>
        </div>
      </div>
    )
  }

  const db = svc.type === 'database'
  const tabs = db
    ? ['overview', 'logs', 'console', 'database', 'backups', 'variables', 'metrics', 'settings']
    : ['overview', 'deploy', 'logs', 'console', 'variables', 'domains', 'storage', 'metrics', 'settings']

  const color = getServiceColor(svc.subtype, svc.dockerImage)

  return (
    <div
      data-service-panel
      className="absolute right-0 top-0 bottom-0 w-full max-w-[800px] bg-[#131318] border-l border-white/[0.06] flex flex-col z-50 shadow-2xl shadow-black/40"
      onWheel={(e) => e.stopPropagation()}
      onMouseDown={(e) => e.stopPropagation()}
    >
      {/* Header */}
      <div className="flex items-center justify-between px-5 py-3 border-b border-white/[0.06] flex-shrink-0">
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={onClose}
            className="w-7 h-7 rounded-lg bg-white/[0.06] flex items-center justify-center hover:bg-white/[0.1]"
            aria-label="Close panel"
          >
            <X size={15} className="text-white/60" />
          </button>
          <div
            className="w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0"
            style={{ backgroundColor: `${color}15` }}
          >
            <ServiceIcon subtype={svc.subtype} dockerImage={svc.dockerImage} size={17} />
          </div>
          <div>
            <div className="text-[15px] font-semibold text-white/90">{svc.name}</div>
            <div className="text-[11px] text-white/40">
              {svc.subtype} {svc.version ? `v${svc.version}` : ''}
              {deploymentRealtime.lastUpdate && <span className="ml-2 text-white/25">· {deploymentRealtime.lastUpdate.message}</span>}
            </div>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {/* Lifecycle actions */}
          <div className="flex items-center gap-1 mr-2">
            {!db && (
              <button
                onClick={handleDeploy}
                disabled={deployService.isPending}
                title="Deploy"
                className="flex items-center gap-1 px-2.5 py-1.5 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[11px] hover:bg-[#8b5cf6]/25 transition-all disabled:opacity-50"
              >
                <Rocket size={12} />
                {deployService.isPending ? '...' : 'Deploy'}
              </button>
            )}
            {svc.status !== 'running' && svc.status !== 'deploying' && (
              <button
                onClick={() => startService.mutate(serviceId)}
                disabled={startService.isPending}
                title="Start"
                className="flex items-center gap-1 px-2 py-1.5 bg-[#22c55e]/10 text-[#22c55e] rounded-lg text-[11px] hover:bg-[#22c55e]/20 transition-all disabled:opacity-50"
              >
                <Play size={12} />
                {startService.isPending ? '...' : 'Start'}
              </button>
            )}
            {svc.status === 'running' && (
              <button
                onClick={() => stopService.mutate(serviceId)}
                disabled={stopService.isPending}
                title="Stop"
                className="flex items-center gap-1 px-2 py-1.5 bg-white/5 text-white/50 rounded-lg text-[11px] hover:bg-white/10 hover:text-white/70 transition-all disabled:opacity-50"
              >
                <Square size={12} />
                {stopService.isPending ? '...' : 'Stop'}
              </button>
            )}
            <button
              onClick={() => restartService.mutate(serviceId)}
              disabled={restartService.isPending}
              title="Restart"
              className="flex items-center gap-1 px-2 py-1.5 bg-white/5 text-white/50 rounded-lg text-[11px] hover:bg-white/10 hover:text-white/70 transition-all disabled:opacity-50"
            >
              <RotateCw size={12} />
              {restartService.isPending ? '...' : 'Restart'}
            </button>
            <button
              onClick={() => rebuildService.mutate(serviceId)}
              disabled={rebuildService.isPending}
              title="Rebuild"
              className="flex items-center gap-1 px-2 py-1.5 bg-white/5 text-white/50 rounded-lg text-[11px] hover:bg-white/10 hover:text-white/70 transition-all disabled:opacity-50"
            >
              <Wrench size={12} />
              {rebuildService.isPending ? '...' : 'Rebuild'}
            </button>
          </div>
          <span
            className="text-[11px] px-2 py-0.5 rounded-full"
            style={{
              backgroundColor: svc.status === 'running' ? '#22c55e15' : '#4A4A5515',
              color: svc.status === 'running' ? '#22c55e' : '#8A8A95',
            }}
          >
            {svc.status === 'running' ? 'Online' : svc.status}
          </span>
          <span className={`h-2 w-2 rounded-full ${deploymentRealtime.connectionState === 'live' ? 'bg-emerald-400' : deploymentRealtime.connectionState === 'fallback' ? 'bg-blue-400' : 'bg-amber-400'}`} title={`${realtimeStateLabel(deploymentRealtime.connectionState)} updates`} />
        </div>
      </div>

      {/* Tabs */}
      <div className="flex border-b border-white/[0.06] overflow-x-auto flex-shrink-0" role="tablist" aria-label="Service sections">
        {tabs.map((t) => (
          <button
            key={t}
            type="button"
            role="tab"
            aria-selected={tab === t}
            onClick={() => setTab(t)}
            className={`px-4 py-2.5 text-[13px] border-b-2 transition-all whitespace-nowrap ${
              tab === t
                ? 'border-[#8b5cf6] text-[#8b5cf6]'
                : 'border-transparent text-white/40 hover:text-white/60'
            }`}
          >
            {t.charAt(0).toUpperCase() + t.slice(1)}
          </button>
        ))}
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto" data-no-pan>
        {tab === 'overview' && <OverviewTab svc={svc} serviceId={serviceId} lastUpdate={deploymentRealtime.lastUpdate} isConnected={deploymentRealtime.isConnected} />}
        {tab === 'deploy' && <DeployTab svc={svc} serviceId={serviceId} realtime={deploymentRealtime} />}
        {tab === 'logs' && <LogsTab serviceId={serviceId} />}
        {tab === 'console' && <InteractiveTerminal serviceId={serviceId} serviceName={svc.name} />}
        {tab === 'database' && db && <DatabaseTab svc={svc} serviceId={serviceId} />}
        {tab === 'backups' && <BackupsTab svc={svc} serviceId={serviceId} />}
        {tab === 'variables' && <VariablesTab svc={svc} />}
        {tab === 'domains' && <DomainsTab svc={svc} />}
        {tab === 'storage' && <StorageTab svc={svc} />}
        {tab === 'metrics' && <MetricsTab svc={svc} />}
        {tab === 'settings' && <SettingsPanel svc={svc} />}
      </div>
    </div>
  )
}
