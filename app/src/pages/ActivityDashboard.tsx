import { Activity, GitBranch, Database, ArrowUpRight, ArrowDownRight, Settings, Boxes } from 'lucide-react'
import { useActivity } from '@/hooks/useActivity'
import { useProjects } from '@/hooks/useProjects'

const ACTION_ICON: Record<string, React.ElementType> = {
  deployed: GitBranch,
  scaled: ArrowUpRight,
  stopped: ArrowDownRight,
  started: ArrowUpRight,
  linked: Database,
  unlinked: Database,
  created: Settings,
  destroyed: ArrowDownRight,
}

const ACTION_COLOR: Record<string, string> = {
  deployed: '#22c55e',
  scaled: '#8b5cf6',
  stopped: '#ef4444',
  started: '#22c55e',
  linked: '#3b82f6',
  unlinked: '#f59e0b',
  created: '#8b5cf6',
  destroyed: '#ef4444',
}

export default function ActivityDashboard() {
  const { data: projects = [] } = useProjects()
  const { data: events = [], isLoading } = useActivity('')

  return (
    <div className="h-full flex flex-col overflow-hidden">
      <div className="px-6 py-4 border-b border-[rgba(255,255,255,0.06)]">
        <div className="flex items-center gap-3">
          <Activity size={18} className="text-rail-purple" />
          <h1 className="text-base font-semibold text-white">Activity</h1>
          <span className="text-[11px] text-[#4A4A55]">All projects</span>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-6">
        <div className="max-w-2xl mx-auto space-y-2">
          {isLoading ? (
            Array.from({ length: 5 }).map((_, i) => (
              <div key={i} className="h-14 bg-[rgba(255,255,255,0.02)] rounded-lg animate-pulse" />
            ))
          ) : events.length === 0 ? (
            <div className="text-center py-20 text-white/30 text-sm">
              No activity yet
            </div>
          ) : (
            events.map((event) => {
              const Icon = ACTION_ICON[event.action] || Activity
              const color = ACTION_COLOR[event.action] || '#A0A0B0'
              const project = projects.find(p => p.id === event.projectId)
              return (
                <div
                  key={event.id}
                  className="flex items-center gap-4 px-4 py-3 bg-[rgba(255,255,255,0.02)] hover:bg-[rgba(255,255,255,0.04)] rounded-lg transition-colors"
                >
                  <div
                    className="w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0"
                    style={{ backgroundColor: `${color}15` }}
                  >
                    <Icon size={14} style={{ color }} />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="text-[13px] text-white/80 font-medium">
                        {event.serviceName}
                      </span>
                      <span
                        className="text-[11px] px-1.5 py-0.5 rounded-full"
                        style={{ backgroundColor: `${color}15`, color }}
                      >
                        {event.action}
                      </span>
                    </div>
                    <div className="text-[12px] text-white/40 mt-0.5">
                      {event.message}
                    </div>
                  </div>
                  <div className="text-right flex-shrink-0">
                    <div className="text-[11px] text-white/30">
                      {new Date(event.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                    </div>
                    {project && (
                      <div className="text-[10px] text-white/20 mt-0.5">{project.name}</div>
                    )}
                  </div>
                </div>
              )
            })
          )}
        </div>
      </div>
    </div>
  )
}
