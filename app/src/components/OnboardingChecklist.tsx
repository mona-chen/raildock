import { useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import {
  CheckCircle2,
  ChevronRight,
  Circle,
  Server,
  Folder,
  Box,
  Rocket,
  Sparkles,
  X,
} from 'lucide-react'
import { useServers } from '@/hooks/useServers'
import { useProjects } from '@/hooks/useProjects'

const STORAGE_KEY = 'raildock-onboarding-dismissed'

interface Step {
  id: string
  label: string
  description: string
  icon: React.ElementType
  action: string
}

const STEPS: Step[] = [
  {
    id: 'server',
    label: 'Connect a server',
    description: 'Link your Dokku host via SSH',
    icon: Server,
    action: 'Add server',
  },
  {
    id: 'project',
    label: 'Create a project',
    description: 'Organize your apps and databases',
    icon: Folder,
    action: 'New project',
  },
  {
    id: 'service',
    label: 'Add a service',
    description: 'Deploy an app or provision a database',
    icon: Box,
    action: 'Add service',
  },
  {
    id: 'deploy',
    label: 'Deploy',
    description: 'Push code and watch it go live',
    icon: Rocket,
    action: 'Deploy now',
  },
]

function readDismissed() {
  try {
    return localStorage.getItem(STORAGE_KEY) === 'true'
  } catch {
    return false
  }
}

/**
 * Compact getting-started strip for the projects list.
 *
 * It stays a single slim row until you ask for the full checklist, collapses by
 * itself once you have made progress, and disappears for good the moment every
 * step is satisfied — a first-run hint should never become permanent chrome.
 */
export default function OnboardingChecklist() {
  const navigate = useNavigate()
  const [dismissed, setDismissed] = useState(readDismissed)
  const { data: servers = [] } = useServers()
  const { data: projects = [] } = useProjects()

  const checks: Record<string, boolean> = useMemo(
    () => ({
      server: servers.some((server) => server.status === 'connected'),
      project: projects.length > 0,
      service: projects.some((project) => (project.serviceCounts?.total || project.serviceIds?.length || 0) > 0),
      deploy: projects.some((project) => project.hasDeployments),
    }),
    [servers, projects],
  )

  const completedCount = STEPS.filter((step) => checks[step.id]).length
  const allCompleted = completedCount === STEPS.length
  const nextStep = STEPS.find((step) => !checks[step.id])

  // Started users get the compact row; brand-new users see the steps once. The
  // choice is deferred (null) until either the data says "no progress yet" or
  // the user toggles, so the strip collapses as soon as projects load instead of
  // staying expanded from the pre-fetch render.
  const [expandedOverride, setExpandedOverride] = useState<boolean | null>(null)
  const expanded = expandedOverride ?? completedCount === 0

  const handleDismiss = () => {
    try {
      localStorage.setItem(STORAGE_KEY, 'true')
    } catch {
      /* localStorage can be unavailable (private mode) — not fatal */
    }
    setDismissed(true)
  }

  const getStepHref = (step: Step): string => {
    if (step.id === 'server') return '/dashboard/servers'
    if (step.id === 'project') return '/dashboard/projects?new=1'
    const firstProject = projects[0]
    return firstProject ? `/dashboard/project/${firstProject.id}` : '/dashboard/projects'
  }

  if (dismissed || allCompleted) return null

  return (
    <div className="mb-6 overflow-hidden rounded-xl border border-[rgba(139,92,246,0.12)] bg-gradient-to-br from-[rgba(139,92,246,0.06)] to-[rgba(139,92,246,0.02)]">
      <div className="flex items-center gap-3 px-4 py-2.5">
        <Sparkles size={14} className="shrink-0 text-rail-purple" />
        <button
          type="button"
          onClick={() => setExpandedOverride(!expanded)}
          aria-expanded={expanded}
          className="flex min-w-0 flex-1 items-center gap-3 text-left"
        >
          <span className="shrink-0 text-[12px] font-medium text-white">Getting started</span>
          <span className="h-1.5 w-24 shrink-0 overflow-hidden rounded-full bg-white/[0.06]">
            <span
              className="block h-full rounded-full bg-rail-purple transition-all"
              style={{ width: `${(completedCount / STEPS.length) * 100}%` }}
            />
          </span>
          <span className="truncate text-[11px] text-[#6B6B78]">
            {completedCount} of {STEPS.length}
            {nextStep ? ` · next: ${nextStep.label.toLowerCase()}` : ''}
          </span>
          <ChevronRight
            size={13}
            className={`shrink-0 text-[#6b6b7b] transition-transform ${expanded ? 'rotate-90' : ''}`}
          />
        </button>
        {nextStep && (
          <button
            type="button"
            onClick={() => navigate(getStepHref(nextStep))}
            className="hidden shrink-0 items-center gap-1.5 rounded-lg bg-rail-purple px-3 py-1.5 text-[11px] font-medium text-white transition-colors hover:bg-rail-purple-dark sm:flex"
          >
            {nextStep.action}
            <ChevronRight size={12} />
          </button>
        )}
        <button
          type="button"
          onClick={handleDismiss}
          aria-label="Dismiss getting started"
          className="shrink-0 rounded p-1 text-[#6b6b7b] transition-colors hover:bg-white/[0.04] hover:text-[#A0A0B0]"
        >
          <X size={13} />
        </button>
      </div>

      {expanded && (
        <ul className="space-y-0.5 px-2 pb-2">
          {STEPS.map((step) => {
            const isDone = checks[step.id]
            const isNext = step.id === nextStep?.id
            return (
              <li key={step.id}>
                <Link
                  to={getStepHref(step)}
                  className={`group flex items-center gap-2.5 rounded-lg px-2 py-1.5 transition-colors ${
                    isDone
                      ? 'opacity-55'
                      : isNext
                        ? 'bg-[rgba(139,92,246,0.08)] hover:bg-[rgba(139,92,246,0.14)]'
                        : 'hover:bg-white/[0.04]'
                  }`}
                >
                  {isDone ? (
                    <CheckCircle2 size={15} className="shrink-0 text-rail-green" />
                  ) : (
                    <Circle size={15} className={`shrink-0 ${isNext ? 'text-rail-purple' : 'text-[#6b6b7b]'}`} />
                  )}
                  <span
                    className={`flex-1 truncate text-[12px] ${isDone ? 'text-[#A0A0B0] line-through' : 'text-white/85'}`}
                  >
                    {step.label}
                  </span>
                  <span className="hidden truncate text-[10px] text-[#6B6B78] sm:block">
                    {step.description}
                  </span>
                  <step.icon size={12} className="shrink-0 text-[#6B6B78]" />
                </Link>
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}
