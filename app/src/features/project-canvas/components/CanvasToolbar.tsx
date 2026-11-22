import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Ban, Box, ChevronDown, Play, RotateCcw, Square, Loader2, type LucideIcon } from 'lucide-react'
import ProjectNavigator from './ProjectNavigator'
import EnvironmentSwitcher from './EnvironmentSwitcher'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import {
  useCancelProjectDeployments,
  useDeployAllServices,
  useRestartAllServices,
  useStopAllServices,
} from '@/hooks/useProjects'
import { realtimeStateLabel, type RealtimeState } from '@/hooks/useRealtimeState'
import ConfirmDialog from '@/features/shared/ConfirmDialog'
import type { Environment } from '@/types'

interface CanvasToolbarProps {
  projectId: string
  projectName: string
  projectEnvironment: string
  environments?: Environment[]
  activeEnvironmentId?: string
  serviceCount?: number
  appCount?: number
  onSelectEnvironment?: (environmentId: string) => void
  connectionState: RealtimeState
  views?: { key: string; label: string; icon: LucideIcon }[]
  activeView?: string
  onSelectView?: (key: string) => void
}

export default function CanvasToolbar({
  projectId,
  projectName,
  projectEnvironment,
  environments = [],
  activeEnvironmentId,
  serviceCount = 0,
  appCount = 0,
  onSelectEnvironment,
  connectionState,
  views = [],
  activeView,
  onSelectView,
}: CanvasToolbarProps) {
  const navigate = useNavigate()
  const [open, setOpen] = useState(false)
  const [pendingAction, setPendingAction] = useState<'deploy' | 'restart' | 'stop' | 'cancel' | null>(null)
  const environmentName = environments.find((environment) => environment.id === activeEnvironmentId)?.name ?? projectEnvironment
  const actionLabels = { deploy: 'Deploy apps', restart: 'Restart services', stop: 'Stop services', cancel: 'Cancel deployments' }
  const confirmAction = () => {
    const input = { projectId, environmentId: activeEnvironmentId }
    if (pendingAction === 'deploy') deployAll.mutate(input)
    if (pendingAction === 'restart') restartAll.mutate(input)
    if (pendingAction === 'stop') stopAll.mutate(input)
    if (pendingAction === 'cancel') cancelDeployments.mutate(input)
    setPendingAction(null)
  }

  const deployAll = useDeployAllServices()
  const cancelDeployments = useCancelProjectDeployments()
  const restartAll = useRestartAllServices()
  const stopAll = useStopAllServices()

  const isLoading = deployAll.isPending || cancelDeployments.isPending || restartAll.isPending || stopAll.isPending

  return (
    <>
    <div className="min-h-14 border-b border-white/8 bg-[#111115] flex flex-wrap items-center justify-between gap-x-4 gap-y-2 px-3 py-2 shrink-0 z-40">
      <div className="flex max-w-full items-center gap-2 overflow-x-auto">
        <button
          type="button"
          onClick={() => navigate('/dashboard/projects')}
          className="w-7 h-7 rounded-lg bg-white/6 flex items-center justify-center hover:bg-white/10"
          aria-label="Back to projects"
        >
          <Box size={16} className="text-white" />
        </button>
        <div className="w-px h-4 bg-white/8" />
        <ProjectNavigator projectId={projectId} projectName={projectName} />
        <span className="text-[#a0a0b0]">/</span>
        <EnvironmentSwitcher
          projectId={projectId}
          environments={environments}
          activeEnvironmentId={activeEnvironmentId}
          fallbackName={projectEnvironment}
          onSelect={(environmentId) => onSelectEnvironment?.(environmentId)}
        />
        <div className="flex items-center gap-1.5 text-[10px] text-white/50" title="Dashboard connection; application health is shown on each service">
          <span className={`h-1.5 w-1.5 rounded-full ${connectionState === 'live' ? 'bg-emerald-400' : connectionState === 'fallback' ? 'bg-blue-400' : 'bg-amber-400'} ${connectionState === 'connecting' || connectionState === 'reconnecting' ? 'animate-pulse' : ''}`} />
          {connectionState === 'live' ? 'Connected' : realtimeStateLabel(connectionState)}
        </div>
      </div>

      <div className="flex max-w-full items-center gap-3 overflow-x-auto">
        {views.length > 0 && (
          <>
            <nav className="flex items-center gap-0.5" aria-label="Project views">
              {views.map((view) => (
                <button
                  key={view.key}
                  type="button"
                  onClick={() => onSelectView?.(view.key)}
                  aria-current={activeView === view.key ? 'page' : undefined}
                  className={`flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-[12px] transition-colors ${
                    activeView === view.key
                      ? 'bg-white/8 text-white/85'
                      : 'text-white/50 hover:text-white/70 hover:bg-white/4'
                  }`}
                >
                  <view.icon size={13} />
                  {view.label}
                </button>
              ))}
            </nav>
            <div className="w-px h-4 bg-white/8" />
          </>
        )}
        {/* Project Actions Dropdown */}
        <DropdownMenu open={open} onOpenChange={setOpen}>
          <DropdownMenuTrigger asChild>
            <button
              type="button"
              disabled={isLoading || !activeEnvironmentId}
              className="flex items-center gap-1.5 px-2.5 py-1.5 text-[11px] text-white/60 bg-white/6 hover:bg-white/10 rounded-lg transition-all disabled:opacity-50"
            >
              {isLoading ? (
                <Loader2 size={12} className="animate-spin" />
              ) : null}
              {environmentName} actions
              <ChevronDown size={11} className="text-white/50" />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent
            align="end"
            className="bg-[#1a1a1e] border-white/8 text-white/80 min-w-[180px]"
          >
            <DropdownMenuItem
              onClick={() => { setPendingAction('deploy'); setOpen(false) }}
              className="text-[12px] cursor-pointer hover:bg-white/8 focus:bg-white/8 focus:text-white"
            >
              <Play size={13} className="text-rail-purple" />
              Deploy All Apps
            </DropdownMenuItem>
            <DropdownMenuItem
              onClick={() => { setPendingAction('restart'); setOpen(false) }}
              className="text-[12px] cursor-pointer hover:bg-white/8 focus:bg-white/8 focus:text-white"
            >
              <RotateCcw size={13} className="text-white/50" />
              Restart All
            </DropdownMenuItem>
            <DropdownMenuItem
              onClick={() => { setPendingAction('cancel'); setOpen(false) }}
              className="text-[12px] cursor-pointer hover:bg-white/8 focus:bg-white/8 focus:text-white"
            >
              <Ban size={13} className="text-amber-400" />
              Cancel All Deployments
            </DropdownMenuItem>
            <DropdownMenuSeparator className="bg-white/8" />
            <DropdownMenuItem
              onClick={() => { setPendingAction('stop'); setOpen(false) }}
              className="text-[12px] cursor-pointer hover:bg-white/8 focus:bg-white/8 focus:text-white"
            >
              <Square size={13} className="text-red-400" />
              Stop All
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>

      </div>
    </div>
    <ConfirmDialog
      open={pendingAction !== null}
      onOpenChange={(open) => { if (!open) setPendingAction(null) }}
      onConfirm={confirmAction}
      title={pendingAction ? `${actionLabels[pendingAction]} in ${environmentName}?` : ''}
      description={`This affects ${pendingAction === 'deploy' ? appCount : serviceCount} ${pendingAction === 'deploy' ? 'apps' : 'services'} in ${projectName} / ${environmentName}. Other environments are unchanged.`}
      confirmLabel={pendingAction ? actionLabels[pendingAction] : 'Confirm'}
      destructive={pendingAction === 'stop'}
    />
    </>
  )
}
