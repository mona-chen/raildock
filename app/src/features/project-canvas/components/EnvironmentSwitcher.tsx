import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Check, ChevronDown, Plus, Settings2, Sparkles } from 'lucide-react'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { useCreateEnvironment } from '@/hooks/useEnvironments'
import type { Environment } from '@/types'

interface EnvironmentSwitcherProps {
  projectId: string
  environments: Environment[]
  activeEnvironmentId?: string
  fallbackName: string
  onSelect: (environmentId: string) => void
}

/**
 * Environment switcher, mirroring Railway's `production ⌄` control: the current
 * environment is a menu (not a static label), every environment in the project
 * is listed, and a new one can be created without leaving the canvas.
 */
export default function EnvironmentSwitcher({
  projectId,
  environments,
  activeEnvironmentId,
  fallbackName,
  onSelect,
}: EnvironmentSwitcherProps) {
  const navigate = useNavigate()
  const createEnvironment = useCreateEnvironment()
  const [showCreate, setShowCreate] = useState(false)
  const [name, setName] = useState('')

  const active = environments.find((environment) => environment.id === activeEnvironmentId)
  const label = active?.name || fallbackName || 'production'

  const handleCreate = () => {
    const trimmed = name.trim()
    if (!trimmed) return
    createEnvironment.mutate(
      { projectId, data: { name: trimmed } },
      {
        onSuccess: (environment) => {
          setShowCreate(false)
          setName('')
          onSelect(environment.id)
        },
      },
    )
  }

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            className="flex items-center gap-1 rounded-lg px-1.5 py-1 text-[12px] text-white/60 hover:bg-white/[0.06] focus:outline-none focus-visible:ring-1 focus-visible:ring-[#8b5cf6]"
            aria-label={`Switch environment (currently ${label})`}
          >
            <span className="max-w-[140px] truncate">{label}</span>
            <ChevronDown size={12} className="text-white/40" />
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent
          align="start"
          className="min-w-[230px] border-white/[0.08] bg-[#1a1a1e] text-white/80"
        >
          <DropdownMenuLabel className="text-[10px] uppercase tracking-[0.12em] text-white/30">
            Environments
          </DropdownMenuLabel>
          {environments.map((environment) => {
            const isActive = environment.id === activeEnvironmentId
            return (
              <DropdownMenuItem
                key={environment.id}
                onClick={() => onSelect(environment.id)}
                className="cursor-pointer text-[12px] focus:bg-white/[0.08] focus:text-white"
              >
                <span className="flex min-w-0 flex-1 flex-col">
                  <span className="flex items-center gap-1.5 truncate">
                    {environment.name}
                    {environment.isDefault && (
                      <span className="rounded bg-white/[0.06] px-1 py-px text-[9px] uppercase tracking-wide text-white/35">
                        default
                      </span>
                    )}
                  </span>
                  <span className="text-[10px] text-white/30">
                    {environment.serviceCount ?? 0} service{(environment.serviceCount ?? 0) === 1 ? '' : 's'}
                  </span>
                </span>
                {isActive && <Check size={13} className="text-rail-purple" />}
              </DropdownMenuItem>
            )
          })}
          {environments.length === 0 && (
            <div className="px-2 py-1.5 text-[12px] text-white/40">No environments yet</div>
          )}
          <DropdownMenuSeparator className="bg-white/[0.08]" />
          <DropdownMenuItem
            onClick={() => setShowCreate(true)}
            className="cursor-pointer text-[12px] focus:bg-white/[0.08] focus:text-white"
          >
            <Plus size={13} className="text-rail-purple" />
            New environment
          </DropdownMenuItem>
          <DropdownMenuItem
            onClick={() => navigate(`/dashboard/project/${projectId}/settings`)}
            className="cursor-pointer text-[12px] focus:bg-white/[0.08] focus:text-white"
          >
            <Settings2 size={13} className="text-white/50" />
            Manage environments
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <Dialog open={showCreate} onOpenChange={(open) => { setShowCreate(open); if (!open) setName('') }}>
        <DialogContent className="max-w-[420px]">
          <DialogHeader>
            <DialogTitle>New environment</DialogTitle>
            <DialogDescription>
              Environments isolate a copy of this project&apos;s configuration so changes never reach
              production by accident. Services are added to the new environment explicitly.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-1.5">
            <label htmlFor="environment-name" className="text-[11px] text-[#8a8a99]">
              Environment name
            </label>
            <input
              id="environment-name"
              value={name}
              autoFocus
              onChange={(event) => setName(event.target.value)}
              onKeyDown={(event) => { if (event.key === 'Enter') handleCreate() }}
              placeholder="staging"
              className="w-full rounded-lg border border-[rgba(255,255,255,0.08)] bg-[#0B0B0D] px-3 py-2.5 text-sm text-white outline-none transition-colors focus:border-[rgba(139,92,246,0.5)]"
            />
            <p className="flex items-center gap-1.5 pt-1 text-[10px] text-white/30">
              <Sparkles size={11} className="text-rail-purple" />
              Preview environments from pull requests are not enabled yet.
            </p>
          </div>
          <DialogFooter>
            <button
              type="button"
              onClick={() => setShowCreate(false)}
              className="rounded-lg border border-[rgba(255,255,255,0.08)] px-3 py-2 text-[12px] text-[#A0A0B0] transition-colors hover:bg-[rgba(255,255,255,0.04)]"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleCreate}
              disabled={!name.trim() || createEnvironment.isPending}
              className="rounded-lg bg-rail-purple px-3 py-2 text-[12px] font-medium text-white transition-colors hover:bg-rail-purple-dark disabled:cursor-not-allowed disabled:opacity-40"
            >
              {createEnvironment.isPending ? 'Creating…' : 'Create environment'}
            </button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}
