import WorkspaceHeader from '@/features/shared/WorkspaceHeader'
import { useMemo, useState } from 'react'
import { useParams } from 'react-router-dom'
import { Activity, GitBranch, Database, ArrowUpRight, ArrowDownRight, Settings, Boxes, Filter, Search, AlertTriangle } from 'lucide-react'
import { useActivity } from '@/hooks/useActivity'
import { useProject } from '@/hooks/useProjects'
import { useProjects } from '@/hooks/useProjects'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Skeleton } from '@/components/ui/skeleton'
import ErrorState from '@/features/shared/ErrorState'
import EmptyState from '@/features/shared/EmptyState'

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
  const { data: events = [], isLoading, isError, refetch } = useActivity(projectId || '')
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
      <WorkspaceHeader title="Activity" description={isScoped && project ? `What’s happening in ${project.name}.` : 'Deployments, changes, and important events across your workspace.'} />
      <div className="border-b border-white/8 px-5 pb-4 sm:px-8">
        <div className="mt-4 flex max-w-3xl items-center gap-2">
          <label className="flex flex-1 items-center gap-2 rounded-md border border-white/[0.07] bg-white/2.5 px-2.5 py-1.5 focus-within:border-rail-purple/50"><Search size={13} className="text-[#9292a3]" /><input aria-label="Search activity" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search activity" className="w-full bg-transparent text-[12px] text-white/65 placeholder:text-[#9292a3] focus:outline-hidden" /></label>
          <label className="flex items-center gap-2 rounded-md border border-white/[0.07] bg-white/2.5 px-2.5 py-1.5"><Filter size={12} className="text-[#9292a3]" /><Select value={action} onValueChange={setAction}><SelectTrigger aria-label="Filter activity by action" className="h-auto border-0 bg-transparent p-0 text-[11px] capitalize text-white/50 shadow-none focus:ring-0 [&_svg]:hidden"><SelectValue /></SelectTrigger><SelectContent><SelectItem value="all" className="text-[11px]">All actions</SelectItem>{actions.map((value) => <SelectItem key={value} value={value} className="capitalize text-[11px]">{value}</SelectItem>)}</SelectContent></Select></label>
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
          ) : isError ? (
            <ErrorState
              title="Couldn't load activity"
              message="RailDock could not reach the API for the activity feed. Retry to load it."
              onRetry={() => refetch()}
            />
          ) : visibleEvents.length > 0 ? (
            <div className="relative divide-y divide-white/5 border-y border-white/5 before:absolute before:bottom-0 before:left-[15px] before:top-0 before:w-px before:bg-white/6">
            {visibleEvents.map((event) => {
              const Icon = ACTION_ICON[event.action] || Boxes
              const color = ACTION_COLOR[event.action] || '#A0A0B0'
              const eventProject = projects.find(p => p.id === event.projectId)
              return (
                <article
                  key={event.id}
                  className="relative grid grid-cols-[32px_minmax(0,1fr)_auto] items-center gap-3 py-3 transition-colors hover:bg-white/2"
                >
                  <div
                    className="z-10 flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-white/6"
                    style={{ backgroundColor: `${color}15` }}
                  >
                    <Icon size={15} style={{ color }} />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="text-[13px] text-white/80">{event.message}</div>
                    <div className="text-[11px] text-[#9292a3] mt-0.5">
                      {event.serviceName && event.serviceName !== '-' && (
                        <span className="text-white/50">{event.serviceName}</span>
                      )}
                      {event.serviceName && event.serviceName !== '-' && (
                        <span className="mx-1.5 text-white/10">·</span>
                      )}
                      {!isScoped && eventProject && (
                        <>
                          <span className="text-white/50">{eventProject.name}</span>
                          <span className="mx-1.5 text-white/10">·</span>
                        </>
                      )}
                      <span>{new Date(event.timestamp).toLocaleString()}</span>
                    </div>
                  </div>
                  <span
                    className="text-[10px] px-2 py-0.5 rounded-full shrink-0"
                    style={{ backgroundColor: `${color}10`, color }}
                  >
                    {event.action}
                  </span>
                </article>
              )
            })}</div>
          ) : events.length === 0 ? (
            <EmptyState
              icon={Activity}
              title="No activity yet"
              description="Deploys, restarts, and configuration changes are recorded here as they happen."
            />
          ) : (
            <EmptyState
              icon={Search}
              title="No matching activity"
              description="No events match the current search or action filter."
              action={
                <button
                  onClick={() => { setQuery(''); setAction('all') }}
                  className="rounded-lg border border-[rgba(255,255,255,0.1)] px-3 py-2 text-[13px] text-[#A0A0B0] hover:text-white transition-colors"
                >
                  Clear filters
                </button>
              }
            />
          )}
        </div>
      </div>
    </div>
  )
}
