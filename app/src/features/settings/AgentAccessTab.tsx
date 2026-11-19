import { useMemo, useState } from 'react'
import { Bot, Copy, KeyRound, Plus, ShieldAlert } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Checkbox } from '@/components/ui/checkbox'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import ConfirmDialog from '@/features/shared/ConfirmDialog'
import { useCopy } from '@/hooks/useCopy'
import { useProjects } from '@/hooks/useProjects'
import { useApiTokens, useCreateApiToken, useRevokeApiToken } from '@/hooks/useApiTokens'
import { useAuthStore } from '@/stores/useAuthStore'
import type { ApiToken, ApiTokenScope, CreatedApiToken } from '@/types'
import { SettingsSection } from './SettingsSection'

const SCOPES: Array<{ value: ApiTokenScope; label: string; description: string }> = [
  {
    value: 'read',
    label: 'Read',
    description: 'Context, services, logs, metrics and diagnosis. Always included.',
  },
  {
    value: 'deploy',
    label: 'Deploy',
    description: 'Deploy, restart, scale and roll back services.',
  },
  {
    value: 'config:write',
    label: 'Configuration',
    description: 'Variables, domains, mounts and manifest edits.',
  },
  {
    value: 'destructive',
    label: 'Destructive',
    description: 'Delete projects, remove services, restore backups. Still requires a typed confirmation.',
  },
]

const EXPIRY_OPTIONS = [
  { value: 'never', label: 'No expiry' },
  { value: '7', label: '7 days' },
  { value: '30', label: '30 days' },
  { value: '90', label: '90 days' },
]

const WRITE_SCOPES: ApiTokenScope[] = ['deploy', 'config:write', 'destructive']

export default function AgentAccessTab() {
  const { data: tokens = [], isLoading, isError, error } = useApiTokens()
  const { data: projects = [] } = useProjects()
  const createToken = useCreateApiToken()
  const revokeToken = useRevokeApiToken()
  const { copiedKey, copy } = useCopy()
  const currentOrganizationId = useAuthStore((state) => state.currentOrganizationId)

  const [createOpen, setCreateOpen] = useState(false)
  const [name, setName] = useState('')
  const [scopes, setScopes] = useState<ApiTokenScope[]>(['read'])
  const [projectId, setProjectId] = useState('all')
  const [environmentId, setEnvironmentId] = useState('all')
  const [expiry, setExpiry] = useState('never')
  const [created, setCreated] = useState<CreatedApiToken | null>(null)
  const [revokeTarget, setRevokeTarget] = useState<ApiToken | null>(null)

  const environments = useMemo(
    () => projects.find((project) => project.id === projectId)?.environments ?? [],
    [projects, projectId],
  )

  function resetForm() {
    setName('')
    setScopes(['read'])
    setProjectId('all')
    setEnvironmentId('all')
    setExpiry('never')
  }

  function toggleScope(scope: ApiTokenScope, checked: boolean) {
    setScopes((current) => {
      const next = checked
        ? [...new Set([...current, scope])]
        : current.filter((entry) => entry !== scope)
      // A write scope is useless without read, so read is implicit and sticky.
      return next.length === 0 ? ['read'] : next
    })
  }

  function submit(event: React.FormEvent) {
    event.preventDefault()
    if (!name.trim()) return

    const expiresAt = expiry === 'never'
      ? null
      : new Date(Date.now() + Number(expiry) * 24 * 60 * 60 * 1000).toISOString()

    createToken.mutate(
      {
        name: name.trim(),
        scopes,
        projectId: projectId === 'all' ? null : projectId,
        environmentId: environmentId === 'all' ? null : environmentId,
        expiresAt,
      },
      {
        onSuccess: (data) => {
          setCreateOpen(false)
          resetForm()
          setCreated(data)
        },
      },
    )
  }

  function binding(token: ApiToken) {
    const project = projects.find((entry) => entry.id === token.projectId)
    if (!project) return 'All projects'
    const environment = (project.environments ?? []).find((entry) => entry.id === token.environmentId)
    return environment ? `${project.name} · ${environment.name}` : project.name
  }

  return (
    <div className="max-w-3xl space-y-5">
      <header className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-[15px] font-medium text-[#eeeeF2]">Agent access</h2>
          <p className="mt-1 max-w-xl text-xs leading-5 text-[#9292a3]">
            Tokens let an agent act as you through the v1 API. The member role still decides what is
            allowed; scopes and a project or environment binding narrow it further. Secrets are shown once.
          </p>
        </div>
        <Button size="sm" onClick={() => setCreateOpen(true)}>
          <Plus className="mr-1.5 h-3.5 w-3.5" />
          Create token
        </Button>
      </header>

      {isLoading && <p className="text-xs text-[#9292a3]">Loading tokens…</p>}

      {isError && (
        <p className="rounded-md border border-red-500/20 bg-red-500/5 px-3 py-2 text-xs text-red-300">
          {error instanceof Error ? error.message : 'Could not load tokens.'}
        </p>
      )}

      {!isLoading && !isError && tokens.length === 0 && (
        <div className="rounded-lg border border-dashed border-white/10 px-5 py-10 text-center">
          <KeyRound className="mx-auto h-5 w-5 text-[#9292a3]" />
          <p className="mt-3 text-sm text-[#d8d8e0]">No tokens yet</p>
          <p className="mx-auto mt-1 max-w-sm text-xs leading-5 text-[#9292a3]">
            Create one to let an agent read context, deploy a service, or diagnose a failed release.
          </p>
        </div>
      )}

      {tokens.length > 0 && (
        <SettingsSection title="Tokens" description="Revoke a token instead of deleting it: audit rows keep resolving.">
          {tokens.map((token) => (
            <div key={token.id} className="flex flex-wrap items-start justify-between gap-3 px-5 py-4">
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-[13px] font-medium text-[#d8d8e0]">{token.name}</span>
                  <code className="rounded bg-white/5 px-1.5 py-0.5 text-[11px] text-[#9292a3]">
                    rd_{token.prefix}…
                  </code>
                  {token.revokedAt && (
                    <span className="rounded bg-red-500/10 px-1.5 py-0.5 text-[11px] text-red-300">Revoked</span>
                  )}
                </div>
                <div className="mt-1.5 flex flex-wrap gap-1.5">
                  {token.scopes.map((scope) => (
                    <span key={scope} className="rounded bg-white/5 px-1.5 py-0.5 text-[11px] text-[#b9b9c6]">
                      {scope}
                    </span>
                  ))}
                </div>
                <p className="mt-1.5 text-xs text-[#9292a3]">
                  {binding(token)} · {token.lastUsedAt ? `Last used ${new Date(token.lastUsedAt).toLocaleString()}` : 'Never used'}
                  {token.expiresAt ? ` · Expires ${new Date(token.expiresAt).toLocaleDateString()}` : ''}
                </p>
              </div>
              {!token.revokedAt && (
                <Button variant="ghost" size="sm" onClick={() => setRevokeTarget(token)}>
                  Revoke
                </Button>
              )}
            </div>
          ))}
        </SettingsSection>
      )}

      <Dialog open={createOpen} onOpenChange={(open) => { setCreateOpen(open); if (!open) resetForm() }}>
        <DialogContent className="sm:max-w-lg">
          <form onSubmit={submit}>
            <DialogHeader>
              <DialogTitle>Create an agent token</DialogTitle>
              <DialogDescription>
                The secret is shown once. Store it where the agent can read it, and revoke it here if it leaks.
              </DialogDescription>
            </DialogHeader>

            <div className="space-y-4 py-4">
              <div className="space-y-1.5">
                <Label htmlFor="token-name">Name</Label>
                <Input
                  id="token-name"
                  value={name}
                  onChange={(event) => setName(event.target.value)}
                  placeholder="Claude Code on my laptop"
                  maxLength={80}
                />
              </div>

              <fieldset className="space-y-2">
                <legend className="text-[13px] font-medium text-[#d8d8e0]">Scopes</legend>
                {SCOPES.map((scope) => (
                  <label
                    key={scope.value}
                    htmlFor={`token-scope-${scope.value}`}
                    className="flex cursor-pointer items-start gap-2.5 rounded-md border border-white/8 px-3 py-2"
                  >
                    <Checkbox
                      id={`token-scope-${scope.value}`}
                      aria-label={scope.label}
                      checked={scopes.includes(scope.value)}
                      disabled={scope.value === 'read'}
                      onCheckedChange={(checked) => toggleScope(scope.value, checked === true)}
                      className="mt-0.5"
                    />
                    <span>
                      <span className="block text-[13px] text-[#d8d8e0]">{scope.label}</span>
                      <span className="block text-xs leading-5 text-[#9292a3]">{scope.description}</span>
                    </span>
                  </label>
                ))}
              </fieldset>

              <div className="grid gap-3 sm:grid-cols-2">
                <div className="space-y-1.5">
                  <Label htmlFor="token-project">Project</Label>
                  <Select
                    value={projectId}
                    onValueChange={(value) => {
                      setProjectId(value)
                      setEnvironmentId('all')
                    }}
                  >
                    <SelectTrigger id="token-project">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">All projects</SelectItem>
                      {projects.map((project) => (
                        <SelectItem key={project.id} value={project.id}>
                          {project.name}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>

                <div className="space-y-1.5">
                  <Label htmlFor="token-environment">Environment</Label>
                  <Select
                    value={environmentId}
                    onValueChange={setEnvironmentId}
                    disabled={projectId === 'all' || environments.length === 0}
                  >
                    <SelectTrigger id="token-environment">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="all">All environments</SelectItem>
                      {environments.map((environment) => (
                        <SelectItem key={environment.id} value={environment.id}>
                          {environment.name}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="token-expiry">Expiry</Label>
                <Select value={expiry} onValueChange={setExpiry}>
                  <SelectTrigger id="token-expiry">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {EXPIRY_OPTIONS.map((option) => (
                      <SelectItem key={option.value} value={option.value}>
                        {option.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              {scopes.some((scope) => WRITE_SCOPES.includes(scope)) && (
                <p className="flex items-start gap-2 rounded-md border border-amber-500/20 bg-amber-500/5 px-3 py-2 text-xs leading-5 text-amber-200">
                  <ShieldAlert className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                  Write scopes let the agent change this organization. Start with read-only and widen only when needed.
                </p>
              )}
            </div>

            <DialogFooter>
              <Button type="button" variant="ghost" onClick={() => setCreateOpen(false)}>
                Cancel
              </Button>
              <Button type="submit" disabled={!name.trim() || createToken.isPending}>
                {createToken.isPending ? 'Creating…' : 'Create token'}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      <Dialog open={!!created} onOpenChange={(open) => { if (!open) setCreated(null) }}>
        <DialogContent className="sm:max-w-xl">
          <DialogHeader>
            <DialogTitle>Copy the secret now</DialogTitle>
            <DialogDescription>
              This is the only time the secret is shown. If you lose it, revoke the token and create another.
            </DialogDescription>
          </DialogHeader>

          {created && (
            <div className="space-y-4 py-1">
              <div className="flex items-center justify-between gap-3 rounded-lg border border-white/6 bg-white/[0.02] px-3 py-2.5">
                <div className="min-w-0">
                  <p className="truncate text-[12px] font-medium text-white/80">{created.token.name}</p>
                  <p className="mt-0.5 truncate text-[10px] text-white/35">
                    {created.token.scopes.join(' · ')} · {created.token.projectId ? 'Project-bound' : 'All projects'}
                  </p>
                </div>
                <code className="shrink-0 rounded bg-white/5 px-1.5 py-0.5 text-[10px] text-white/40">
                  rd_{created.token.prefix}…
                </code>
              </div>

              <div className="space-y-2">
                <div className="flex items-center justify-between gap-3">
                  <Label className="text-[11px] font-medium text-white/55">Secret</Label>
                  <Button variant="secondary" size="sm" onClick={() => copy(created.secret, 'secret')}>
                    <Copy className="mr-1.5 h-3.5 w-3.5" />
                    {copiedKey === 'secret' ? 'Copied' : 'Copy secret'}
                  </Button>
                </div>
                <code className="block select-all break-all rounded-lg border border-rail-purple/25 bg-black/35 px-3.5 py-3 font-mono text-[11px] leading-relaxed text-[#e2e2ea]">
                  {created.secret}
                </code>
              </div>

              <div className="rounded-xl border border-white/8 bg-white/[0.02] p-3.5">
                <p className="flex items-center gap-2 text-[11px] font-medium text-white/60">
                  <Bot size={12} className="text-rail-purple/70" />
                  Use it from your agent
                </p>
                <p className="mt-1.5 text-[11px] leading-relaxed text-[#9292a3]">
                  Send the token as a Bearer credential. Include your organization id if your client asks for it,
                  then call the context endpoint to orient the agent.
                </p>
                <dl className="mt-3 space-y-1.5 font-mono text-[10.5px]">
                  <div className="flex gap-3">
                    <dt className="w-28 shrink-0 text-white/30">Authorization</dt>
                    <dd className="min-w-0 break-all text-white/65">Bearer rd_…</dd>
                  </div>
                  <div className="flex gap-3">
                    <dt className="w-28 shrink-0 text-white/30">X-Organization-ID</dt>
                    <dd className="min-w-0 break-all text-white/65">
                      {currentOrganizationId ?? '<organization id>'}
                    </dd>
                  </div>
                  <div className="flex gap-3">
                    <dt className="w-28 shrink-0 text-white/30">Endpoint</dt>
                    <dd className="min-w-0 break-all text-white/65">GET /api/v1/context</dd>
                  </div>
                </dl>
              </div>
            </div>
          )}

          <DialogFooter>
            <Button onClick={() => setCreated(null)}>Done</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <ConfirmDialog
        open={!!revokeTarget}
        onOpenChange={(open) => { if (!open) setRevokeTarget(null) }}
        title="Revoke this token?"
        description={
          revokeTarget
            ? `${revokeTarget.name} (rd_${revokeTarget.prefix}…) will stop working immediately. This cannot be undone.`
            : undefined
        }
        confirmLabel="Revoke token"
        destructive
        pending={revokeToken.isPending}
        onConfirm={() => {
          if (!revokeTarget) return
          revokeToken.mutate(revokeTarget.id, { onSettled: () => setRevokeTarget(null) })
        }}
      />
    </div>
  )
}
