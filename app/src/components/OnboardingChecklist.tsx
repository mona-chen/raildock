import { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { CheckCircle2, Circle, Server, Folder, Box, Rocket, X, ChevronRight } from 'lucide-react'
import { useServers } from '@/hooks/useServers'
import { useProjects } from '@/hooks/useProjects'

const STORAGE_KEY = 'raildock-onboarding-dismissed'

interface Step {
  id: string
  label: string
  description: string
  icon: React.ElementType
  link: string
}

export default function OnboardingChecklist() {
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

  const steps: Step[] = [
    {
      id: 'server',
      label: 'Connect a server',
      description: 'Link your Dokku host via SSH',
      icon: Server,
      link: '/dashboard/servers',
    },
    {
      id: 'project',
      label: 'Create a project',
      description: 'Organize your apps and databases',
      icon: Folder,
      link: '/dashboard/projects',
    },
    {
      id: 'service',
      label: 'Add a service',
      description: 'Deploy an app or provision a database',
      icon: Box,
      link: '/dashboard/projects',
    },
    {
      id: 'deploy',
      label: 'Deploy',
      description: 'Push code and watch it go live',
      icon: Rocket,
      link: '/dashboard/projects',
    },
  ]

  // Compute completion state
  const checks: Record<string, boolean> = {
    server: servers.length > 0,
    project: projects.length > 0,
    service: projects.some((p) => (p.serviceIds?.length || 0) > 0),
    deploy: false, // Would need deployment query — keep simple for now
  }

  const completedCount = steps.filter((s) => checks[s.id]).length
  const allCompleted = completedCount === steps.length

  if (dismissed || allCompleted) return null

  return (
    <div className="mb-6 bg-[rgba(139,92,246,0.04)] border border-[rgba(139,92,246,0.12)] rounded-xl p-4">
      <div className="flex items-center justify-between mb-3">
        <div>
          <h2 className="text-sm font-semibold text-white">Getting Started</h2>
          <p className="text-[11px] text-[#4A4A55] mt-0.5">
            {completedCount === 0
              ? 'Complete these steps to deploy your first app'
              : `${completedCount} of ${steps.length} completed — keep going!`}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setExpanded(!expanded)}
            className="text-[#4A4A55] hover:text-[#A0A0B0] transition-colors"
          >
            <ChevronRight
              size={16}
              className={`transition-transform ${expanded ? 'rotate-90' : ''}`}
            />
          </button>
          <button
            onClick={handleDismiss}
            className="text-[#4A4A55] hover:text-[#A0A0B0] transition-colors"
            title="Dismiss"
          >
            <X size={14} />
          </button>
        </div>
      </div>

      {expanded && (
        <div className="space-y-1">
          {steps.map((step, index) => {
            const isDone = checks[step.id]
            const isNext = !isDone && steps.slice(0, index).every((s) => checks[s.id])

            return (
              <Link
                key={step.id}
                to={step.link}
                className={`flex items-center gap-3 p-2.5 rounded-lg transition-all ${
                  isDone
                    ? 'opacity-50'
                    : isNext
                    ? 'bg-[rgba(139,92,246,0.06)] hover:bg-[rgba(139,92,246,0.1)]'
                    : 'hover:bg-[rgba(255,255,255,0.02)]'
                }`}
              >
                {isDone ? (
                  <CheckCircle2 size={16} className="text-rail-green shrink-0" />
                ) : (
                  <Circle size={16} className={`shrink-0 ${isNext ? 'text-rail-purple' : 'text-[#4A4A55]'}`} />
                )}
                <div className="flex-1 min-w-0">
                  <div className={`text-xs font-medium ${isDone ? 'text-[#A0A0B0] line-through' : 'text-white'}`}>
                    {step.label}
                  </div>
                  <div className="text-[10px] text-[#4A4A55]">{step.description}</div>
                </div>
                <step.icon size={14} className="text-[#4A4A55] shrink-0" />
              </Link>
            )
          })}
        </div>
      )}

      {/* Progress bar */}
      <div className="mt-3 h-1 bg-[rgba(255,255,255,0.04)] rounded-full overflow-hidden">
        <div
          className="h-full bg-rail-purple rounded-full transition-all"
          style={{ width: `${(completedCount / steps.length) * 100}%` }}
        />
      </div>
    </div>
  )
}
