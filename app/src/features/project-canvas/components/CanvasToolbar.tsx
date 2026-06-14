import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Ban, Box, ChevronDown, Rocket, RotateCcw, Square, Loader2 } from 'lucide-react'
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

interface CanvasToolbarProps {
  projectId: string
  projectName: string
  projectEnvironment: string
}

export default function CanvasToolbar({ projectId, projectName, projectEnvironment }: CanvasToolbarProps) {
  const navigate = useNavigate()
  const [open, setOpen] = useState(false)

  const deployAll = useDeployAllServices()
  const cancelDeployments = useCancelProjectDeployments()
  const restartAll = useRestartAllServices()
  const stopAll = useStopAllServices()

  const isLoading = deployAll.isPending || cancelDeployments.isPending || restartAll.isPending || stopAll.isPending

  return (
    <div className="h-11 border-b border-white/[0.06] flex items-center justify-between px-3 flex-shrink-0 z-40">
      <div className="flex items-center gap-2">
        <button
          type="button"
          onClick={() => navigate('/dashboard/projects')}
          className="w-7 h-7 rounded-lg bg-white/[0.06] flex items-center justify-center hover:bg-white/[0.1]"
          aria-label="Back to projects"
        >
          <Box size={16} className="text-white" />
        </button>
        <div className="w-px h-4 bg-white/[0.08]" />
        <button
          type="button"
          onClick={() => navigate('/dashboard/projects')}
          className="flex items-center gap-1 text-[13px]"
        >
          <span className="font-medium text-white/90">{projectName}</span>
          <ChevronDown size={13} className="text-white/30" />
        </button>
        <div className="w-px h-4 bg-white/[0.08]" />
        <span className="text-[12px] text-white/50 capitalize">{projectEnvironment}</span>
      </div>

      <div className="flex items-center gap-3">
        {/* Project Actions Dropdown */}
        <DropdownMenu open={open} onOpenChange={setOpen}>
          <DropdownMenuTrigger asChild>
            <button
              type="button"
              disabled={isLoading}
              className="flex items-center gap-1.5 px-2.5 py-1.5 text-[11px] text-white/60 bg-white/[0.06] hover:bg-white/[0.1] rounded-lg transition-all disabled:opacity-50"
            >
              {isLoading ? (
                <Loader2 size={12} className="animate-spin" />
              ) : (
                <Rocket size={12} />
              )}
              Actions
              <ChevronDown size={11} className="text-white/40" />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent
            align="end"
            className="bg-[#1a1a1e] border-white/[0.08] text-white/80 min-w-[180px]"
          >
            <DropdownMenuItem
              onClick={() => { deployAll.mutate(projectId); setOpen(false) }}
              className="text-[12px] cursor-pointer hover:bg-white/[0.08] focus:bg-white/[0.08] focus:text-white"
            >
              <Rocket size={13} className="text-[#8b5cf6]" />
              Deploy All Apps
            </DropdownMenuItem>
            <DropdownMenuItem
              onClick={() => { restartAll.mutate(projectId); setOpen(false) }}
              className="text-[12px] cursor-pointer hover:bg-white/[0.08] focus:bg-white/[0.08] focus:text-white"
            >
              <RotateCcw size={13} className="text-white/50" />
              Restart All
            </DropdownMenuItem>
            <DropdownMenuItem
              onClick={() => { cancelDeployments.mutate(projectId); setOpen(false) }}
              className="text-[12px] cursor-pointer hover:bg-white/[0.08] focus:bg-white/[0.08] focus:text-white"
            >
              <Ban size={13} className="text-amber-400" />
              Cancel All Deployments
            </DropdownMenuItem>
            <DropdownMenuSeparator className="bg-white/[0.08]" />
            <DropdownMenuItem
              onClick={() => { stopAll.mutate(projectId); setOpen(false) }}
              className="text-[12px] cursor-pointer hover:bg-white/[0.08] focus:bg-white/[0.08] focus:text-white"
            >
              <Square size={13} className="text-red-400" />
              Stop All
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>

      </div>
    </div>
  )
}
