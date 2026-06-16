import { useState, useEffect, useRef, useMemo } from 'react'
import { ChevronDown, ChevronRight, Terminal, Copy, Check, AlertTriangle, Link2, RotateCcw, ClipboardCopy, WrapText, Maximize2, Minimize2, Download } from 'lucide-react'
import {
  useScaleProcess,
  useRollbackService,
  useServiceDeployments,
  useContainerStatus,
  useDeployment,
  useCancelDeployment,
} from '@/hooks/useServices'
import { useCopy } from '@/hooks/useCopy'
import { useWebSocketDeployments } from '@/hooks/useWebSocketDeployments'
import type { Service } from '@/types'
import { toast } from 'sonner'
import { copyToClipboard } from '@/lib/clipboard'

function stripAnsi(str: string): string {
  // eslint-disable-next-line no-control-regex
  return str.replace(/\x1B\[[0-9;]*m/g, '')
}

function timeAgo(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime()
  const sec = Math.floor(diff / 1000)
  if (sec < 1) return 'now'
  if (sec < 60) return `${sec}s ago`
  const min = Math.floor(sec / 60)
  if (min < 60) return `${min}m ago`
  const hr = Math.floor(min / 60)
  if (hr < 24) return `${hr}h ago`
  return `${Math.floor(hr / 24)}d ago`
}

function DeploymentLogPanel({ deploymentId, liveLog }: { deploymentId: string; liveLog?: string }) {
  const { data: deployment, isLoading } = useDeployment(deploymentId)
  const logRef = useRef<HTMLDivElement>(null)
  const [wrapLines, setWrapLines] = useState(false)
  const [isExpanded, setIsExpanded] = useState(false)
  const [copiedAll, setCopiedAll] = useState(false)

  const logText = liveLog || deployment?.deployLog || deployment?.buildLog || ''
  const cleanText = useMemo(() => stripAnsi(logText), [logText])
  const lines = useMemo(() => cleanText.split('\n'), [cleanText])

  useEffect(() => {
    if (logRef.current) {
      logRef.current.scrollTop = logRef.current.scrollHeight
    }
  }, [cleanText])

  const handleCopyAll = async () => {
    const success = await copyToClipboard(cleanText)
    if (success) {
      setCopiedAll(true)
      setTimeout(() => setCopiedAll(false), 1500)
    }
  }

  const handleExport = () => {
    const blob = new Blob([cleanText], { type: 'text/plain' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `deploy-${deploymentId}-${new Date().toISOString()}.log`
    a.click()
    URL.revokeObjectURL(url)
  }

  if (isLoading && !liveLog) {
    return (
      <div className="ml-6 bg-[#131318] border border-white/[0.06] rounded-xl p-4">
        <div className="text-[12px] text-white/30">Loading logs...</div>
      </div>
    )
  }

  const logView = (
    <div className={`flex flex-col bg-[#131318] ${isExpanded ? 'fixed inset-0 z-[100]' : 'rounded-xl border border-white/[0.06] overflow-hidden'}`}>
      {/* Toolbar */}
      <div className="flex items-center justify-between px-4 py-2 border-b border-white/[0.06] flex-shrink-0">
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-1.5">
            <Terminal size={12} className="text-white/30" />
            <span className="text-[11px] text-white/40">Deployment Log</span>
          </div>
          <span className="text-[10px] text-white/20">{lines.length.toLocaleString()} lines</span>
        </div>
        <div className="flex items-center gap-1">
          {isExpanded && (
            <>
              <button
                type="button"
                onClick={() => setIsExpanded(false)}
                className="flex items-center gap-1 px-2 py-1 rounded bg-white/[0.06] text-white/50 text-[11px] hover:bg-white/[0.1] transition-colors"
                title="Minimize"
              >
                <Minimize2 size={11} />
                Esc to close
              </button>
              <div className="w-px h-4 bg-white/[0.08] mx-0.5" />
            </>
          )}
          <button
            type="button"
            onClick={handleCopyAll}
            className="p-1.5 rounded hover:bg-white/[0.06] text-white/30 hover:text-white/60 transition-colors"
            title="Copy all logs"
          >
            {copiedAll ? <Check size={13} className="text-emerald-400" /> : <ClipboardCopy size={13} />}
          </button>
          <button
            type="button"
            onClick={() => setWrapLines((w) => !w)}
            className={`p-1.5 rounded transition-colors ${wrapLines ? 'bg-white/[0.08] text-white/60' : 'hover:bg-white/[0.06] text-white/30 hover:text-white/60'}`}
            title="Wrap lines"
          >
            <WrapText size={13} />
          </button>
          <button
            type="button"
            onClick={handleExport}
            className="p-1.5 rounded hover:bg-white/[0.06] text-white/30 hover:text-white/60 transition-colors"
            title="Export log"
          >
            <Download size={13} />
          </button>
          <div className="w-px h-4 bg-white/[0.08] mx-0.5" />
          <button
            type="button"
            onClick={() => setIsExpanded(true)}
            className="p-1.5 rounded hover:bg-white/[0.06] text-white/30 hover:text-white/60 transition-colors"
            title="Expand logs"
          >
            <Maximize2 size={13} />
          </button>
        </div>
      </div>

      {/* Log lines */}
      <div
        ref={logRef}
        className="flex-1 overflow-y-auto font-mono text-[12px] leading-relaxed p-2"
      >
        {lines.length > 0 ? (
          <div className="space-y-0.5">
            {lines.map((line, i) => (
              <div key={i} className="group flex items-start gap-2 hover:bg-white/[0.03] px-2 py-0.5 rounded">
                <span className="select-none w-10 text-right shrink-0 text-[11px] text-white/10 pt-0.5">
                  {String(i + 1).padStart(4, '0')}
                </span>
                <span className={`text-white/60 ${wrapLines ? 'whitespace-pre-wrap break-all' : 'whitespace-pre'}`}>
                  {line}
                </span>
              </div>
            ))}
          </div>
        ) : (
          <div className="flex flex-col items-center justify-center h-32 text-white/20">
            <Terminal size={24} className="mb-2 opacity-30" />
            <p className="text-xs">No log output captured for this deployment.</p>
          </div>
        )}
      </div>
    </div>
  )

  return logView
}

function RollbackConfirmDialog({
  deploymentId,
  onConfirm,
  onCancel,
}: {
  deploymentId: string
  onConfirm: () => void
  onCancel: () => void
}) {
  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center" style={{ backgroundColor: 'rgba(0,0,0,0.6)' }}>
      <div className="bg-[#1a1a1e] border border-white/[0.08] rounded-xl w-[400px] p-5 shadow-2xl">
        <div className="flex items-center gap-3 mb-4">
          <div className="w-10 h-10 rounded-full bg-amber-500/10 flex items-center justify-center">
            <AlertTriangle size={20} className="text-amber-400" />
          </div>
          <div>
            <div className="text-[14px] font-semibold text-white/90">Rollback Deployment?</div>
            <div className="text-[12px] text-white/40">This will redeploy an older version.</div>
          </div>
        </div>
        <p className="text-[12px] text-white/50 mb-5">
          Rolling back to deployment <span className="font-mono text-white/60">{String(deploymentId).slice(0, 8)}</span> will
          stop the current version and redeploy this older build. Any data written since then may be affected.
        </p>
        <div className="flex gap-2 justify-end">
          <button
            onClick={onCancel}
            className="px-4 py-2 bg-white/5 text-white/50 rounded-lg text-[12px] hover:bg-white/10 transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={onConfirm}
            className="px-4 py-2 bg-amber-500/15 text-amber-400 rounded-lg text-[12px] hover:bg-amber-500/25 transition-colors flex items-center gap-1.5"
          >
            <RotateCcw size={12} />
            Rollback
          </button>
        </div>
      </div>
    </div>
  )
}

function WebhookCard({ url }: { url: string }) {
  const { copiedKey, copy } = useCopy(2000)

  return (
    <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4">
      <div className="flex items-center gap-2 mb-2">
        <Link2 size={13} className="text-[#8b5cf6]" />
        <div className="text-[13px] font-medium text-white/70">Deploy Webhook</div>
      </div>
      <p className="text-[11px] text-white/30 mb-2">
        POST to this URL from your CI/CD pipeline to trigger a deployment.
      </p>
      <div className="flex items-center gap-2">
        <code className="flex-1 bg-black/30 rounded-lg px-3 py-2 text-[11px] font-mono text-white/50 truncate">
          {url}
        </code>
        <button
          onClick={() => copy(url, 'webhook')}
          className="px-3 py-2 bg-white/5 text-white/40 rounded-lg text-[11px] hover:bg-white/10 hover:text-white/60 transition-all flex items-center gap-1.5"
        >
          {copiedKey === 'webhook' ? <Check size={12} className="text-[#22c55e]" /> : <Copy size={12} />}
          {copiedKey === 'webhook' ? 'Copied' : 'Copy'}
        </button>
      </div>
    </div>
  )
}

interface DeployTabProps {
  svc: Service
  serviceId: string
}

export default function DeployTab({ svc, serviceId }: DeployTabProps) {
  const scaleProcess = useScaleProcess()
  const rollbackService = useRollbackService()
  const cancelDeployment = useCancelDeployment()
  const { data: deployments } = useServiceDeployments(svc.id)
  const { data: containerStatus } = useContainerStatus(serviceId)
  const { lastUpdate, isConnected, logMap } = useWebSocketDeployments(serviceId)
  const [expandedDeployment, setExpandedDeployment] = useState<string | null>(null)
  const [rollbackTarget, setRollbackTarget] = useState<string | null>(null)

  useEffect(() => {
    if (lastUpdate?.deployment_id) {
      setExpandedDeployment(String(lastUpdate.deployment_id))
    }
  }, [lastUpdate?.deployment_id])

  const pendingCount = useMemo(() =>
    deployments?.filter((d) => d.status === 'pending' || d.status === 'building' || d.status === 'deploying').length ?? 0,
    [deployments]
  )

  const handleCancelAllPending = () => {
    deployments?.forEach((d) => {
      if (d.status === 'pending' || d.status === 'building' || d.status === 'deploying') {
        cancelDeployment.mutate(d.id)
      }
    })
  }

  const handleCancel = (deploymentId: string) => {
    cancelDeployment.mutate(deploymentId)
  }

  const handleRollback = (deploymentId: string) => {
    rollbackService.mutate(
      { id: svc.id, deploymentId },
      {
        onSuccess: () => {
          toast.success('Rollback initiated')
          setRollbackTarget(null)
        },
        onError: (err: Error) => toast.error(`Rollback failed: ${err.message}`),
      }
    )
  }

  return (
    <div className="p-5 space-y-5">
      {/* Active deployment info */}
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

      {/* Webhook URL */}
      {svc.webhookUrl && <WebhookCard url={svc.webhookUrl} />}

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
            lastUpdate.status === 'cancelled' ? 'bg-amber-500/10 text-amber-400' :
            'bg-[#8b5cf6]/10 text-[#8b5cf6]'
          }`}>{lastUpdate.status}</span>
        </div>
      )}

      {/* Deployment History */}
      <div>
        <div className="flex items-center justify-between mb-3">
          <h4 className="text-[14px] font-medium text-white/70">Deployment History</h4>
          {pendingCount > 1 && (
            <button
              onClick={handleCancelAllPending}
              disabled={cancelDeployment.isPending}
              className="text-[10px] px-2 py-1 bg-red-500/10 text-red-400 rounded hover:bg-red-500/20 transition-colors disabled:opacity-50"
            >
              Cancel {pendingCount} pending
            </button>
          )}
        </div>
        <div className="space-y-1.5">
          {deployments && deployments.length > 0 ? (
            deployments.map((d) => (
              <div key={d.id} className="space-y-1">
                <div
                  className="flex items-center gap-3 px-3 py-2 bg-[#1a1a1e]/50 rounded-lg group cursor-pointer hover:bg-[#1a1a1e]"
                  onClick={() => setExpandedDeployment(expandedDeployment === d.id ? null : d.id)}
                >
                  {expandedDeployment === d.id ? (
                    <ChevronDown size={14} className="text-white/30 flex-shrink-0" />
                  ) : (
                    <ChevronRight size={14} className="text-white/30 flex-shrink-0" />
                  )}
                  <div className="flex-1 grid grid-cols-[auto_1fr_auto] items-center gap-3 min-w-0">
                    <div className="flex items-center gap-2 min-w-0">
                      <span className={`text-[10px] px-1.5 py-0.5 rounded-full font-medium shrink-0 ${
                        d.status === 'succeeded' ? 'bg-[#22c55e]/10 text-[#22c55e]' :
                        d.status === 'failed' ? 'bg-red-500/10 text-red-400' :
                        d.status === 'cancelled' ? 'bg-amber-500/10 text-amber-400' :
                        d.status === 'deploying' || d.status === 'building' ? 'bg-[#8b5cf6]/10 text-[#8b5cf6]' :
                        'bg-white/5 text-white/40'
                      }`}>
                        {d.status}
                      </span>
                      <span className="text-white/30 font-mono text-[11px] shrink-0">
                        {d.commit_sha ? d.commit_sha.slice(0, 7) : '-'}
                      </span>
                      <span className="text-white/60 truncate text-[12px]" title={d.commit_message || ''}>
                        {d.commit_message || <span className="text-white/20">no commit message</span>}
                      </span>
                    </div>
                    <div />
                    <div className="flex items-center gap-2 text-white/30 text-[11px] font-mono shrink-0">
                      {d.created_at && <span>{timeAgo(d.created_at)}</span>}
                      {d.started_at && d.completed_at && (
                        <>
                          <span className="text-white/15">·</span>
                          <span>{Math.round((new Date(d.completed_at).getTime() - new Date(d.started_at).getTime()) / 1000)}s</span>
                        </>
                      )}
                    </div>
                  </div>
                  <div className="flex items-center gap-1.5 shrink-0">
                    <span className={`text-[10px] px-1.5 py-0.5 rounded-full ${
                      d.triggered_by === 'webhook'
                        ? 'bg-[#8b5cf6]/10 text-[#8b5cf6]'
                        : 'bg-white/5 text-white/40'
                    }`}>
                      {d.triggered_by === 'webhook' ? 'auto' : 'manual'}
                    </span>
                    {(d.status === 'pending' || d.status === 'building' || d.status === 'deploying') && (
                      <button
                        onClick={(e) => {
                          e.stopPropagation()
                          handleCancel(d.id)
                        }}
                        disabled={cancelDeployment.isPending}
                        className="text-[10px] px-2 py-0.5 bg-red-500/10 text-red-400 rounded hover:bg-red-500/20 opacity-0 group-hover:opacity-100 transition-all disabled:opacity-50"
                      >
                        Cancel
                      </button>
                    )}
                    {d.status === 'succeeded' && (
                      <button
                        onClick={(e) => {
                          e.stopPropagation()
                          setRollbackTarget(d.id)
                        }}
                        disabled={rollbackService.isPending}
                        className="text-[10px] px-2 py-0.5 bg-white/[0.06] text-white/40 rounded hover:bg-white/[0.1] hover:text-white/70 opacity-0 group-hover:opacity-100 transition-all disabled:opacity-50"
                      >
                        Rollback
                      </button>
                    )}
                  </div>
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

      {/* Rollback confirmation dialog */}
      {rollbackTarget && (
        <RollbackConfirmDialog
          deploymentId={rollbackTarget}
          onConfirm={() => handleRollback(rollbackTarget)}
          onCancel={() => setRollbackTarget(null)}
        />
      )}
    </div>
  )
}
