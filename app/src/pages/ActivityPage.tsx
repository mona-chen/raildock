import { useParams } from 'react-router-dom'
import { Activity, GitBranch, Database, ArrowUpRight, ArrowDownRight, Settings, Boxes } from 'lucide-react'
import { useActivity } from '@/hooks/useActivity'
import { useProject } from '@/hooks/useProjects'
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

export default function ActivityPage() {
  const { projectId } = useParams<{ projectId: string }>()
  const isScoped = !!projectId
  const { data: project } = useProject(projectId || '')
  const { data: projects = [] } = useProjects()
  const { data: events = [], isLoading } = useActivity(projectId || '')

  return (
    <div className="h-full flex flex-col overflow-hidden">
      <div className="px-6 py-4 border-b border-[rgba(255,255,255,0.06)]">
        <div className="flex items-center gap-3">
          <Activity size={18} className="text-rail-purple" />
          <h1 className="text-base font-semibold text-white">Activity</h1>
          {isScoped && project && (
            <span className="text-[11px] text-[#4A4A55]">{project.name}</span>
          )}
          {!isScoped && (
            <span className="text-[11px] text-[#4A4A55]">All projects</span>
          )}
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-6">
        <div className="max-w-2xl mx-auto space-y-2">
          {isLoading ? (
            Array.from({ length: 5 }).map((_, i) => (
              <div key={i} className="h-14 bg-[rgba(255,255,255,0.02)] rounded-lg animate-pulse" />
            ))
          ) : events.length > 0 ? (
            events.map((event) => {
              const Icon = ACTION_ICON[event.action] || Boxes
              const color = ACTION_COLOR[event.action] || '#A0A0B0'
              const eventProject = projects.find(p => p.id === event.projectId)
              return (
                <div
                  key={event.id}
                  className="flex items-center gap-3 bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-lg p-3 hover:bg-[rgba(255,255,255,0.04)] transition-colors"
                >
                  <div
                    className="w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0"
                    style={{ backgroundColor: `${color}15` }}
                  >
                    <Icon size={15} style={{ color }} />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="text-[13px] text-white/80">{event.message}</div>
                    <div className="text-[11px] text-[#4A4A55] mt-0.5">
                      {event.serviceName && event.serviceName !== '-' && (
                        <span className="text-white/40">{event.serviceName}</span>
                      )}
                      {event.serviceName && event.serviceName !== '-' && (
                        <span className="mx-1.5 text-white/10">·</span>
                      )}
                      {!isScoped && eventProject && (
                        <>
                          <span className="text-white/30">{eventProject.name}</span>
                          <span className="mx-1.5 text-white/10">·</span>
                        </>
                      )}
                      <span>{new Date(event.timestamp).toLocaleString()}</span>
                    </div>
                  </div>
                  <span
                    className="text-[10px] px-2 py-0.5 rounded-full flex-shrink-0"
                    style={{ backgroundColor: `${color}10`, color }}
                  >
                    {event.action}
                  </span>
                </div>
              )
            })
          ) : (
            <div className="text-center py-16 text-[#4A4A55]">
              <Activity size={48} className="mx-auto mb-4 opacity-30" />
              <p className="text-sm">No activity yet</p>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
