import { useState, useEffect, useRef, useMemo } from 'react'
import { Box, X, ArrowDownToLine, Trash2, Globe, HardDrive, Play, Square, RotateCw, Rocket, ChevronDown, ChevronRight, Terminal, GitBranch, Settings2, Wrench, Clock, CheckCircle2, XCircle, Loader2, Upload, AlertCircle, ArrowRight } from 'lucide-react'
import AccessibleToggle from '@/features/shared/AccessibleToggle'
import { useService, useScaleProcess, useSetEnvVar, useUnsetEnvVar, useServiceMetrics, useServiceDeployments, useAddDomain, useRemoveDomain, useAddStorageMount, useRemoveStorageMount, useBackupService, useRestoreService, useRollbackService, useContainerStatus, useDeployService, useStartService, useStopService, useRestartService, useRebuildService, useDeployment, useDestroyService, useDatabaseInfo, useBackups } from '@/hooks/useServices'
import { useWebSocketDeployments } from '@/hooks/useWebSocketDeployments'
import { useUpdateService } from '@/hooks/useServices'
import { useCanvasStore } from '@/stores/useCanvasStore'
import type { Service } from '@/types'
import { api } from '@/lib/api'
import LogsTab from '@/features/service-panel/tabs/LogsTab'
import ConsoleTab from '@/features/service-panel/tabs/ConsoleTab'

const SVC_ICON: Record<string, React.ElementType> = {
  web: () => null, worker: Box, postgres: () => null, redis: () => null,
  mysql: () => null, mongo: () => null, clock: Box,
}
const SVC_CLR: Record<string, string> = {
  web: '#22c55e', worker: '#3b82f6', postgres: '#8b5cf6',
  redis: '#f59e0b', mysql: '#3b82f6', mongo: '#22c55e', clock: '#a855f7',
}

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

  const handleDeploy = () => {
    setTab('deploy')
    deployService.mutate(serviceId)
  }

  if (isLoading) {
    return (
      <div data-service-panel className="absolute right-0 top-0 bottom-0 w-[800px] bg-[#131318] border-l border-white/[0.06] flex flex-col z-50 shadow-2xl shadow-black/40">
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
      <div data-service-panel className="absolute right-0 top-0 bottom-0 w-[800px] bg-[#131318] border-l border-white/[0.06] flex flex-col z-50 shadow-2xl shadow-black/40">
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
          {error && (
            <p className="text-white/40 text-[12px] mb-6 max-w-md">{error.message}</p>
          )}
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
    ? ['overview', 'logs', 'database', 'backups', 'variables', 'metrics', 'settings']
    : ['overview', 'deploy', 'logs', 'console', 'variables', 'domains', 'storage', 'metrics', 'settings']

  const Icon = SVC_ICON[svc.subtype] || Box
  const color = SVC_CLR[svc.subtype] || '#A0A0B0'

  return (
    <div data-service-panel className="absolute right-0 top-0 bottom-0 w-[800px] bg-[#131318] border-l border-white/[0.06] flex flex-col z-50 shadow-2xl shadow-black/40" onWheel={(e) => e.stopPropagation()} onMouseDown={(e) => e.stopPropagation()}>
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
            <Icon size={17} style={{ color }} />
          </div>
          <div>
            <div className="text-[15px] font-semibold text-white/90">{svc.name}</div>
            <div className="text-[11px] text-white/40">
              {svc.subtype} {svc.version ? `v${svc.version}` : ''}
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
        </div>
      </div>

      {/* Tabs */}
      <div className="flex border-b border-white/[0.06] overflow-x-auto flex-shrink-0">
        {tabs.map((t) => (
          <button
            key={t}
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
        {tab === 'overview' && <OverviewTab svc={svc} serviceId={serviceId} onDeploy={handleDeploy} />}
        {tab === 'deploy' && <DeployTab svc={svc} serviceId={serviceId} />}
        {tab === 'logs' && <LogsTab serviceId={serviceId} />}
        {tab === 'console' && <ConsoleTab serviceId={serviceId} serviceName={svc.name} />}
        {tab === 'database' && db && <DatabaseTab svc={svc} serviceId={serviceId} />}
        {tab === 'backups' && <BackupsTab svc={svc} serviceId={serviceId} />}
        {tab === 'variables' && <VariablesTab svc={svc} />}
        {tab === 'domains' && <DomainsTab svc={svc} />}
        {tab === 'storage' && <StorageTab svc={svc} />}
        {tab === 'metrics' && <MetricsTab svc={svc} />}
        {tab === 'settings' && <SettingsTab svc={svc} />}
      </div>
    </div>
  )
}

// ── Overview Tab ─────────────────────────────
function OverviewTab({ svc, serviceId, onDeploy }: { svc: Service; serviceId: string; onDeploy: () => void }) {
  const scaleProcess = useScaleProcess()
  const { data: containerStatus } = useContainerStatus(serviceId)
  const { lastUpdate, isConnected, logMap } = useWebSocketDeployments(serviceId)
  const deployService = useDeployService()
  const startService = useStartService()
  const stopService = useStopService()
  const restartService = useRestartService()
  const rebuildService = useRebuildService()

  return (
    <div className="p-5 space-y-5">
      {/* Status Card */}
      <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4">
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-3">
            <div
              className="w-10 h-10 rounded-xl flex items-center justify-center"
              style={{ backgroundColor: svc.status === 'running' ? '#22c55e15' : '#4A4A5515' }}
            >
              <Box size={20} style={{ color: svc.status === 'running' ? '#22c55e' : '#8A8A95' }} />
            </div>
            <div>
              <div className="text-[14px] font-medium text-white/80">{svc.name}</div>
              <div className="text-[12px] text-white/40">{svc.subtype} · {svc.status}</div>
            </div>
          </div>
          <span
            className="text-[11px] px-2.5 py-1 rounded-full font-medium"
            style={{
              backgroundColor: svc.status === 'running' ? '#22c55e15' : '#4A4A5515',
              color: svc.status === 'running' ? '#22c55e' : '#8A8A95',
            }}
          >
            {svc.status === 'running' ? 'Online' : svc.status}
          </span>
        </div>

        {/* Quick Actions */}
        <div className="flex items-center gap-2">
          {svc.type !== 'database' && (
            <button
              onClick={onDeploy}
              disabled={deployService.isPending}
              className="flex items-center gap-1.5 px-3 py-2 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[12px] font-medium hover:bg-[#8b5cf6]/25 transition-all disabled:opacity-50"
            >
              <Rocket size={13} />
              {deployService.isPending ? 'Deploying...' : 'Deploy'}
            </button>
          )}
          {svc.status !== 'running' && svc.status !== 'deploying' && (
            <button
              onClick={() => startService.mutate(serviceId)}
              disabled={startService.isPending}
              className="flex items-center gap-1.5 px-3 py-2 bg-[#22c55e]/10 text-[#22c55e] rounded-lg text-[12px] font-medium hover:bg-[#22c55e]/20 transition-all disabled:opacity-50"
            >
              <Play size={13} />
              {startService.isPending ? 'Starting...' : 'Start'}
            </button>
          )}
          {svc.status === 'running' && (
            <button
              onClick={() => stopService.mutate(serviceId)}
              disabled={stopService.isPending}
              className="flex items-center gap-1.5 px-3 py-2 bg-white/5 text-white/50 rounded-lg text-[12px] font-medium hover:bg-white/10 hover:text-white/70 transition-all disabled:opacity-50"
            >
              <Square size={13} />
              {stopService.isPending ? 'Stopping...' : 'Stop'}
            </button>
          )}
          <button
            onClick={() => restartService.mutate(serviceId)}
            disabled={restartService.isPending}
            className="flex items-center gap-1.5 px-3 py-2 bg-white/5 text-white/50 rounded-lg text-[12px] font-medium hover:bg-white/10 hover:text-white/70 transition-all disabled:opacity-50"
          >
            <RotateCw size={13} />
            {restartService.isPending ? 'Restarting...' : 'Restart'}
          </button>
          <button
            onClick={() => rebuildService.mutate(serviceId)}
            disabled={rebuildService.isPending}
            className="flex items-center gap-1.5 px-3 py-2 bg-white/5 text-white/50 rounded-lg text-[12px] font-medium hover:bg-white/10 hover:text-white/70 transition-all disabled:opacity-50"
          >
            <Wrench size={13} />
            {rebuildService.isPending ? 'Rebuilding...' : 'Rebuild'}
          </button>
        </div>
      </div>

      {/* Source Info */}
      {(svc.gitRepo || svc.dockerImage || svc.builder) && (
        <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4 space-y-2">
          <div className="text-[13px] font-medium text-white/70 mb-2">Source</div>
          {svc.gitRepo && (
            <div className="flex items-center gap-2 text-[12px]">
              <GitBranch size={13} className="text-white/30" />
              <span className="text-white/50">{svc.gitRepo}</span>
              <span className="text-white/20">on</span>
              <span className="text-white/50 font-mono">{svc.branch || 'main'}</span>
            </div>
          )}
          {svc.dockerImage && (
            <div className="flex items-center gap-2 text-[12px]">
              <Box size={13} className="text-white/30" />
              <span className="text-white/40">Image:</span>
              <span className="text-white/60 font-mono">{svc.dockerImage}</span>
            </div>
          )}
          {svc.builder && (
            <div className="flex items-center gap-2 text-[12px]">
              <Settings2 size={13} className="text-white/30" />
              <span className="text-white/40">Builder:</span>
              <span className="text-white/60 capitalize">{svc.builder}</span>
            </div>
          )}
        </div>
      )}

      {/* Processes */}
      {svc.processTypes && svc.processTypes.length > 0 && (
        <div>
          <h4 className="text-[14px] font-medium text-white/70 mb-3">Processes</h4>
          <div className="space-y-2">
            {svc.processTypes.map((pt) => (
              <div
                key={pt.name}
                className="flex items-center justify-between bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3"
              >
                <div>
                  <div className="text-[13px] font-medium text-white/80">{pt.name}</div>
                  <div className="text-[11px] text-white/40 font-mono mt-0.5">
                    {pt.command || 'No command'}
                  </div>
                </div>
                <div className="flex items-center gap-3">
                  <span className="text-[12px] text-white/40">
                    {pt.running}/{pt.quantity} running
                  </span>
                  <div className="flex items-center border border-white/[0.1] rounded-lg overflow-hidden">
                    <button
                      onClick={() =>
                        scaleProcess.mutate({
                          id: svc.id,
                          processName: pt.name,
                          quantity: Math.max(0, pt.quantity - 1),
                        })
                      }
                      className="px-2.5 py-1.5 text-white/40 hover:text-white/70 hover:bg-white/[0.06]"
                    >
                      −
                    </button>
                    <span className="px-3 py-1.5 text-[13px] text-white/70 min-w-[40px] text-center border-x border-white/[0.06]">
                      {pt.quantity}
                    </span>
                    <button
                      onClick={() =>
                        scaleProcess.mutate({
                          id: svc.id,
                          processName: pt.name,
                          quantity: pt.quantity + 1,
                        })
                      }
                      className="px-2.5 py-1.5 text-white/40 hover:text-white/70 hover:bg-white/[0.06]"
                    >
                      +
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Container Status */}
      {containerStatus && (
        <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3">
          <div className="flex items-center justify-between">
            <div className="text-[12px] text-white/60">Container Status</div>
            <span className={`text-[10px] px-2 py-0.5 rounded-full ${
              containerStatus.status === 'running' ? 'bg-[#22c55e]/10 text-[#22c55e]' : 'bg-white/5 text-white/40'
            }`}>{containerStatus.status}</span>
          </div>
        </div>
      )}

      {/* Last Deployment */}
      {lastUpdate && (
        <div className="bg-[#8b5cf6]/5 border border-[#8b5cf6]/20 rounded-lg p-3 flex items-center gap-2">
          <span className={`w-2 h-2 rounded-full ${isConnected ? 'bg-[#22c55e]' : 'bg-white/20'} animate-pulse`} />
          <span className="text-[12px] text-white/60">{lastUpdate.message}</span>
          <span className={`text-[10px] px-1.5 py-0.5 rounded-full ml-auto ${
            lastUpdate.status === 'succeeded' ? 'bg-[#22c55e]/10 text-[#22c55e]' :
            lastUpdate.status === 'failed' ? 'bg-red-500/10 text-red-400' :
            'bg-[#8b5cf6]/10 text-[#8b5cf6]'
          }`}>{lastUpdate.status}</span>
        </div>
      )}
    </div>
  )
}

// ── Deploy Tab ───────────────────────────────
function DeployTab({ svc, serviceId }: { svc: Service; serviceId: string }) {
  const scaleProcess = useScaleProcess()
  const rollbackService = useRollbackService()
  const { data: deployments } = useServiceDeployments(svc.id)
  const { data: containerStatus } = useContainerStatus(serviceId)
  const { lastUpdate, isConnected, logMap } = useWebSocketDeployments(serviceId)
  const [expandedDeployment, setExpandedDeployment] = useState<string | null>(null)

  // Auto-expand the active deployment when a new one starts via WebSocket
  useEffect(() => {
    if (lastUpdate?.deployment_id) {
      setExpandedDeployment(String(lastUpdate.deployment_id))
    }
  }, [lastUpdate?.deployment_id])

  return (
    <div className="p-5 space-y-5">
      <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span className="text-[11px] px-2 py-0.5 bg-[#22c55e]/10 text-[#22c55e] rounded-full font-medium">
              ACTIVE
            </span>
            <span className="text-[13px] text-white/50">
              {svc.lastDeployed || 'No deployments yet'}
            </span>
          </div>
        </div>
        {svc.gitRepo && (
          <div className="mt-3 flex items-center gap-2 text-[12px] text-white/40">
            <span>{svc.gitRepo}</span>
            <span className="text-white/20">on</span>
            <span className="text-white/50">{svc.branch || 'main'}</span>
          </div>
        )}
        {svc.builder && (
          <div className="mt-2 text-[12px] text-white/40">
            Builder: <span className="text-white/60">{svc.builder}</span>
          </div>
        )}
      </div>

      {svc.processTypes && svc.processTypes.length > 0 && (
        <div>
          <h4 className="text-[14px] font-medium text-white/70 mb-3">Processes</h4>
          <div className="space-y-2">
            {svc.processTypes.map((pt) => (
              <div
                key={pt.name}
                className="flex items-center justify-between bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3"
              >
                <div>
                  <div className="text-[13px] font-medium text-white/80">{pt.name}</div>
                  <div className="text-[11px] text-white/40 font-mono mt-0.5">
                    {pt.command || 'No command'}
                  </div>
                </div>
                <div className="flex items-center gap-3">
                  <span className="text-[12px] text-white/40">
                    {pt.running}/{pt.quantity} running
                  </span>
                  <div className="flex items-center border border-white/[0.1] rounded-lg overflow-hidden">
                    <button
                      onClick={() =>
                        scaleProcess.mutate({
                          id: svc.id,
                          processName: pt.name,
                          quantity: Math.max(0, pt.quantity - 1),
                        })
                      }
                      className="px-2.5 py-1.5 text-white/40 hover:text-white/70 hover:bg-white/[0.06]"
                    >
                      −
                    </button>
                    <span className="px-3 py-1.5 text-[13px] text-white/70 min-w-[40px] text-center border-x border-white/[0.06]">
                      {pt.quantity}
                    </span>
                    <button
                      onClick={() =>
                        scaleProcess.mutate({
                          id: svc.id,
                          processName: pt.name,
                          quantity: pt.quantity + 1,
                        })
                      }
                      className="px-2.5 py-1.5 text-white/40 hover:text-white/70 hover:bg-white/[0.06]"
                    >
                      +
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {containerStatus && (
        <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3">
          <div className="flex items-center justify-between">
            <div className="text-[12px] text-white/60">Container Status</div>
            <span className={`text-[10px] px-2 py-0.5 rounded-full ${
              containerStatus.status === 'running' ? 'bg-[#22c55e]/10 text-[#22c55e]' : 'bg-white/5 text-white/40'
            }`}>{containerStatus.status}</span>
          </div>
        </div>
      )}

      {lastUpdate && (
        <div className="bg-[#8b5cf6]/5 border border-[#8b5cf6]/20 rounded-lg p-3 flex items-center gap-2">
          <span className={`w-2 h-2 rounded-full ${isConnected ? 'bg-[#22c55e]' : 'bg-white/20'} animate-pulse`} />
          <span className="text-[12px] text-white/60">{lastUpdate.message}</span>
          <span className={`text-[10px] px-1.5 py-0.5 rounded-full ml-auto ${
            lastUpdate.status === 'succeeded' ? 'bg-[#22c55e]/10 text-[#22c55e]' :
            lastUpdate.status === 'failed' ? 'bg-red-500/10 text-red-400' :
            'bg-[#8b5cf6]/10 text-[#8b5cf6]'
          }`}>{lastUpdate.status}</span>
        </div>
      )}

      <div>
        <h4 className="text-[14px] font-medium text-white/70 mb-3">Deployment History</h4>
        <div className="space-y-1.5">
          {deployments && deployments.length > 0 ? (
            deployments.map((d) => (
              <div key={d.id} className="space-y-1">
                <div
                  className="flex items-center gap-3 text-[12px] px-3 py-2 bg-[#1a1a1e]/50 rounded-lg group cursor-pointer hover:bg-[#1a1a1e]"
                  onClick={() => setExpandedDeployment(expandedDeployment === d.id ? null : d.id)}
                >
                  {expandedDeployment === d.id ? (
                    <ChevronDown size={14} className="text-white/30 flex-shrink-0" />
                  ) : (
                    <ChevronRight size={14} className="text-white/30 flex-shrink-0" />
                  )}
                  <span className={`text-[10px] px-1.5 py-0.5 rounded-full font-medium ${
                    d.status === 'succeeded' ? 'bg-[#22c55e]/10 text-[#22c55e]' :
                    d.status === 'failed' ? 'bg-red-500/10 text-red-400' :
                    d.status === 'deploying' ? 'bg-[#8b5cf6]/10 text-[#8b5cf6]' :
                    'bg-white/5 text-white/40'
                  }`}>
                    {d.status}
                  </span>
                  <span className="text-white/30 font-mono">
                    {d.created_at ? new Date(d.created_at).toLocaleString() : '-'}
                  </span>
                  <span className="text-white/50 truncate flex-1">{d.commit_sha || d.branch || 'manual deploy'}</span>
                  {d.status === 'succeeded' && (
                    <button
                      onClick={(e) => {
                        e.stopPropagation()
                        rollbackService.mutate({ id: svc.id, deploymentId: d.id })
                      }}
                      disabled={rollbackService.isPending}
                      className="text-[10px] px-2 py-1 bg-white/[0.06] text-white/40 rounded hover:bg-white/[0.1] hover:text-white/70 opacity-0 group-hover:opacity-100 transition-all disabled:opacity-50"
                    >
                      Rollback
                    </button>
                  )}
                </div>
                {expandedDeployment === d.id && (
                  <DeploymentLogPanel deploymentId={d.id} liveLog={logMap[d.id]} />
                )}
              </div>
            ))
          ) : (
            <div className="text-[12px] text-white/30 py-4 text-center">No deployment history</div>
          )}
        </div>
      </div>
    </div>
  )
}

function DeploymentLogPanel({ deploymentId, liveLog }: { deploymentId: string; liveLog?: string }) {
  const { data: deployment, isLoading } = useDeployment(deploymentId)
  const logRef = useRef<HTMLDivElement>(null)

  const logText = liveLog || deployment?.deployLog || deployment?.buildLog || ''

  useEffect(() => {
    if (logRef.current) {
      logRef.current.scrollTop = logRef.current.scrollHeight
    }
  }, [logText])

  if (isLoading && !liveLog) {
    return (
      <div className="ml-6 bg-[#0a0a0c] border border-white/[0.06] rounded-lg p-4">
        <div className="text-[12px] text-white/30">Loading logs...</div>
      </div>
    )
  }

  const lines = logText.split('\n').filter(Boolean)

  return (
    <div className="ml-6 bg-[#0a0a0c] border border-white/[0.06] rounded-lg overflow-hidden">
      <div className="flex items-center gap-2 px-3 py-2 border-b border-white/[0.06]">
        <Terminal size={12} className="text-white/30" />
        <span className="text-[11px] text-white/40">Deployment Log</span>
        {lines.length > 0 && (
          <span className="text-[10px] text-white/20 ml-auto">{lines.length} lines</span>
        )}
      </div>
      <div ref={logRef} className="max-h-64 overflow-y-auto p-3 font-mono text-[11px] space-y-0.5">
        {lines.length > 0 ? (
          lines.map((line, i) => (
            <div key={i} className="text-white/50">
              <span className="text-white/20 mr-2 select-none">{String(i + 1).padStart(4, '0')}</span>
              <span>{line}</span>
            </div>
          ))
        ) : (
          <div className="text-white/20 text-center py-6">No log output captured for this deployment.</div>
        )}
      </div>
    </div>
  )
}

// ── Database Tab ─────────────────────────────
function DatabaseTab({ svc, serviceId }: { svc: Service; serviceId: string }) {
  const { data: info, isLoading } = useDatabaseInfo(serviceId)
  const [copied, setCopied] = useState<string | null>(null)

  const handleCopy = (text: string, label: string) => {
    navigator.clipboard.writeText(text)
    setCopied(label)
    setTimeout(() => setCopied(null), 2000)
  }

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
      {/* Connection URL */}
      <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4">
        <div className="flex items-center justify-between mb-3">
          <div className="text-[13px] font-medium text-white/70">Connection</div>
          {info?.status && (
            <span className={`text-[11px] px-2 py-0.5 rounded-full ${info.status === 'running' ? 'bg-emerald-500/10 text-emerald-400' : 'bg-white/5 text-white/40'}`}>
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
                  onClick={() => handleCopy(connectionUrl, 'url')}
                  className="text-[11px] text-white/30 hover:text-white/60 transition-colors"
                >
                  {copied === 'url' ? 'Copied!' : 'Copy'}
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
                        onClick={() => handleCopy(f.value!, f.label)}
                        className="opacity-0 group-hover:opacity-100 text-[10px] text-white/30 hover:text-white/60 transition-all"
                      >
                        {copied === f.label ? 'Copied!' : 'Copy'}
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
                    onClick={() => handleCopy(quickConnect, 'cmd')}
                    className="text-[11px] text-white/30 hover:text-white/60 transition-colors"
                  >
                    {copied === 'cmd' ? 'Copied!' : 'Copy'}
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

      {/* Service Info */}
      <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4">
        <div className="text-[13px] font-medium text-white/70 mb-3">Service Details</div>
        <div className="grid grid-cols-2 gap-2">
          {[
            { l: 'Type', v: svc.subtype },
            { l: 'Version', v: svc.version || info?.version || 'latest' },
            { l: 'Name', v: svc.name },
            { l: 'Status', v: svc.status },
            { l: 'Internal IP', v: info?.internal_ip },
            { l: 'Dokku Name', v: svc.name?.replace(/[^a-z0-9]/gi, '-').toLowerCase() },
          ].filter((f) => f.v).map((f) => (
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

// ── Backups Tab ──────────────────────────────
function formatSize(bytes: number): string {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i]
}

function BackupsTab({ svc, serviceId }: { svc: Service; serviceId: string }) {
  const { data: backups, isLoading, isError, refetch } = useBackups(serviceId)
  const backupService = useBackupService()
  const restoreService = useRestoreService()
  const fileInputRef = useRef<HTMLInputElement>(null)

  const handleRestoreClick = () => {
    fileInputRef.current?.click()
  }

  const handleFileSelected = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return
    restoreService.mutate({ id: serviceId, file })
    e.target.value = ''
  }

  const handleCreateBackup = () => {
    backupService.mutate(serviceId, {
      onSuccess: () => refetch(),
    })
  }

  return (
    <div className="p-5 space-y-5">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <div className="text-[14px] font-medium text-white/70">Backups</div>
          <div className="text-[12px] text-white/40 mt-0.5">
            {backups?.length ?? svc.backups.length} backup(s) available
          </div>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={handleRestoreClick}
            disabled={restoreService.isPending}
            className="flex items-center gap-1.5 px-3 py-2 bg-white/[0.06] text-white/60 rounded-lg text-[12px] hover:bg-white/[0.1] transition-all disabled:opacity-50"
            title="Restore from backup file"
          >
            <Upload size={13} />
            {restoreService.isPending ? 'Restoring...' : 'Restore'}
          </button>
          <input
            ref={fileInputRef}
            type="file"
            accept=".sql,.dump,.gz,.zip"
            className="hidden"
            onChange={handleFileSelected}
          />
          <button
            onClick={handleCreateBackup}
            disabled={backupService.isPending}
            className="flex items-center gap-1.5 px-3 py-2 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[12px] hover:bg-[#8b5cf6]/25 transition-all disabled:opacity-50"
          >
            {backupService.isPending ? <Loader2 size={13} className="animate-spin" /> : <ArrowDownToLine size={13} />}
            {backupService.isPending ? 'Creating...' : 'Create Backup'}
          </button>
        </div>
      </div>

      {/* Backup List */}
      {isLoading ? (
        <div className="space-y-2">
          {[1, 2, 3].map((i) => (
            <div key={i} className="flex items-center gap-3 bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3 animate-pulse">
              <div className="flex-1 space-y-2">
                <div className="h-3.5 bg-white/5 rounded w-32" />
                <div className="h-2.5 bg-white/5 rounded w-48" />
              </div>
              <div className="h-5 bg-white/5 rounded w-16" />
              <div className="h-4 bg-white/5 rounded w-12" />
            </div>
          ))}
        </div>
      ) : isError ? (
        <div className="text-center py-12">
          <AlertCircle size={24} className="mx-auto text-red-400/60 mb-2" />
          <div className="text-[13px] text-white/40">Failed to load backups</div>
          <button
            onClick={() => refetch()}
            className="mt-2 text-[12px] text-[#8b5cf6] hover:text-[#8b5cf6]/80"
          >
            Retry
          </button>
        </div>
      ) : (backups && backups.length > 0) || svc.backups.length > 0 ? (
        <div className="space-y-2">
          {(backups || svc.backups).map((b) => {
            const statusConfig = {
              completed: { icon: CheckCircle2, color: 'text-[#22c55e]', bg: 'bg-[#22c55e]/10' },
              success: { icon: CheckCircle2, color: 'text-[#22c55e]', bg: 'bg-[#22c55e]/10' },
              failed: { icon: XCircle, color: 'text-red-400', bg: 'bg-red-400/10' },
              pending: { icon: Loader2, color: 'text-amber-400', bg: 'bg-amber-400/10' },
              running: { icon: Loader2, color: 'text-[#8b5cf6]', bg: 'bg-[#8b5cf6]/10' },
            }
            const config = statusConfig[b.status as keyof typeof statusConfig] || statusConfig.pending
            const StatusIcon = config.icon
            const sizeNum = typeof b.size === 'number' ? b.size : parseInt(b.size as string) || 0

            return (
              <div
                key={b.id}
                className="flex items-center gap-3 bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3 group"
              >
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <div className="text-[13px] text-white/70 truncate">Backup {String(b.id).slice(0, 8)}</div>
                    <span className={`inline-flex items-center gap-1 text-[11px] px-2 py-0.5 rounded-full ${config.bg} ${config.color}`}>
                      <StatusIcon size={11} className={b.status === 'pending' || b.status === 'running' ? 'animate-spin' : ''} />
                      {b.status}
                    </span>
                  </div>
                  <div className="flex items-center gap-3 mt-0.5">
                    <span className="text-[11px] text-white/40 flex items-center gap-1">
                      <Clock size={10} />
                      {new Date(b.createdAt).toLocaleString()}
                    </span>
                    <span className="text-[11px] text-white/40 font-mono">{formatSize(sizeNum)}</span>
                  </div>
                </div>
                <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                  <button
                    type="button"
                    disabled
                    className="p-1.5 hover:bg-white/[0.06] rounded text-white/30 hover:text-white/60 disabled:opacity-30 disabled:cursor-not-allowed"
                    title="Download (coming soon)"
                    aria-label="Download backup"
                  >
                    <ArrowDownToLine size={13} />
                  </button>
                  <button
                    type="button"
                    disabled
                    className="p-1.5 hover:bg-white/[0.06] rounded text-white/30 hover:text-red-400 disabled:opacity-30 disabled:cursor-not-allowed"
                    title="Delete (coming soon)"
                    aria-label="Delete backup"
                  >
                    <Trash2 size={13} />
                  </button>
                </div>
              </div>
            )
          })}
        </div>
      ) : (
        <div className="text-center py-12 border border-dashed border-white/[0.08] rounded-xl">
          <HardDrive size={28} className="mx-auto text-white/15 mb-3" />
          <div className="text-[13px] text-white/40 font-medium">No backups yet</div>
          <div className="text-[12px] text-white/25 mt-1">Create your first backup to protect your data.</div>
        </div>
      )}
    </div>
  )
}

// ── Variables Tab ────────────────────────────
function resolveEnvRef(value: string, allServices: Service[]): string {
  const refPattern = /\$\{\{([^}]+)\}\}/g
  return value.replace(refPattern, (_, ref) => {
    const parts = ref.split('.')
    if (parts.length !== 2) return '${{' + ref + '}}'
    const [svcName, varName] = parts
    const target = allServices.find((s) => s.name === svcName)
    if (!target) return '${{' + ref + '}}'
    const targetVar = target.envVars.find((ev) => ev.key === varName)
    return targetVar?.value || '${{' + ref + '}}'
  })
}

function VariablesTab({ svc }: { svc: Service }) {
  const [editing, setEditing] = useState<string | null>(null)
  const [newKey, setNewKey] = useState('')
  const [newVal, setNewVal] = useState('')
  const setEnvVar = useSetEnvVar()
  const unsetEnvVar = useUnsetEnvVar()

  return (
    <div className="p-5">
      <div className="flex items-center justify-between mb-4">
        <div>
          <div className="text-[14px] font-medium text-white/70">Environment Variables</div>
          <div className="text-[12px] text-white/40 mt-0.5">{svc.envVars.length} variable(s)</div>
        </div>
      </div>
      <div className="space-y-2">
        {svc.envVars.map((ev) => (
          <div
            key={ev.key}
            className="flex items-center gap-3 bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3 group"
          >
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <span className="text-[13px] font-mono text-[#8b5cf6]/80">{ev.key}</span>
                {ev.source && (
                  <span className="text-[10px] px-1.5 py-0.5 bg-white/[0.06] text-white/40 rounded-full">
                    {ev.source}
                  </span>
                )}
              </div>
              {editing === ev.key ? (
                <input
                  type="text"
                  defaultValue={ev.value}
                  autoFocus
                  onBlur={(e) => {
                    setEnvVar.mutate({ id: svc.id, key: ev.key, value: e.target.value })
                    setEditing(null)
                  }}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') {
                      setEnvVar.mutate({ id: svc.id, key: ev.key, value: (e.target as HTMLInputElement).value })
                      setEditing(null)
                    }
                  }}
                  className="flex-1 mt-1 bg-black/40 border border-white/[0.08] rounded px-2 py-1 text-[12px] font-mono text-white/70 focus:outline-none focus:border-[#8b5cf6]/40 w-full"
                />
              ) : (
                <div className="text-[12px] text-white/50 font-mono mt-0.5 truncate">
                  {ev.value}
                  {ev.value.includes('${{') && (
                    <span className="ml-2 text-[10px] px-1.5 py-0.5 bg-[#8b5cf6]/10 text-[#8b5cf6]/60 rounded">reference</span>
                  )}
                </div>
              )}
            </div>
            <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
              <button
                onClick={() => setEditing(editing === ev.key ? null : ev.key)}
                className="p-1.5 hover:bg-white/[0.06] rounded text-white/30 hover:text-white/60"
              >
                Edit
              </button>
              {!ev.isDokkuInternal && (
                <button
                  onClick={() => unsetEnvVar.mutate({ id: svc.id, key: ev.key })}
                  className="p-1.5 hover:bg-white/[0.06] rounded text-white/30 hover:text-red-400"
                >
                  <Trash2 size={12} />
                </button>
              )}
            </div>
          </div>
        ))}
      </div>
      <div className="mt-4 bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3">
        <div className="text-[12px] text-white/50 mb-2">Add Variable</div>
        <div className="flex gap-2">
          <input
            type="text"
            placeholder="KEY"
            value={newKey}
            onChange={(e) => setNewKey(e.target.value)}
            className="flex-1 bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] font-mono text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
          />
          <input
            type="text"
            placeholder="value or ${{Service.VAR}}"
            value={newVal}
            onChange={(e) => setNewVal(e.target.value)}
            className="flex-[2] bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] font-mono text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
          />
          <button
            onClick={() => {
              if (newKey && newVal) {
                setEnvVar.mutate({ id: svc.id, key: newKey, value: newVal })
                setNewKey('')
                setNewVal('')
              }
            }}
            className="px-3 py-1.5 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[12px] hover:bg-[#8b5cf6]/25 transition-all"
          >
            Add
          </button>
        </div>
      </div>
    </div>
  )
}

// ── Metrics Tab ──────────────────────────────
function useMetricHistory(serviceId: string, maxPoints = 30) {
  const { data: metrics } = useServiceMetrics(serviceId)
  const historyRef = useRef<{ cpu: number[]; memory: number[]; networkIn: number[]; networkOut: number[] }>({
    cpu: [], memory: [], networkIn: [], networkOut: [],
  })

  useEffect(() => {
    if (!metrics) return
    const h = historyRef.current
    h.cpu.push(metrics.cpu || 0)
    h.memory.push(metrics.memory || 0)
    h.networkIn.push(metrics.networkIn || 0)
    h.networkOut.push(metrics.networkOut || 0)
    if (h.cpu.length > maxPoints) h.cpu.shift()
    if (h.memory.length > maxPoints) h.memory.shift()
    if (h.networkIn.length > maxPoints) h.networkIn.shift()
    if (h.networkOut.length > maxPoints) h.networkOut.shift()
  }, [metrics, maxPoints])

  return { current: metrics || { cpu: 0, memory: 0, networkIn: 0, networkOut: 0 }, history: historyRef.current }
}

function Sparkline({ data, color, maxVal = 100 }: { data: number[]; color: string; maxVal?: number }) {
  if (data.length === 0) {
    return <div className="h-16 bg-black/20 rounded-lg flex items-center justify-center"><span className="text-[10px] text-white/20">Collecting data...</span></div>
  }
  const padded = data.length < 2 ? [...Array(Math.max(0, 2 - data.length)).fill(0), ...data] : data
  const h = 64
  const w = 280
  const step = w / (padded.length - 1)
  const points = padded.map((v, i) => {
    const x = i * step
    const y = h - (Math.min(v, maxVal) / maxVal) * (h - 4) - 2
    return `${x},${y}`
  }).join(' ')

  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="h-16 w-full bg-black/20 rounded-lg" preserveAspectRatio="none">
      <polyline
        fill="none"
        stroke={color}
        strokeWidth={2}
        strokeLinecap="round"
        strokeLinejoin="round"
        points={points}
        opacity={0.8}
      />
      {padded.map((v, i) => (
        <circle key={i} cx={i * step} cy={h - (Math.min(v, maxVal) / maxVal) * (h - 4) - 2} r={1.5} fill={color} opacity={0.6} />
      ))}
    </svg>
  )
}

function MetricsTab({ svc }: { svc: Service }) {
  const { current: m, history } = useMetricHistory(svc.id)

  const items = [
    { label: 'CPU', value: `${m.cpu.toFixed(1)}%`, color: '#8b5cf6', data: history.cpu, max: 100 },
    { label: 'Memory', value: `${m.memory.toFixed(1)}%`, color: '#22c55e', data: history.memory, max: 100 },
    { label: 'Network In', value: `${(m.networkIn ?? 0).toFixed(1)} MB/s`, color: '#3b82f6', data: history.networkIn, max: 50 },
    { label: 'Network Out', value: `${(m.networkOut ?? 0).toFixed(1)} MB/s`, color: '#f59e0b', data: history.networkOut, max: 50 },
  ]

  return (
    <div className="p-5">
      <div className="text-[14px] font-medium text-white/70 mb-4">Metrics</div>
      <div className="grid grid-cols-2 gap-3">
        {items.map((item) => (
          <div key={item.label} className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4">
            <div className="text-[11px] text-white/40 mb-2">{item.label}</div>
            <div className="text-[20px] font-semibold" style={{ color: item.color }}>
              {item.value}
            </div>
            <div className="mt-3">
              <Sparkline data={item.data} color={item.color} maxVal={item.max} />
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

// ── Settings Tab ─────────────────────────────
function SettingsTab({ svc }: { svc: Service }) {
  const updateService = useUpdateService()
  const destroyService = useDestroyService()
  const [sTab, setSTab] = useState('builder')
  const sTabs = ['builder', 'resources', 'security', 'ssl', 'network', 'health', 'docker', 'cron', 'git', 'danger']
  const isApp = svc.type === 'app'

  const toggleField = (path: string, value: unknown) => {
    updateService.mutate({ id: svc.id, data: { [path]: value } })
  }

  return (
    <div className="flex h-full">
      <div className="w-[180px] border-r border-white/[0.06] bg-[#0f0f13] p-3 space-y-0.5 flex-shrink-0">
        {sTabs.map((t) => (
          <button
            key={t}
            onClick={() => setSTab(t)}
            className={`w-full text-left px-3 py-2 rounded-lg text-[12px] transition-all capitalize ${
              sTab === t ? 'bg-white/[0.06] text-white/70' : 'text-white/40 hover:text-white/60'
            }`}
          >
            {t === 'health' ? 'Health Checks' : t === 'docker' ? 'Docker Options' : t === 'cron' ? 'Cron Jobs' : t === 'danger' ? 'Danger Zone' : t === 'security' ? 'Security' : t === 'ssl' ? 'SSL/TLS' : t === 'network' ? 'Network' : t}
          </button>
        ))}
      </div>
      <div className="flex-1 overflow-y-auto p-5">
        {sTab === 'builder' && isApp && (
          <div className="space-y-4">
            <div className="text-[13px] font-medium text-white/70 mb-2">Builder</div>
            {['nixpacks', 'dockerfile', 'herokuish', 'pack', 'railpack'].map((b) => (
              <label
                key={b}
                className={`flex items-center gap-3 p-3 border rounded-lg cursor-pointer transition-all ${
                  svc.builder === b
                    ? 'border-[#8b5cf6]/40 bg-[#8b5cf6]/5'
                    : 'border-white/[0.06] bg-[#1a1a1e]'
                }`}
              >
                <input
                  type="radio"
                  name="builder"
                  checked={svc.builder === b}
                  onChange={() => toggleField('builder', b)}
                  className="accent-[#8b5cf6]"
                />
                <div>
                  <div className="text-[13px] text-white/70 capitalize">{b}</div>
                </div>
              </label>
            ))}
          </div>
        )}

        {sTab === 'resources' && (
          <ResourceSettings svc={svc} />
        )}

        {sTab === 'security' && <SecuritySettings svc={svc} />}
        {sTab === 'ssl' && <SSLSettings svc={svc} />}
        {sTab === 'network' && <NetworkSettings svc={svc} />}

        {sTab === 'health' && (
          <HealthSettings svc={svc} />
        )}

        {sTab === 'docker' && (
          <DockerSettings svc={svc} />
        )}

        {sTab === 'cron' && (
          <CronSettings svc={svc} />
        )}

        {sTab === 'git' && (
          <div className="space-y-3">
            <div className="text-[13px] font-medium text-white/70 mb-2">Source</div>
            <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3 space-y-3">
              <div>
                <div className="text-[11px] text-white/40 mb-1">Git Repository</div>
                <input
                  type="text"
                  value={svc.gitRepo || ''}
                  placeholder="https://github.com/user/repo"
                  onChange={(e) => toggleField('gitRepo', e.target.value)}
                  className="w-full bg-black/40 border border-white/[0.08] rounded px-2 py-1 text-[12px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
                />
              </div>
              <div>
                <div className="text-[11px] text-white/40 mb-1">Docker Image</div>
                <input
                  type="text"
                  value={svc.dockerImage || ''}
                  placeholder="nginx:alpine"
                  onChange={(e) => toggleField('dockerImage', e.target.value)}
                  className="w-full bg-black/40 border border-white/[0.08] rounded px-2 py-1 text-[12px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
                />
              </div>
              <div>
                <div className="text-[11px] text-white/40 mb-1">Deploy Branch</div>
                <input
                  type="text"
                  value={svc.git?.deployBranch || 'main'}
                  onChange={(e) => toggleField('git', { ...svc.git, deployBranch: e.target.value })}
                  className="w-full bg-black/40 border border-white/[0.08] rounded px-2 py-1 text-[12px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
                />
              </div>
            </div>
          </div>
        )}

        {sTab === 'danger' && (
          <div className="space-y-4">
            <div className="text-[13px] font-medium text-red-400 mb-2">Danger Zone</div>
            <div className="bg-red-500/5 border border-red-500/20 rounded-lg p-4 space-y-4">
              <div className="flex items-center justify-between">
                <div>
                  <div className="text-[13px] text-white/70">Destroy Service</div>
                  <div className="text-[11px] text-white/40 mt-0.5">
                    Permanently delete {svc.name} and all associated data. This cannot be undone.
                  </div>
                </div>
                <button
                  onClick={() => {
                    if (confirm(`Are you sure you want to destroy "${svc.name}"? This will also remove the Dokku app and all data. This action cannot be undone.`)) {
                      destroyService.mutate(svc.id)
                    }
                  }}
                  disabled={destroyService.isPending}
                  className="px-3 py-2 bg-red-500/15 text-red-400 rounded-lg text-[12px] font-medium hover:bg-red-500/25 transition-all disabled:opacity-50 flex items-center gap-1.5"
                >
                  <Trash2 size={13} />
                  {destroyService.isPending ? 'Destroying...' : 'Destroy'}
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

// ── Resource Settings ────────────────────────
function ResourceSettings({ svc }: { svc: Service }) {
  const updateService = useUpdateService()

  const updateLimit = (processType: string, field: string, value: string) => {
    const next = svc.resourceLimits.map((r) =>
      r.processType === processType ? { ...r, [field]: value || undefined } : r
    )
    if (!next.find((r) => r.processType === processType)) {
      next.push({ processType, [field]: value })
    }
    updateService.mutate({ id: svc.id, data: { resourceLimits: next } })
  }

  return (
    <div className="space-y-4">
      <div className="text-[13px] font-medium text-white/70 mb-2">Resource Limits</div>
      {svc.processTypes?.map((pt) => {
        const limit = svc.resourceLimits.find((r) => r.processType === pt.name) || { processType: pt.name }
        return (
          <div key={pt.name} className="bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3">
            <div className="text-[12px] font-medium text-white/70 mb-2">{pt.name}</div>
            <div className="grid grid-cols-2 gap-2">
              {[
                { key: 'cpu', label: 'CPU', placeholder: 'e.g. 0.5' },
                { key: 'memory', label: 'Memory', placeholder: 'e.g. 512m' },
                { key: 'memorySwap', label: 'Swap', placeholder: 'e.g. 512m' },
                { key: 'nvidiaGpu', label: 'NVIDIA GPU', placeholder: 'e.g. 1' },
              ].map((f) => (
                <div key={f.key}>
                  <div className="text-[11px] text-white/40">{f.label}</div>
                  <input
                    type="text"
                    value={(limit as unknown as Record<string, string>)[f.key] || ''}
                    placeholder={f.placeholder}
                    onChange={(e) => updateLimit(pt.name, f.key, e.target.value)}
                    className="w-full mt-1 bg-black/40 border border-white/[0.08] rounded px-2 py-1 text-[12px] font-mono text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
                  />
                </div>
              ))}
            </div>
          </div>
        )
      }) || <div className="text-[12px] text-white/30">No process types configured</div>}
    </div>
  )
}

// ── Health Settings ──────────────────────────
function HealthSettings({ svc }: { svc: Service }) {
  const updateService = useUpdateService()
  const checks = svc.checks || { enabled: false, wait: 5, timeout: 30, skipList: [] }

  const updateChecks = (patch: Partial<typeof checks>) => {
    updateService.mutate({ id: svc.id, data: { checks: { ...checks, ...patch } } })
  }

  return (
    <div className="space-y-3">
      <div className="text-[13px] font-medium text-white/70 mb-2">Health Checks</div>
      <div className="flex items-center justify-between bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3">
        <div className="text-[12px] text-white/60">Zero-Downtime Checks</div>
        <AccessibleToggle
          checked={checks.enabled}
          onChange={(v) => updateChecks({ enabled: v })}
          label="Zero-downtime checks enabled"
        />
      </div>
      <div className="grid grid-cols-2 gap-3">
        <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3">
          <div className="text-[11px] text-white/40 mb-1">Wait (seconds)</div>
          <input
            type="number"
            value={checks.wait}
            onChange={(e) => updateChecks({ wait: parseInt(e.target.value) || 0 })}
            className="w-full bg-black/40 border border-white/[0.08] rounded px-2 py-1 text-[12px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
          />
        </div>
        <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3">
          <div className="text-[11px] text-white/40 mb-1">Timeout (seconds)</div>
          <input
            type="number"
            value={checks.timeout}
            onChange={(e) => updateChecks({ timeout: parseInt(e.target.value) || 0 })}
            className="w-full bg-black/40 border border-white/[0.08] rounded px-2 py-1 text-[12px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
          />
        </div>
      </div>
    </div>
  )
}

// ── Docker Settings ──────────────────────────
function DockerSettings({ svc }: { svc: Service }) {
  const updateService = useUpdateService()
  const [newPhase, setNewPhase] = useState<'build' | 'deploy' | 'run'>('run')
  const [newOption, setNewOption] = useState('')

  const options = svc.dockerOptions || []

  const addOption = () => {
    if (!newOption.trim()) return
    updateService.mutate({
      id: svc.id,
      data: { dockerOptions: [...options, { phase: newPhase, option: newOption.trim() }] },
    })
    setNewOption('')
  }

  const removeOption = (idx: number) => {
    updateService.mutate({
      id: svc.id,
      data: { dockerOptions: options.filter((_, i) => i !== idx) },
    })
  }

  return (
    <div className="space-y-3">
      <div className="text-[13px] font-medium text-white/70 mb-2">Docker Options</div>
      {options.length > 0 ? (
        <div className="space-y-2">
          {options.map((opt, i) => (
            <div key={i} className="flex items-center gap-2 bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-2.5 group">
              <span className="text-[10px] px-1.5 py-0.5 bg-white/[0.06] text-white/40 rounded uppercase">{opt.phase}</span>
              <span className="text-[12px] text-white/60 font-mono flex-1 truncate">{opt.option}</span>
              <button
                onClick={() => removeOption(i)}
                className="p-1 hover:bg-white/[0.06] rounded text-white/20 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity"
              >
                <Trash2 size={12} />
              </button>
            </div>
          ))}
        </div>
      ) : (
        <div className="text-[12px] text-white/30 py-2">No docker options configured</div>
      )}
      <div className="flex gap-2 mt-2">
        <select
          value={newPhase}
          onChange={(e) => setNewPhase(e.target.value as 'build' | 'deploy' | 'run')}
          className="bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
        >
          <option value="build">build</option>
          <option value="deploy">deploy</option>
          <option value="run">run</option>
        </select>
        <input
          type="text"
          placeholder="--add-host=host.docker.internal:host-gateway"
          value={newOption}
          onChange={(e) => setNewOption(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && addOption()}
          className="flex-1 bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] font-mono text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
        />
        <button
          onClick={addOption}
          className="px-3 py-1.5 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[12px] hover:bg-[#8b5cf6]/25 transition-all"
        >
          Add
        </button>
      </div>
    </div>
  )
}


// ── Cron Settings ────────────────────────────
function CronSettings({ svc }: { svc: Service }) {
  const updateService = useUpdateService()
  const [schedule, setSchedule] = useState('')
  const [command, setCommand] = useState('')

  const jobs = svc.config?.cron || []

  const addJob = () => {
    if (!schedule.trim() || !command.trim()) return
    const next = [...jobs, { schedule: schedule.trim(), command: command.trim() }]
    updateService.mutate({
      id: svc.id,
      data: { config: { ...svc.config, cron: next } },
    })
    setSchedule('')
    setCommand('')
  }

  const removeJob = (idx: number) => {
    const next = jobs.filter((_j: typeof jobs[0], i: number) => i !== idx)
    updateService.mutate({
      id: svc.id,
      data: { config: { ...svc.config, cron: next } },
    })
  }

  return (
    <div className="space-y-3">
      <div className="text-[13px] font-medium text-white/70 mb-2">Cron Jobs</div>
      {jobs.length > 0 ? (
        <div className="space-y-2">
          {jobs.map((job: { schedule: string; command: string }, i: number) => (
            <div key={i} className="flex items-center gap-2 bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-2.5 group">
              <span className="text-[10px] px-1.5 py-0.5 bg-[#8b5cf6]/10 text-[#8b5cf6] rounded font-mono">{job.schedule}</span>
              <span className="text-[12px] text-white/60 font-mono flex-1 truncate">{job.command}</span>
              <button
                onClick={() => removeJob(i)}
                className="p-1 hover:bg-white/[0.06] rounded text-white/20 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity"
              >
                <Trash2 size={12} />
              </button>
            </div>
          ))}
        </div>
      ) : (
        <div className="text-[12px] text-white/30 py-2">No cron jobs configured</div>
      )}
      <div className="flex gap-2 mt-2">
        <input
          type="text"
          placeholder="*/5 * * * *"
          value={schedule}
          onChange={(e) => setSchedule(e.target.value)}
          className="w-32 bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] font-mono text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
        />
        <input
          type="text"
          placeholder="rake tasks:run"
          value={command}
          onChange={(e) => setCommand(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && addJob()}
          className="flex-1 bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] font-mono text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
        />
        <button
          onClick={addJob}
          className="px-3 py-1.5 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[12px] hover:bg-[#8b5cf6]/25 transition-all"
        >
          Add
        </button>
      </div>
    </div>
  )
}


// ── Domains Tab ──────────────────────────────
function DomainsTab({ svc }: { svc: Service }) {
  const addDomain = useAddDomain()
  const removeDomain = useRemoveDomain()
  const [newDomain, setNewDomain] = useState('')

  return (
    <div className="p-5 space-y-4">
      <div className="text-[14px] font-medium text-white/70 mb-2">Domains</div>
      {svc.domains.length > 0 ? (
        <div className="space-y-2">
          {svc.domains.map((d) => (
            <div
              key={d.hostname}
              className="flex items-center gap-3 bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3 group"
            >
              <Globe size={15} className="text-white/30" />
              <span className="text-[13px] text-white/70">{d.hostname}</span>
              {d.ssl && (
                <span className="text-[10px] px-1.5 bg-[#22c55e]/10 text-[#22c55e] rounded-full">SSL</span>
              )}
              <button
                onClick={() => removeDomain.mutate({ id: svc.id, hostname: d.hostname })}
                className="ml-auto p-1.5 hover:bg-white/[0.06] rounded text-white/20 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity"
              >
                <Trash2 size={12} />
              </button>
            </div>
          ))}
        </div>
      ) : (
        <div className="text-[13px] text-white/30 py-4 text-center">No domains configured</div>
      )}
      <div className="flex gap-2 mt-3">
        <input
          type="text"
          placeholder="example.com"
          value={newDomain}
          onChange={(e) => setNewDomain(e.target.value)}
          className="flex-1 bg-black/40 border border-white/[0.08] rounded-lg px-3 py-2 text-[13px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
        />
        <button
          onClick={() => {
            if (newDomain) {
              addDomain.mutate({ id: svc.id, hostname: newDomain, port: 443 })
              setNewDomain('')
            }
          }}
          className="px-4 py-2 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[13px] hover:bg-[#8b5cf6]/25 transition-all"
        >
          Add
        </button>
      </div>
    </div>
  )
}

// ── Storage Tab ──────────────────────────────
function StorageTab({ svc }: { svc: Service }) {
  const addStorage = useAddStorageMount()
  const removeStorage = useRemoveStorageMount()
  const [newHostPath, setNewHostPath] = useState('')
  const [newContainerPath, setNewContainerPath] = useState('')

  return (
    <div className="p-5 space-y-4">
      <div className="text-[14px] font-medium text-white/70 mb-2">Storage Mounts</div>
      {svc.storageMounts.length > 0 ? (
        <div className="space-y-2">
          {svc.storageMounts.map((sm) => (
            <div
              key={sm.hostPath}
              className="flex items-center gap-3 bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3 group"
            >
              <HardDrive size={15} className="text-white/30" />
              <div className="text-[12px] text-white/50 font-mono">
                {sm.hostPath} → {sm.containerPath}
              </div>
              <button
                onClick={() => removeStorage.mutate({ id: svc.id, hostPath: sm.hostPath })}
                className="ml-auto p-1.5 hover:bg-white/[0.06] rounded text-white/20 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity"
              >
                <Trash2 size={12} />
              </button>
            </div>
          ))}
        </div>
      ) : (
        <div className="text-[13px] text-white/30 py-4 text-center">No storage mounts configured</div>
      )}
      <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3 space-y-2">
        <div className="text-[12px] text-white/50 mb-1">Add Mount</div>
        <div className="flex gap-2">
          <input
            type="text"
            placeholder="/var/lib/dokku/data/storage/..."
            value={newHostPath}
            onChange={(e) => setNewHostPath(e.target.value)}
            className="flex-1 bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] font-mono text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
          />
          <input
            type="text"
            placeholder="/app/data"
            value={newContainerPath}
            onChange={(e) => setNewContainerPath(e.target.value)}
            className="flex-1 bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] font-mono text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
          />
          <button
            onClick={() => {
              if (newHostPath && newContainerPath) {
                addStorage.mutate({ id: svc.id, hostPath: newHostPath, containerPath: newContainerPath })
                setNewHostPath('')
                setNewContainerPath('')
              }
            }}
            className="px-3 py-1.5 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[12px] hover:bg-[#8b5cf6]/25 transition-all"
          >
            Add
          </button>
        </div>
      </div>
    </div>
  )
}

// ── Security Settings ───────────────────────
function SecuritySettings({ svc }: { svc: Service }) {
  const updateService = useUpdateService()
  const [isLocked, setIsLocked] = useState(svc.locked || false)
  const [loading, setLoading] = useState(false)

  const toggleLock = async () => {
    setLoading(true)
    try {
      const newLocked = !isLocked
      if (newLocked) {
        await api.services.app_lock(svc.id)
      } else {
        await api.services.app_unlock(svc.id)
      }
      setIsLocked(newLocked)
      updateService.mutate({ id: svc.id, data: { locked: newLocked } })
    } catch (err) {
      console.error('Failed to toggle lock:', err)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="space-y-4">
      <div className="text-[13px] font-medium text-white/70 mb-2">Security</div>
      <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-4">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-[13px] text-white/70">App Lock</div>
            <div className="text-[11px] text-white/40 mt-0.5">
              Prevent deployments when locked. Use during maintenance or migrations.
            </div>
          </div>
          <button
            onClick={toggleLock}
            disabled={loading}
            className={`flex items-center gap-2 px-3 py-2 rounded-lg text-[12px] font-medium transition-all disabled:opacity-50 ${
              isLocked
                ? 'bg-amber-500/15 text-amber-400 hover:bg-amber-500/25'
                : 'bg-white/5 text-white/50 hover:bg-white/10 hover:text-white/70'
            }`}
          >
            {loading ? (
              <Loader2 size={13} className="animate-spin" />
            ) : isLocked ? (
              '🔒 Locked'
            ) : (
              '🔓 Unlocked'
            )}
          </button>
        </div>
        {isLocked && (
          <div className="mt-3 text-[11px] text-amber-400/60 bg-amber-500/5 rounded-lg p-2">
            App is locked. Deployments and rebuilds are blocked.
          </div>
        )}
      </div>
    </div>
  )
}

// ── SSL/TLS Settings ─────────────────────────
function SSLSettings({ svc }: { svc: Service }) {
  const letsencrypt = svc.letsencrypt || { enabled: false, email: '', staging: false, autoRenew: true }

  return (
    <div className="space-y-4">
      <div className="text-[13px] font-medium text-white/70 mb-2">SSL/TLS</div>
      {svc.domains.filter((d) => d.ssl).length > 0 ? (
        <div className="space-y-3">
          <div className="text-[11px] text-white/40 mb-2">Configured Certificates</div>
          {svc.domains.filter((d) => d.ssl).map((d) => (
            <div key={d.hostname} className="bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3">
              <div className="flex items-center gap-2">
                <span className="text-[12px] text-white/70">{d.hostname}</span>
                <span className="text-[10px] px-1.5 py-0.5 bg-[#22c55e]/10 text-[#22c55e] rounded-full">SSL</span>
                {d.letsencrypt && (
                  <span className="text-[10px] px-1.5 py-0.5 bg-[#8b5cf6]/10 text-[#8b5cf6] rounded-full">Let's Encrypt</span>
                )}
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-4 text-center">
          <div className="text-[12px] text-white/40">No SSL certificates configured</div>
          <div className="text-[11px] text-white/30 mt-1">Add a domain and enable SSL to secure connections</div>
        </div>
      )}

      <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-4">
        <div className="flex items-center justify-between mb-3">
          <div className="text-[12px] text-white/60">Let's Encrypt</div>
          <span className={`text-[10px] px-2 py-0.5 rounded-full ${
            letsencrypt.enabled ? 'bg-[#22c55e]/10 text-[#22c55e]' : 'bg-white/5 text-white/40'
          }`}>
            {letsencrypt.enabled ? 'Enabled' : 'Disabled'}
          </span>
        </div>
        {letsencrypt.enabled && (
          <div className="space-y-2 text-[11px] text-white/40">
            <div>Email: {letsencrypt.email || 'not set'}</div>
            <div>Auto-renew: {letsencrypt.autoRenew ? 'Yes' : 'No'}</div>
            <div>Staging: {letsencrypt.staging ? 'Yes' : 'No'}</div>
            {letsencrypt.lastIssued && <div>Last issued: {letsencrypt.lastIssued}</div>}
            {letsencrypt.expiryDate && <div>Expires: {letsencrypt.expiryDate}</div>}
          </div>
        )}
      </div>
    </div>
  )
}

// ── Network Settings ─────────────────────────
function NetworkSettings({ svc }: { svc: Service }) {
  return (
    <div className="space-y-4">
      <div className="text-[13px] font-medium text-white/70 mb-2">Networking</div>
      <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-4">
        <div className="text-[11px] text-white/40 mb-2">Proxy Type</div>
        <div className="flex items-center gap-2">
          <span className="text-[12px] text-white/70 capitalize">{svc.proxy?.proxyType || 'traefik'}</span>
          <span className="text-[10px] px-1.5 py-0.5 bg-white/5 text-white/40 rounded">
            {svc.proxy?.enabled !== false ? 'enabled' : 'disabled'}
          </span>
        </div>
      </div>

      {svc.proxy?.portMappings && svc.proxy.portMappings.length > 0 && (
        <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-4">
          <div className="text-[11px] text-white/40 mb-2">Port Mappings</div>
          <div className="space-y-2">
            {svc.proxy.portMappings.map((pm, i) => (
              <div key={i} className="flex items-center gap-3 text-[12px]">
                <span className="text-white/50">{pm.scheme}://</span>
                <span className="text-white/70 font-mono">{pm.hostPort}</span>
                <ArrowRight size={12} className="text-white/20" />
                <span className="text-white/70 font-mono">{pm.containerPort}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-4">
        <div className="flex items-center justify-between mb-2">
          <div className="text-[12px] text-white/60">Linked Services</div>
          <span className="text-[10px] px-2 py-0.5 bg-white/5 text-white/40 rounded">
            {svc.linkedServiceIds.length}
          </span>
        </div>
        {svc.linkedServiceIds.length > 0 ? (
          <div className="text-[11px] text-white/40">
            {svc.linkedServiceIds.join(', ')}
          </div>
        ) : (
          <div className="text-[11px] text-white/30">No linked services</div>
        )}
      </div>
    </div>
  )
}
