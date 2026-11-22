import LogText, { stripLogFormatting } from '@/features/shared/LogText'
import ProcessScaling from './ProcessScaling'
import { IconButton } from '@/components/ui/icon-button'
import { useState, useEffect, useRef, useMemo } from 'react'
import { ChevronDown, ChevronRight, Terminal, Copy, Check, AlertTriangle, Link2, RotateCcw, ClipboardCopy, WrapText, Maximize2, Minimize2, Download, GitBranch, GitCommit, Timer, UserRound, Play, RefreshCw, Hammer } from 'lucide-react'
import {
  useRollbackService,
  useServiceDeployments,
  useContainerStatus,
  useDeployment,
  useCancelDeployment,
  useDeployService,
  useRestartService,
  useRebuildService,
} from '@/hooks/useServices'
import { useCopy } from '@/hooks/useCopy'
import type { useWebSocketDeployments } from '@/hooks/useWebSocketDeployments'
import type { Service } from '@/types'
import { toast } from 'sonner'
import { copyToClipboard } from '@/lib/clipboard'
import { realtimeStateLabel } from '@/hooks/useRealtimeState'
import { statusMeta } from '@/lib/status'


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

export function DeploymentLogPanel({ deploymentId, liveLog }: { deploymentId: string; liveLog?: string }) {
  const { data: deployment, isLoading, isError, refetch } = useDeployment(deploymentId)
  const logRef = useRef<HTMLDivElement>(null)
  const [wrapLines, setWrapLines] = useState(true)
  const [query, setQuery] = useState('')
  const [isExpanded, setIsExpanded] = useState(false)
  const [copiedAll, setCopiedAll] = useState(false)
  const [followLogs, setFollowLogs] = useState(true)

  const isLiveDeployment = ['pending', 'building', 'deploying'].includes(deployment?.status || '') || (!deployment && Boolean(liveLog))
  const logText = deployment?.deployLog || deployment?.buildLog || liveLog || ''
  const rawLines = useMemo(() => logText.split('\n'), [logText])
  const cleanText = useMemo(() => stripLogFormatting(logText), [logText])
  const lines = useMemo(() => cleanText ? cleanText.split('\n') : [], [cleanText])

  const visibleLines = useMemo(() => lines.map((text, index) => ({ text, number: index + 1 })).filter((line) => line.text.toLowerCase().includes(query.trim().toLowerCase())), [lines, query])
  useEffect(() => {
    if (!isExpanded) return
    const close = (event: KeyboardEvent) => { if (event.key === 'Escape') { event.preventDefault(); event.stopImmediatePropagation(); setIsExpanded(false) } }
    window.addEventListener('keydown', close, true)
    return () => window.removeEventListener('keydown', close, true)
  }, [isExpanded])
  useEffect(() => {
    if (followLogs && !query && logRef.current) {
      logRef.current.scrollTop = logRef.current.scrollHeight
    }
  }, [cleanText, followLogs, query])

  const handleLogScroll = () => {
    if (!logRef.current) return
    const distanceFromBottom = logRef.current.scrollHeight - logRef.current.scrollTop - logRef.current.clientHeight
    setFollowLogs(distanceFromBottom < 48)
  }

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
      <div className="ml-6 bg-[#131318] border border-white/6 rounded-xl p-4">
        <div className="text-[12px] text-white/50">Loading logs...</div>
      </div>
    )
  }

  const logView = (
    <div className={`flex flex-col bg-[#131318] ${isExpanded ? 'fixed inset-0 z-100' : 'h-[480px] max-h-[65dvh] min-h-64 rounded-lg border border-white/8 overflow-hidden'}`}>
      {/* Toolbar */}
      <div className="flex flex-wrap items-center justify-between gap-2 px-3 py-2 border-b border-white/6 shrink-0">
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-1.5">
            <Terminal size={12} className="text-white/50" />
            <span className="text-[11px] text-white/50">Deployment Log</span>
          </div>
          <span className="text-[10px] text-white/20">{lines.length.toLocaleString()} lines</span>
        </div>
        <div className="flex items-center gap-1">
          {isExpanded && (
            <>
              <button
                type="button"
                onClick={() => setIsExpanded(false)}
                className="flex items-center gap-1 px-2 py-1 rounded bg-white/6 text-white/50 text-[11px] hover:bg-white/10 transition-colors"
                title="Minimize"
              >
                <Minimize2 size={11} />
                Esc to close
              </button>
              <div className="w-px h-4 bg-white/8 mx-0.5" />
            </>
          )}
          <IconButton
            type="button"
            onClick={handleCopyAll}
            className="p-1.5 rounded hover:bg-white/6 text-white/50 hover:text-white/60 transition-colors"
            title="Copy all logs"
          >
            {copiedAll ? <Check size={13} className="text-emerald-400" /> : <ClipboardCopy size={13} />}
          </IconButton>
          <IconButton
            type="button"
            onClick={() => setWrapLines((w) => !w)}
            className={`p-1.5 rounded transition-colors ${wrapLines ? 'bg-white/8 text-white/60' : 'hover:bg-white/6 text-white/50 hover:text-white/60'}`}
            title="Wrap lines"
            aria-pressed={wrapLines}
          >
            <WrapText size={13} />
          </IconButton>
          <IconButton
            type="button"
            onClick={handleExport}
            className="p-1.5 rounded hover:bg-white/6 text-white/50 hover:text-white/60 transition-colors"
            title="Export log"
          >
            <Download size={13} />
          </IconButton>
          <div className="w-px h-4 bg-white/8 mx-0.5" />
          <IconButton
            type="button"
            onClick={() => setIsExpanded((expanded) => !expanded)}
            className="p-1.5 rounded hover:bg-white/6 text-white/50 hover:text-white/60 transition-colors"
            title={isExpanded ? 'Restore log viewer' : 'Expand logs'}
          >
            <Maximize2 size={13} />
          </IconButton>
        </div>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-white/8 px-3 py-2"><input aria-label="Search deployment logs" placeholder="Search output…" value={query} onChange={(event) => setQuery(event.target.value)} className="input-dark max-w-xs text-xs" /><span className="text-xs text-[#a0a0b0]">{query ? `${visibleLines.length} matching ${visibleLines.length === 1 ? 'line' : 'lines'}` : !isLiveDeployment ? 'Saved output' : followLogs ? 'Following output' : 'Following paused'}</span></div>
      {isError && <div role="status" className="flex items-center justify-between gap-2 px-3 py-2 text-xs text-amber-200">Could not fetch deployment logs. Displayed output is retained.<button type="button" onClick={() => refetch()} className="underline">Retry</button></div>}
      {/* Log lines */}
      <div
        ref={logRef}
        onScroll={handleLogScroll}
        role="textbox"
        aria-readonly="true"
        aria-multiline="true"
        aria-label="Deployment output"
        tabIndex={0}
        className="min-h-0 flex-1 overflow-auto font-mono text-[12px] leading-5 p-2"
      >
        {!followLogs && (
          <button
            type="button"
            onClick={() => setFollowLogs(true)}
            className="sticky left-1/2 top-2 z-10 -translate-x-1/2 rounded-full border border-white/10 bg-[#24242a] px-3 py-1 text-[10px] text-white/60 shadow-lg hover:text-white"
          >
            {isLiveDeployment ? 'Resume live logs' : 'Jump to end'}
          </button>
        )}
        {visibleLines.length > 0 ? (
          <div className="space-y-0.5">
            {visibleLines.map(({ text: line, number }) => (
              <div key={number} className={`group flex items-start gap-2 px-2 py-0.5 rounded ${/\b(ERROR|FATAL)\b/i.test(line) ? 'bg-red-400/6' : 'hover:bg-white/3'}`}>
                <span className="select-none w-10 text-right shrink-0 text-[11px] text-[#878795] pt-0.5">
                  {number}
                </span>
                <span className={`min-w-0 text-[#c3c3cf] ${wrapLines ? 'whitespace-pre-wrap wrap-break-word wrap-anywhere' : 'whitespace-pre'}`}>
                  <LogText text={rawLines[number - 1] || line} />
                </span>
              </div>
            ))}
          </div>
        ) : (
          <div className="flex flex-col items-center justify-center h-32 text-white/20">
            <Terminal size={24} className="mb-2 opacity-30" />
            <p className="text-xs">{query ? 'No lines match your search.' : isError ? 'Deployment logs are unavailable. Retry the request.' : 'No log output captured for this deployment.'}</p>
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
    <div className="fixed inset-0 z-70 flex items-center justify-center" style={{ backgroundColor: 'rgba(0,0,0,0.6)' }}>
      <div className="bg-[#1a1a1e] border border-white/8 rounded-xl w-[400px] p-5 shadow-2xl">
        <div className="flex items-center gap-3 mb-4">
          <div className="w-10 h-10 rounded-full bg-amber-500/10 flex items-center justify-center">
            <AlertTriangle size={20} className="text-amber-400" />
          </div>
          <div>
            <div className="text-[14px] font-semibold text-white/90">Rollback Deployment?</div>
            <div className="text-[12px] text-white/50">This will redeploy an older version.</div>
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
    <div className="bg-[#1a1a1e] border border-white/6 rounded-xl p-4">
      <div className="flex items-center gap-2 mb-2">
        <Link2 size={13} className="text-rail-purple" />
        <div className="text-[13px] font-medium text-white/70">Deploy Webhook</div>
      </div>
      <p className="text-[11px] text-white/50 mb-2">
        POST to this URL from your CI/CD pipeline to trigger a deployment.
      </p>
      <div className="flex items-center gap-2">
        <code className="flex-1 bg-black/30 rounded-lg px-3 py-2 text-[11px] font-mono text-white/50 truncate">
          {url}
        </code>
        <button
          onClick={() => copy(url, 'webhook')}
          className="px-3 py-2 bg-white/5 text-white/50 rounded-lg text-[11px] hover:bg-white/10 hover:text-white/60 transition-all flex items-center gap-1.5"
        >
          {copiedKey === 'webhook' ? <Check size={12} className="text-rail-green" /> : <Copy size={12} />}
          {copiedKey === 'webhook' ? 'Copied' : 'Copy'}
        </button>
      </div>
    </div>
  )
}

interface DeployTabProps {
  svc: Service
  serviceId: string
  realtime: ReturnType<typeof useWebSocketDeployments>
}

export default function DeployTab({ svc, serviceId, realtime }: DeployTabProps) {
  const rollbackService = useRollbackService()
  const cancelDeployment = useCancelDeployment()
  const deployService = useDeployService()
  const restartService = useRestartService()
  const rebuildService = useRebuildService()
  const { data: deployments } = useServiceDeployments(svc.id)
  const { data: containerStatus } = useContainerStatus(serviceId)
  const { lastUpdate, isConnected, connectionState, logMap } = realtime
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

  const containerState = containerStatus?.status
  const isCrashLooping = containerState === 'restarting' || containerState === 'exited' || containerState === 'dead'
  // A deploy can report success and the container still die right after. Call
  // that "crashed" rather than letting it read as a plain failure, and surface
  // the restart/rollback affordances next to it.
  const succeededDeployments = useMemo(
    () => (deployments ?? [])
      .filter((d) => d.status === 'succeeded')
      .sort((a, b) => new Date(b.createdAt || 0).getTime() - new Date(a.createdAt || 0).getTime()),
    [deployments]
  )
  const latestSucceeded = succeededDeployments[0] ?? null
  const previousSucceeded = succeededDeployments[1] ?? null
  const crashedAfterSuccess = isCrashLooping && !!latestSucceeded
  const busy = deployService.isPending || restartService.isPending || rebuildService.isPending || pendingCount > 0

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
      <div className="bg-[#1a1a1e] border border-white/6 rounded-xl p-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span className="text-[11px] px-2 py-0.5 bg-rail-green/10 text-rail-green rounded-full font-medium">
              ACTIVE
            </span>
            <span className="text-[13px] text-white/50">
              {svc.lastDeployed || 'No deployments yet'}
            </span>
          </div>
        </div>
        {svc.gitRepo && (
          <div className="mt-3 flex items-center gap-2 text-[12px] text-white/50">
            <span>{svc.gitRepo}</span>
            <span className="text-white/20">on</span>
            <span className="text-white/50">{svc.branch || 'main'}</span>
          </div>
        )}
        {svc.builder && (
          <div className="mt-2 text-[12px] text-white/50">
            Builder: <span className="text-white/60">{svc.builder}</span>
          </div>
        )}
      </div>

      {/* Deploy actions */}
      <div className="flex flex-wrap items-center gap-2">
        <button
          type="button"
          onClick={() => deployService.mutate(svc.id)}
          disabled={busy}
          className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-rail-purple text-white text-[12px] font-medium hover:bg-rail-purple-dark disabled:opacity-50 transition-colors"
        >
          <Play size={13} /> Deploy latest
        </button>
        <button
          type="button"
          onClick={() => restartService.mutate(svc.id)}
          disabled={busy}
          className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-white/6 text-white/70 text-[12px] hover:bg-white/10 hover:text-white disabled:opacity-50 transition-colors"
        >
          <RefreshCw size={13} /> Restart
        </button>
        <button
          type="button"
          onClick={() => rebuildService.mutate(svc.id)}
          disabled={busy}
          className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-white/6 text-white/70 text-[12px] hover:bg-white/10 hover:text-white disabled:opacity-50 transition-colors"
        >
          <Hammer size={13} /> Rebuild
        </button>
      </div>

      {crashedAfterSuccess && (
        <div className="flex items-start gap-3 rounded-xl border border-red-500/20 bg-red-500/6 p-3">
          <AlertTriangle size={15} className="text-red-400 mt-0.5 shrink-0" />
          <div className="min-w-0">
            <div className="text-[12px] font-medium text-red-300">Crashed after a successful deploy</div>
            <p className="text-[11px] text-white/50 mt-0.5">
              The build succeeded but the container is {containerState}. Check the logs, then restart it
              {previousSucceeded ? ' or roll back to the previous revision.' : '.'}
            </p>
            <div className="flex items-center gap-2 mt-2">
              <button
                type="button"
                onClick={() => restartService.mutate(svc.id)}
                disabled={restartService.isPending}
                className="px-2.5 py-1 rounded-md bg-red-500/15 text-red-300 text-[11px] hover:bg-red-500/25 disabled:opacity-50 transition-colors"
              >
                Restart container
              </button>
              {previousSucceeded && (
                <button
                  type="button"
                  onClick={() => setRollbackTarget(previousSucceeded.id)}
                  className="px-2.5 py-1 rounded-md bg-white/6 text-white/60 text-[11px] hover:bg-white/10 transition-colors"
                >
                  Roll back to previous
                </button>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Webhook URL */}
      {svc.webhookUrl && <WebhookCard url={svc.webhookUrl} />}

      {svc.processTypes && svc.processTypes.length > 0 && (
        <div>
          <h4 className="text-[14px] font-medium text-white/70 mb-3">Processes</h4>
          <div className="space-y-2">
            {svc.processTypes.map((process) => <ProcessScaling key={process.name} serviceId={serviceId} process={process} />)}
          </div>
        </div>
      )}

      {containerStatus && (
        <div className="bg-[#1a1a1e] border border-white/6 rounded-lg p-3">
          <div className="flex items-center justify-between">
            <div className="text-[12px] text-white/60">Container Status</div>
            <span className={`text-[10px] px-2 py-0.5 rounded-full ${
              containerStatus.status === 'running'
                ? 'bg-rail-green/10 text-rail-green'
                : isCrashLooping
                  ? 'bg-red-500/10 text-red-400'
                  : 'bg-white/5 text-white/50'
            }`}>{containerStatus.status}</span>
          </div>
        </div>
      )}

      {lastUpdate && (
        <div className="bg-rail-purple/5 border border-rail-purple/20 rounded-lg p-3 flex items-center gap-2">
          <span className={`w-2 h-2 rounded-full ${isConnected ? 'bg-rail-green' : connectionState === 'fallback' ? 'bg-blue-400' : 'bg-amber-400'} ${connectionState === 'connecting' || connectionState === 'reconnecting' ? 'animate-pulse' : ''}`} />
          <span className="text-[12px] text-white/60">{lastUpdate.message}</span>
          <span className="text-[10px] text-white/25">{realtimeStateLabel(connectionState)}</span>
          <span className={`text-[10px] px-1.5 py-0.5 rounded-full ml-auto ${
            lastUpdate.status === 'succeeded' ? 'bg-rail-green/10 text-rail-green' :
            lastUpdate.status === 'failed' ? 'bg-red-500/10 text-red-400' :
            lastUpdate.status === 'cancelled' ? 'bg-amber-500/10 text-amber-400' :
            'bg-rail-purple/10 text-rail-purple'
          }`}>{statusMeta(lastUpdate.status).label}</span>
        </div>
      )}

      {/* Deployment ledger */}
      <section className="overflow-hidden border-y border-white/6">
        <div className="flex items-center justify-between mb-3">
          <div>
            <h4 className="text-[14px] font-medium text-white/80">Deployments</h4>
            <p className="mt-0.5 text-[11px] text-white/25">Build, release, restart, and rollback history.</p>
          </div>
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
        <div className="grid grid-cols-[minmax(0,1fr)_110px_90px_90px] gap-3 border-b border-white/6 px-3 py-2 text-[9px] uppercase tracking-[0.12em] text-white/20">
          <span>Revision</span><span>Trigger</span><span>Started</span><span className="text-right">Duration</span>
        </div>
        <div className="divide-y divide-white/5">
          {deployments && deployments.length > 0 ? (
            deployments.map((d) => (
              <article key={d.id}>
                <div
                  className="group grid cursor-pointer grid-cols-[minmax(0,1fr)_110px_90px_90px] items-center gap-3 px-3 py-3 hover:bg-white/2.5 focus-within:bg-white/2.5"
                  onClick={() => setExpandedDeployment(expandedDeployment === d.id ? null : d.id)}
                >
                  <div className="flex min-w-0 items-center gap-2">
                    {expandedDeployment === d.id ? <ChevronDown size={13} className="shrink-0 text-white/25" /> : <ChevronRight size={13} className="shrink-0 text-white/25" />}
                      <span className={`text-[10px] px-1.5 py-0.5 rounded-full border font-medium shrink-0 ${statusMeta(d.status).badge}`}>
                        {statusMeta(d.status).label}
                      </span>
                      {d.kind && d.kind !== 'deploy' && (
                        <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-cyan-500/10 text-cyan-400 font-medium uppercase tracking-wider shrink-0">
                          {d.kind.replace('_', ' ')}
                        </span>
                      )}
                      {d.kind === 'deploy' || !d.kind ? (
                        <div className="min-w-0"><div className="truncate text-[12px] text-white/70" title={d.commitMessage || ''}>{d.commitMessage || 'Manual deployment'}</div><div className="mt-0.5 flex items-center gap-2 text-[10px] text-white/25"><span className="flex items-center gap-1 font-mono"><GitCommit size={10} />{d.commitSha ? d.commitSha.slice(0, 7) : 'working tree'}</span><span className="flex items-center gap-1"><GitBranch size={10} />{d.branch || svc.branch || 'main'}</span></div></div>
                      ) : (
                        <span className="truncate text-[12px] text-white/50">
                          {d.deployLog?.split("\n").filter(Boolean).pop() || `${d.kind} operation`}
                        </span>
                      )}
                  </div>
                  <div className="flex items-center gap-1.5 text-[10px] text-white/35"><UserRound size={11} /><span className="truncate">{d.triggeredBy?.replace('_', ' ') || 'manual'}</span></div>
                  <span className="text-[10px] text-white/50">{d.createdAt ? timeAgo(d.createdAt) : '—'}</span>
                  <div className="flex items-center justify-end gap-1 text-[10px] font-mono text-white/50"><Timer size={10} />{d.startedAt && d.completedAt ? `${Math.round((new Date(d.completedAt).getTime() - new Date(d.startedAt).getTime()) / 1000)}s` : d.status === 'building' || d.status === 'deploying' ? 'live' : '—'}
                    {(d.status === 'pending' || d.status === 'building' || d.status === 'deploying') && (!d.kind || d.kind === 'deploy') && (
                      <button
                        onClick={(e) => {
                          e.stopPropagation()
                          handleCancel(d.id)
                        }}
                        disabled={cancelDeployment.isPending}
                        className="ml-1 rounded bg-red-500/10 px-1.5 py-0.5 text-[9px] text-red-400 hover:bg-red-500/20 disabled:opacity-50"
                      >
                        Cancel
                      </button>
                    )}
                    {d.status === 'succeeded' && (!d.kind || d.kind === 'deploy') && (
                      <button
                        onClick={(e) => {
                          e.stopPropagation()
                          setRollbackTarget(d.id)
                        }}
                        disabled={rollbackService.isPending}
                        className="ml-1 rounded bg-white/6 px-1.5 py-0.5 text-[9px] text-white/50 hover:bg-white/10 hover:text-white/70 disabled:opacity-50"
                      >
                        Rollback
                      </button>
                    )}
                  </div>
                </div>
                {expandedDeployment === d.id && (
                  <div className="border-t border-white/4 bg-black/10 px-3 py-3"><DeploymentLogPanel deploymentId={d.id} liveLog={logMap[d.id]} /></div>
                )}
              </article>
            ))
          ) : (
            <div className="text-[12px] text-white/50 py-4 text-center">No deployment history</div>
          )}
        </div>
      </section>

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
