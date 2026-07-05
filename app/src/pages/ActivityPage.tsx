import { useMemo, useState } from 'react'
import { useParams } from 'react-router-dom'
import { Activity, GitBranch, Database, ArrowUpRight, ArrowDownRight, Settings, Boxes, Filter, Search, AlertTriangle } from 'lucide-react'
import { useActivity } from '@/hooks/useActivity'
import { useProject } from '@/hooks/useProjects'
import { useProjects } from '@/hooks/useProjects'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Skeleton } from '@/components/ui/skeleton'

const ACTION_ICON: Record<string, React.ElementType> = {
  deployed: GitBranch,
  scaled: ArrowUpRight,
  stopped: ArrowDownRight,
  started: ArrowUpRight,
  linked: Database,
  unlinked: Database,
  created: Settings,
  destroyed: ArrowDownRight,
  restarted: ArrowUpRight,
  warning: AlertTriangle,
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
  restarted: '#22c55e',
  warning: '#f59e0b',
}

export default function ActivityPage() {
  const { projectId } = useParams<{ projectId: string }>()
  const isScoped = !!projectId
  const { data: project } = useProject(projectId || '')
  const { data: projects = [] } = useProjects()
  const { data: events = [], isLoading } = useActivity(projectId || '')
  const [query, setQuery] = useState('')
  const [action, setAction] = useState('all')
  const actions = useMemo(() => Array.from(new Set(events.map((event) => event.action))).sort(), [events])
  const visibleEvents = useMemo(() => events.filter((event) => {
    const matchesAction = action === 'all' || event.action === action
    const haystack = `${event.message} ${event.serviceName || ''}`.toLowerCase()
    return matchesAction && haystack.includes(query.toLowerCase())
  }), [action, events, query])

  return (
    <div className="h-full flex flex-col overflow-hidden">
      <div className="border-b border-white/[0.06] px-6 py-4">
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
        <div className="mt-4 flex max-w-3xl items-center gap-2">
          <label className="flex flex-1 items-center gap-2 rounded-md border border-white/[0.07] bg-white/[0.025] px-2.5 py-1.5 focus-within:border-[#8b5cf6]/50"><Search size={13} className="text-white/20" /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search activity" className="w-full bg-transparent text-[12px] text-white/65 placeholder:text-white/20 focus:outline-none" /></label>
          <label className="flex items-center gap-2 rounded-md border border-white/[0.07] bg-white/[0.025] px-2.5 py-1.5"><Filter size={12} className="text-white/20" /><Select value={action} onValueChange={setAction}><SelectTrigger className="h-auto border-0 bg-transparent p-0 text-[11px] capitalize text-white/50 shadow-none focus:ring-0 [&_svg]:hidden"><SelectValue /></SelectTrigger><SelectContent><SelectItem value="all" className="text-[11px]">All actions</SelectItem>{actions.map((value) => <SelectItem key={value} value={value} className="capitalize text-[11px]">{value}</SelectItem>)}</SelectContent></Select></label>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-6">
        <div className="mx-auto max-w-3xl">
          {isLoading ? (
            Array.from({ length: 5 }).map((_, i) => (
              <div key={i} className="flex items-center gap-3 py-3">
                <Skeleton className="size-8 rounded-full" />
                <div className="flex-1 space-y-2">
                  <Skeleton className="h-3.5 w-1/2" />
                  <Skeleton className="h-3 w-1/3" />
                </div>
                <Skeleton className="h-5 w-16 rounded" />
              </div>
            ))
          ) : visibleEvents.length > 0 ? (
            <div className="relative divide-y divide-white/[0.05] border-y border-white/[0.05] before:absolute before:bottom-0 before:left-[15px] before:top-0 before:w-px before:bg-white/[0.06]">
            {visibleEvents.map((event) => {
              const Icon = ACTION_ICON[event.action] || Boxes
              const color = ACTION_COLOR[event.action] || '#A0A0B0'
              const eventProject = projects.find(p => p.id === event.projectId)
              return (
                <article
                  key={event.id}
                  className="relative grid grid-cols-[32px_minmax(0,1fr)_auto] items-center gap-3 py-3 transition-colors hover:bg-white/[0.02]"
                >
                  <div
                    className="z-10 flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-full border border-white/[0.06]"
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
                </article>
              )
            })}</div>
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
