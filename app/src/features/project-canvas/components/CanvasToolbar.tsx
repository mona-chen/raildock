import { useNavigate } from 'react-router-dom'
import { Box, ChevronDown, Activity, Bell, Bot } from 'lucide-react'

interface CanvasToolbarProps {
  projectName: string
  projectEnvironment: string
}

export default function CanvasToolbar({ projectName, projectEnvironment }: CanvasToolbarProps) {
  const navigate = useNavigate()

  return (
    <div className="h-11 border-b border-white/[0.06] flex items-center justify-between px-3 flex-shrink-0 z-40">
      <div className="flex items-center gap-2">
        <button
          onClick={() => navigate('/dashboard/projects')}
          className="w-7 h-7 rounded-lg bg-white/[0.06] flex items-center justify-center hover:bg-white/[0.1]"
        >
          <Box size={16} className="text-white" />
        </button>
        <div className="w-px h-4 bg-white/[0.08]" />
        <button
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
        <button className="text-white/30 hover:text-white/60"><Activity size={16} /></button>
        <button className="text-white/30 hover:text-white/60"><Bell size={16} /></button>
        <div className="h-5 w-px bg-white/[0.08]" />
        <button className="flex items-center gap-1 text-[12px] text-white/50">
          <Bot size={14} /> Agent
        </button>
      </div>
    </div>
  )
}
