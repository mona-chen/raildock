import { useState, useEffect, useRef, useMemo } from 'react'
import { Box, X, ArrowDownToLine, Trash2, Globe, HardDrive, Play, Square, RotateCw, Rocket, ChevronDown, ChevronRight, Terminal, GitBranch, Settings2, Wrench } from 'lucide-react'
import AccessibleToggle from '@/features/shared/AccessibleToggle'
import { useService, useScaleProcess, useSetEnvVar, useUnsetEnvVar, useServiceMetrics, useServiceDeployments, useAddDomain, useRemoveDomain, useAddStorageMount, useRemoveStorageMount, useBackupService, useRestoreService, useRollbackService, useContainerStatus, useDeployService, useStartService, useStopService, useRestartService, useRebuildService, useDeployment, useDestroyService } from '@/hooks/useServices'
import { useServiceLogs } from '@/hooks/useServices'
import { useWebSocketLogs } from '@/hooks/useWebSocketLogs'
import { useWebSocketDeployments } from '@/hooks/useWebSocketDeployments'
import { useUpdateService } from '@/hooks/useServices'
import { useCanvasStore } from '@/stores/useCanvasStore'
import type { Service } from '@/types'

const SVC_ICON: Record<string, React.ElementType> = {
  web: () => null, worker: Box, postgres: () => null, redis: () => null,
  mysql: () => null, mongo: () => null, rabbitmq: () => null, clock: Box,
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
  const { data: svc } = useService(serviceId)
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

  if (!svc) return null

  const db = svc.type === 'database'
  const tabs = db
    ? ['overview', 'logs', 'database', 'backups', 'variables', 'metrics', 'settings']
    : ['overview', 'deploy', 'logs', 'variables', 'domains', 'storage', 'metrics', 'settings']

  const Icon = SVC_ICON[svc.subtype] || Box
  const color = SVC_CLR[svc.subtype] || '#A0A0B0'

  return (
    <div data-service-panel className="absolute right-0 top-0 bottom-0 w-[800px] bg-[#131318] border-l border-white/[0.06] flex flex-col z-50 shadow-2xl shadow-black/40" onWheel={(e) => e.stopPropagation()} onMouseDown={(e) => e.stopPropagation()}>
      {/* Header */}
      <div className="flex items-center justify-between px-5 py-3 border-b border-white/[0.06] flex-shrink-0">
        <div className="flex items-center gap-3">
          <button
            onClick={onClose}
            className="w-7 h-7 rounded-lg bg-white/[0.06] flex items-center justify-center hover:bg-white/[0.1]"
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
            <button
              onClick={handleDeploy}
              disabled={deployService.isPending}
              title="Deploy"
              className="flex items-center gap-1 px-2.5 py-1.5 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[11px] hover:bg-[#8b5cf6]/25 transition-all disabled:opacity-50"
            >
              <Rocket size={12} />
              {deployService.isPending ? '...' : 'Deploy'}
            </button>
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
        {tab === 'database' && db && <DatabaseTab svc={svc} />}
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
          <button
            onClick={onDeploy}
            disabled={deployService.isPending}
            className="flex items-center gap-1.5 px-3 py-2 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[12px] font-medium hover:bg-[#8b5cf6]/25 transition-all disabled:opacity-50"
          >
            <Rocket size={13} />
            {deployService.isPending ? 'Deploying...' : 'Deploy'}
          </button>
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

// ── Logs Tab ─────────────────────────────────
function LogsTab({ serviceId }: { serviceId: string }) {
  const { data: historicalLogs } = useServiceLogs(serviceId)
  const { lines: liveLines, isConnected, clear } = useWebSocketLogs(serviceId)
  const scrollRef = useRef<HTMLDivElement>(null)
  const [hasCleared, setHasCleared] = useState(false)

  // Build the full log list: historical first, then live additions
  const allLines = useMemo(() => {
    if (hasCleared) return liveLines
    const historical = (historicalLogs || []).map((l) => ({
      timestamp: l.timestamp,
      process_type: l.processType,
      message: l.message,
    }))
    return [...historical, ...liveLines]
  }, [historicalLogs, liveLines, hasCleared])

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight
    }
  }, [allLines.length])

  const handleClear = () => {
    clear()
    setHasCleared(true)
  }

  return (
    <div className="flex flex-col h-full">
      <div className="flex items-center justify-between px-5 py-2 border-b border-white/[0.06] flex-shrink-0">
        <div className="flex items-center gap-2">
          <span className={`w-2 h-2 rounded-full ${isConnected ? 'bg-[#22c55e]' : 'bg-white/20'}`} />
          <span className="text-[11px] text-white/40">{isConnected ? 'Live' : 'Polling'}</span>
        </div>
        <button
          onClick={handleClear}
          className="text-[11px] text-white/30 hover:text-white/60 transition-colors"
        >
          Clear
        </button>
      </div>
      <div ref={scrollRef} className="flex-1 overflow-y-auto p-4 font-mono text-[12px] space-y-1">
        {allLines.length > 0 ? (
          allLines.map((line, i) => (
            <div key={i} className="text-white/60">
              <span className="text-white/20 mr-2">{new Date(line.timestamp).toLocaleTimeString()}</span>
              <span className="text-[#8b5cf6]/60 mr-2">[{line.process_type}]</span>
              <span>{line.message}</span>
            </div>
          ))
        ) : (
          <div className="text-white/20 text-center py-10">Waiting for logs...</div>
        )}
      </div>
    </div>
  )
}

// ── Database Tab ─────────────────────────────
function DatabaseTab({ svc }: { svc: Service }) {
  const [subTab, setSubTab] = useState('config')
  const subTabs = ['config']
  const dbUrl = svc.envVars.find((e) => e.key.includes('URL') || e.key.includes('DATABASE') || e.key.includes('REDIS'))

  return (
    <div className="p-5 space-y-4">
      <div className="flex border-b border-white/[0.06] mb-4">
        {subTabs.map((t) => (
          <button
            key={t}
            onClick={() => setSubTab(t)}
            className={`px-3 py-2 text-[12px] border-b-2 transition-all capitalize ${
              subTab === t
                ? 'border-[#8b5cf6] text-[#8b5cf6]'
                : 'border-transparent text-white/40 hover:text-white/60'
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      {subTab === 'config' && (
        <div className="space-y-4">
          <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4">
            <div className="text-[13px] font-medium text-white/70 mb-2">Connection</div>
            {dbUrl ? (
              <div className="bg-black/20 rounded-lg p-3 mb-3">
                <div className="text-[11px] text-white/40 mb-1">{dbUrl.key}</div>
                <div className="text-[12px] text-white/70 font-mono break-all">{dbUrl.value}</div>
              </div>
            ) : (
              <div className="text-[12px] text-white/30 mb-3">No connection URL configured</div>
            )}
            <div className="grid grid-cols-2 gap-3">
              {[
                { l: 'Type', v: svc.subtype },
                { l: 'Version', v: svc.version || 'latest' },
                { l: 'Name', v: svc.name },
                { l: 'Status', v: svc.status },
              ].map((f) => (
                <div key={f.l} className="bg-black/20 rounded-lg p-2.5">
                  <div className="text-[11px] text-white/40">{f.l}</div>
                  <div className="text-[12px] text-white/70 font-mono mt-0.5">{f.v}</div>
                </div>
              ))}
            </div>
          </div>

          <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4">
            <div className="text-[13px] font-medium text-white/70 mb-2">Database Management</div>
            <p className="text-[12px] text-white/40 mb-3">
              Query interface and table introspection require SSH access to the Dokku host.
            </p>
            <div className="text-[11px] text-white/30">
              Connect a server in project settings to enable database querying, backup management, and performance metrics.
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

// ── Backups Tab ──────────────────────────────
function BackupsTab({ svc, serviceId }: { svc: Service; serviceId: string }) {
  const backupService = useBackupService()
  const restoreService = useRestoreService()

  return (
    <div className="p-5">
      <div className="flex items-center justify-between mb-4">
        <div>
          <div className="text-[14px] font-medium text-white/70">Backups</div>
          <div className="text-[12px] text-white/40 mt-0.5">
            {svc.backups.length} backup(s) available
          </div>
        </div>
        <button
          onClick={() => backupService.mutate(serviceId)}
          disabled={backupService.isPending}
          className="flex items-center gap-1.5 px-3 py-2 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[12px] hover:bg-[#8b5cf6]/25 transition-all disabled:opacity-50"
        >
          <ArrowDownToLine size={13} /> {backupService.isPending ? 'Creating...' : 'Create Backup'}
        </button>
      </div>
      {svc.backups.length > 0 ? (
        <div className="space-y-2">
          {svc.backups.map((b) => (
            <div
              key={b.id}
              className="flex items-center gap-3 bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3"
            >
              <div className="flex-1">
                <div className="text-[13px] text-white/70">Backup {b.id}</div>
                <div className="text-[11px] text-white/40">{new Date(b.createdAt).toLocaleString()}</div>
              </div>
              <span className="text-[11px] px-2 py-0.5 bg-[#22c55e]/10 text-[#22c55e] rounded-full">{b.status}</span>
              <span className="text-[12px] text-white/50 font-mono">{b.size}</span>
              <button className="p-1.5 hover:bg-white/[0.06] rounded text-white/30 hover:text-white/60">
                <ArrowDownToLine size={13} />
              </button>
              <button className="p-1.5 hover:bg-white/[0.06] rounded text-white/30 hover:text-red-400">
                <Trash2 size={13} />
              </button>
            </div>
          ))}
        </div>
      ) : (
        <div className="text-center py-12 text-[13px] text-white/30">
          No backups yet. Create your first backup to protect your data.
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
function MetricsTab({ svc }: { svc: Service }) {
  const { data: metrics } = useServiceMetrics(svc.id)
  const m = metrics || { cpu: 0, memory: 0, networkIn: 0, networkOut: 0 }

  const items = [
    { label: 'CPU', value: `${m.cpu.toFixed(1)}%`, color: '#8b5cf6', pct: Math.min(m.cpu, 100) },
    { label: 'Memory', value: `${m.memory.toFixed(1)}%`, color: '#22c55e', pct: Math.min(m.memory, 100) },
    { label: 'Network In', value: `${(m.networkIn ?? 0).toFixed(1)} MB/s`, color: '#3b82f6', pct: Math.min((m.networkIn ?? 0) / 10, 100) },
    { label: 'Network Out', value: `${(m.networkOut ?? 0).toFixed(1)} MB/s`, color: '#f59e0b', pct: Math.min((m.networkOut ?? 0) / 10, 100) },
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
            <div className="mt-3 h-16 bg-black/20 rounded-lg flex items-end gap-0.5 p-1">
              {Array.from({ length: 20 }, (_, i) => (
                <div
                  key={i}
                  className="flex-1 rounded-sm transition-all"
                  style={{
                    height: `${i === 19 ? item.pct : Math.max(4, item.pct * (0.5 + (i % 7) / 12))}%`,
                    backgroundColor: item.color,
                    opacity: 0.3 + (i / 20) * 0.4,
                  }}
                />
              ))}
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
  const sTabs = ['builder', 'resources', 'health', 'docker', 'cron', 'git', 'danger']
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
            {t === 'health' ? 'Health Checks' : t === 'docker' ? 'Docker Options' : t === 'cron' ? 'Cron Jobs' : t === 'danger' ? 'Danger Zone' : t}
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

// ── Network Settings (Domains + Storage CRUD) ──
function NetworkSettings({ svc }: { svc: Service }) {
  const updateService = useUpdateService()
  const addDomain = useAddDomain()
  const removeDomain = useRemoveDomain()
  const addStorage = useAddStorageMount()
  const removeStorage = useRemoveStorageMount()
  const [newDomain, setNewDomain] = useState('')
  const [newHostPath, setNewHostPath] = useState('')
  const [newContainerPath, setNewContainerPath] = useState('')

  const nginx = svc.nginx || { clientMaxBodySize: '', readTimeout: '', keepaliveTimeout: '', hsts: false, hstsMaxAge: 31536000, hstsIncludeSubdomains: false, hstsPreload: false, bindAddressIpv4: '0.0.0.0', bindAddressIpv6: '::' }
  const le = svc.letsencrypt || { enabled: false, email: '', staging: false, autoRenew: true }

  const toggleField = (path: string, value: unknown) => {
    updateService.mutate({ id: svc.id, data: { [path]: value } })
  }

  const updateNginx = (patch: Partial<typeof nginx>) => {
    toggleField('nginx', { ...nginx, ...patch })
  }

  const updateLE = (patch: Partial<typeof le>) => {
    toggleField('letsencrypt', { ...le, ...patch })
  }

  return (
    <div className="space-y-4">
      <div>
        <div className="text-[13px] font-medium text-white/70 mb-2">Proxy</div>
        <div className="flex items-center justify-between bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3 mb-2">
          <div className="text-[12px] text-white/60">Proxy Enabled</div>
          <AccessibleToggle
            checked={svc.proxy.enabled}
            onChange={(v) => toggleField('proxy', { ...svc.proxy, enabled: v })}
            label="Proxy enabled"
          />
        </div>
        <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3 mb-2">
          <div className="flex items-center justify-between">
            <div>
              <div className="text-[11px] text-white/40">Proxy Type</div>
              <div className="text-[12px] text-white/60 capitalize mt-0.5">{svc.proxy.proxyType}</div>
            </div>
            <span className="text-[10px] px-2 py-0.5 bg-white/[0.04] text-white/30 rounded-full">server-level</span>
          </div>
        </div>
      </div>

      <div>
        <div className="text-[13px] font-medium text-white/70 mb-2">Nginx Settings</div>
        <div className="grid grid-cols-2 gap-2 mb-2">
          {[
            { key: 'clientMaxBodySize', label: 'Max Body Size', placeholder: 'e.g. 50m' },
            { key: 'readTimeout', label: 'Read Timeout', placeholder: 'e.g. 60s' },
            { key: 'keepaliveTimeout', label: 'Keepalive Timeout', placeholder: 'e.g. 60s' },
          ].map((f) => (
            <div key={f.key} className="bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-2.5">
              <div className="text-[11px] text-white/40 mb-1">{f.label}</div>
              <input
                type="text"
                value={(nginx as unknown as Record<string, string>)[f.key] || ''}
                placeholder={f.placeholder}
                onChange={(e) => updateNginx({ [f.key]: e.target.value })}
                className="w-full bg-black/40 border border-white/[0.08] rounded px-2 py-1 text-[12px] font-mono text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
              />
            </div>
          ))}
        </div>
        <div className="flex items-center justify-between bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3">
          <div className="text-[12px] text-white/60">HSTS</div>
          <AccessibleToggle
            checked={nginx.hsts}
            onChange={(v) => updateNginx({ hsts: v })}
            label="HSTS enabled"
          />
        </div>
      </div>

      <div>
        <div className="text-[13px] font-medium text-white/70 mb-2">Let's Encrypt SSL</div>
        <div className="flex items-center justify-between bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3 mb-2">
          <div className="text-[12px] text-white/60">Auto SSL</div>
          <AccessibleToggle
            checked={le.enabled}
            onChange={(v) => updateLE({ enabled: v })}
            label="Let's Encrypt enabled"
          />
        </div>
        {le.enabled && (
          <div className="space-y-2">
            <input
              type="email"
              value={le.email}
              placeholder="admin@example.com"
              onChange={(e) => updateLE({ email: e.target.value })}
              className="w-full bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
            />
            <div className="flex items-center justify-between bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3">
              <div className="text-[12px] text-white/60">Staging Mode</div>
              <AccessibleToggle
                checked={le.staging}
                onChange={(v) => updateLE({ staging: v })}
                label="Use Let's Encrypt staging"
              />
            </div>
            <div className="flex items-center justify-between bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3">
              <div className="text-[12px] text-white/60">Auto Renew</div>
              <AccessibleToggle
                checked={le.autoRenew}
                onChange={(v) => updateLE({ autoRenew: v })}
                label="Auto renew certificates"
              />
            </div>
          </div>
        )}
      </div>

      <div>
        <div className="text-[13px] font-medium text-white/70 mb-2">Domains</div>
        {svc.domains.length > 0 ? (
          svc.domains.map((d) => (
            <div
              key={d.hostname}
              className="flex items-center gap-2 bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-2.5 mb-1.5 group"
            >
              <Globe size={13} className="text-white/30" />
              <span className="text-[12px] text-white/70">{d.hostname}</span>
              {d.ssl && (
                <span className="text-[10px] px-1.5 bg-[#22c55e]/10 text-[#22c55e] rounded-full">
                  SSL
                </span>
              )}
              <button
                onClick={() => removeDomain.mutate({ id: svc.id, hostname: d.hostname })}
                className="ml-auto p-1 hover:bg-white/[0.06] rounded text-white/20 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity"
              >
                <Trash2 size={12} />
              </button>
            </div>
          ))
        ) : (
          <div className="text-[12px] text-white/30 py-2">No domains configured</div>
        )}
        <div className="flex gap-2 mt-2">
          <input
            type="text"
            placeholder="example.com"
            value={newDomain}
            onChange={(e) => setNewDomain(e.target.value)}
            className="flex-1 bg-black/40 border border-white/[0.08] rounded px-2 py-1.5 text-[12px] text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
          />
          <button
            onClick={() => {
              if (newDomain) {
                addDomain.mutate({ id: svc.id, hostname: newDomain, port: 443 })
                setNewDomain('')
              }
            }}
            className="px-3 py-1.5 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[12px] hover:bg-[#8b5cf6]/25 transition-all"
          >
            Add
          </button>
        </div>
      </div>

      <div>
        <div className="text-[13px] font-medium text-white/70 mb-2">Storage Mounts</div>
        {svc.storageMounts.length > 0 ? (
          svc.storageMounts.map((sm) => (
            <div
              key={sm.hostPath}
              className="flex items-center gap-2 bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-2.5 mb-1.5 group"
            >
              <HardDrive size={13} className="text-white/30" />
              <div className="text-[11px] text-white/50 font-mono">
                {sm.hostPath} → {sm.containerPath}
              </div>
              <button
                onClick={() => removeStorage.mutate({ id: svc.id, hostPath: sm.hostPath })}
                className="ml-auto p-1 hover:bg-white/[0.06] rounded text-white/20 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity"
              >
                <Trash2 size={12} />
              </button>
            </div>
          ))
        ) : (
          <div className="text-[12px] text-white/30 py-2">No storage mounts</div>
        )}
        <div className="flex gap-2 mt-2">
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
