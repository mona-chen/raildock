import { useNavigate } from 'react-router-dom'
import { Check, ChevronDown, Folder, FolderPlus, LayoutGrid } from 'lucide-react'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { useProjects } from '@/hooks/useProjects'

interface ProjectNavigatorProps {
  projectId: string
  projectName: string
}

/**
 * The project switcher in the project toolbar. Railway lists your projects in
 * the order you last opened them and keeps "view all" one click away, so the
 * project name is a real menu instead of a link back to the dashboard.
 */
export default function ProjectNavigator({ projectId, projectName }: ProjectNavigatorProps) {
  const navigate = useNavigate()
  const { data: projects = [] } = useProjects()

  const recent = projects.slice(0, 8)

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <button
          type="button"
          className="flex items-center gap-1 rounded-lg px-1.5 py-1 text-[13px] hover:bg-white/[0.06] focus:outline-none focus-visible:ring-1 focus-visible:ring-[#8b5cf6]"
          aria-label={`Switch project (currently ${projectName})`}
        >
          <span className="max-w-[180px] truncate font-medium text-white/90">{projectName}</span>
          <ChevronDown size={13} className="text-white/50" />
        </button>
      </DropdownMenuTrigger>
      <DropdownMenuContent
        align="start"
        className="min-w-[240px] border-white/[0.08] bg-[#1a1a1e] text-white/80"
      >
        <DropdownMenuLabel className="text-[10px] uppercase tracking-[0.12em] text-white/30">
          Projects
        </DropdownMenuLabel>
        {recent.length === 0 && (
          <div className="px-2 py-1.5 text-[12px] text-white/40">No other projects yet</div>
        )}
        {recent.map((project) => {
          const isCurrent = project.id === projectId
          return (
            <DropdownMenuItem
              key={project.id}
              onClick={() => {
                if (!isCurrent) navigate(`/dashboard/project/${project.id}`)
              }}
              className="cursor-pointer text-[12px] focus:bg-white/[0.08] focus:text-white"
            >
              <Folder size={13} className="text-white/40" />
              <span className="flex-1 truncate">{project.name}</span>
              {isCurrent && <Check size={13} className="text-rail-purple" />}
            </DropdownMenuItem>
          )
        })}
        <DropdownMenuSeparator className="bg-white/[0.08]" />
        <DropdownMenuItem
          onClick={() => navigate('/dashboard/projects')}
          className="cursor-pointer text-[12px] focus:bg-white/[0.08] focus:text-white"
        >
          <LayoutGrid size={13} className="text-white/50" />
          View all projects
        </DropdownMenuItem>
        <DropdownMenuItem
          onClick={() => navigate('/dashboard/projects?new=1')}
          className="cursor-pointer text-[12px] focus:bg-white/[0.08] focus:text-white"
        >
          <FolderPlus size={13} className="text-rail-purple" />
          New project
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
