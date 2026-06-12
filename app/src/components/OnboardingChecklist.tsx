import { useState, useEffect, useMemo } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import {
  CheckCircle2,
  Circle,
  Server,
  Folder,
  Box,
  Rocket,
  X,
  ChevronRight,
  Sparkles,
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

export default function OnboardingChecklist() {
  const navigate = useNavigate()
  const [dismissed, setDismissed] = useState(false)
  const [expanded, setExpanded] = useState(true)
  const { data: servers = [] } = useServers()
  const { data: projects = [] } = useProjects()

  useEffect(() => {
    setDismissed(localStorage.getItem(STORAGE_KEY) === 'true')
  }, [])

  const handleDismiss = () => {
    localStorage.setItem(STORAGE_KEY, 'true')
    setDismissed(true)
  }

  const steps: Step[] = useMemo(
    () => [
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
    ],
    []
  )

  // Compute completion state
  const checks: Record<string, boolean> = useMemo(
    () => ({
      server: servers.some((s) => s.status === 'connected'),
      project: projects.length > 0,
      service: projects.some((p) => (p.serviceCounts?.total || p.serviceIds?.length || 0) > 0),
      deploy: projects.some((p) => p.has_deployments),
    }),
    [servers, projects]
  )

  const completedCount = steps.filter((s) => checks[s.id]).length
  const allCompleted = completedCount === steps.length

  const nextStep = useMemo(() => steps.find((s) => !checks[s.id]), [steps, checks])

  const getStepHref = (step: Step): string => {
    if (step.id === 'server') return '/dashboard/servers'
    if (step.id === 'project') return '/dashboard/projects'
    const firstProject = projects[0]
    if (firstProject) return `/dashboard/project/${firstProject.id}`
    return '/dashboard/projects'
  }

  const handlePrimaryAction = () => {
    if (!nextStep) return
    navigate(getStepHref(nextStep))
  }

  if (dismissed || allCompleted) return null

  return (
    <div className="mb-6 rounded-xl border border-[rgba(139,92,246,0.12)] bg-gradient-to-br from-[rgba(139,92,246,0.06)] to-[rgba(139,92,246,0.02)] p-4">
      <div className="flex items-start justify-between gap-4">
        <div className="flex items-start gap-3">
          <div className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-lg border border-[rgba(139,92,246,0.18)] bg-[rgba(139,92,246,0.1)]">
            <Sparkles size={16} className="text-rail-purple" />
          </div>
          <div>
            <h2 className="text-sm font-semibold text-white">Getting Started</h2>
            <p className="mt-0.5 text-[11px] text-[#6B6B78]">
              {completedCount === 0
                ? 'Complete these steps to deploy your first app'
                : `${completedCount} of ${steps.length} completed — keep going!`}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-1">
          <button
            onClick={() => setExpanded(!expanded)}
            className="rounded p-1 text-[#4A4A55] transition-colors hover:bg-white/[0.04] hover:text-[#A0A0B0]"
            title={expanded ? 'Collapse' : 'Expand'}
          >
            <ChevronRight
              size={16}
              className={`transition-transform ${expanded ? 'rotate-90' : ''}`}
            />
          </button>
          <button
            onClick={handleDismiss}
            className="rounded p-1 text-[#4A4A55] transition-colors hover:bg-white/[0.04] hover:text-[#A0A0B0]"
            title="Dismiss"
          >
            <X size={14} />
          </button>
        </div>
      </div>

      {expanded && (
        <>
          <div className="mt-4 space-y-1.5">
            {steps.map((step, index) => {
              const isDone = checks[step.id]
              const isNext = !isDone && steps.slice(0, index).every((s) => checks[s.id])
              const href = getStepHref(step)

              return (
                <Link
                  key={step.id}
                  to={href}
                  className={`group flex items-center gap-3 rounded-lg border p-2.5 transition-all ${
                    isDone
                      ? 'border-transparent bg-white/[0.02] opacity-60'
                      : isNext
                        ? 'border-[rgba(139,92,246,0.16)] bg-[rgba(139,92,246,0.06)] hover:bg-[rgba(139,92,246,0.1)]'
                        : 'border-transparent bg-white/[0.02] hover:bg-white/[0.04]'
                  }`}
                >
                  <div className="shrink-0">
                    {isDone ? (
                      <CheckCircle2 size={18} className="text-rail-green" />
                    ) : (
                      <Circle
                        size={18}
                        className={`${isNext ? 'text-rail-purple' : 'text-[#4A4A55]'}`}
                      />
                    )}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div
                      className={`text-xs font-medium ${
                        isDone ? 'text-[#A0A0B0] line-through' : 'text-white'
                      }`}
                    >
                      {step.label}
                    </div>
                    <div className="text-[10px] text-[#6B6B78]">{step.description}</div>
                  </div>
                  <div className="flex items-center gap-2">
                    <step.icon
                      size={14}
                      className={`shrink-0 ${isDone ? 'text-[#4A4A55]' : 'text-[#6B6B78] group-hover:text-white/60'}`}
                    />
                    <ChevronRight
                      size={12}
                      className="shrink-0 text-[#4A4A55] opacity-0 transition-opacity group-hover:opacity-100"
                    />
                  </div>
                </Link>
              )
            })}
          </div>

          {nextStep && (
            <div className="mt-4 flex items-center justify-between">
              <div className="h-1.5 flex-1 rounded-full bg-white/[0.04] overflow-hidden mr-4">
                <div
                  className="h-full rounded-full bg-rail-purple transition-all"
                  style={{ width: `${(completedCount / steps.length) * 100}%` }}
                />
              </div>
              <button
                onClick={handlePrimaryAction}
                className="shrink-0 flex items-center gap-1.5 rounded-lg bg-rail-purple px-3 py-1.5 text-[11px] font-medium text-white hover:bg-rail-purple-dark transition-colors"
              >
                {nextStep.action}
                <ChevronRight size={12} />
              </button>
            </div>
          )}
        </>
      )}
    </div>
  )
}
