import { useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Settings, Puzzle, Building2, Plus, Trash2, Users, Key, FolderGit2, RefreshCw, ArrowUpCircle, Rocket } from 'lucide-react'
import { useCopy } from '@/hooks/useCopy'
import { useModules } from '@/hooks/useModules'
import { useOrganizations, useCreateOrganization, useDeleteOrganization } from '@/hooks/useOrganizations'
import { useDeployKeys, useCreateDeployKey, useDeleteDeployKey } from '@/hooks/useDeployKeys'
import { useAuthStore } from '@/stores/useAuthStore'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import GitSourcesTab from '@/features/settings/GitSourcesTab'
import { updateApi } from '@/lib/api'
import { toast } from 'sonner'
import type { AppUpdateInfo } from '@/types'

const TABS = [
  { key: 'integrations', label: 'Integrations', icon: Puzzle },
  { key: 'git-sources', label: 'Git Sources', icon: FolderGit2 },
  { key: 'organizations', label: 'Organizations', icon: Building2 },
  { key: 'deploy-keys', label: 'Deploy Keys', icon: Key },
  { key: 'updates', label: 'Updates', icon: ArrowUpCircle },
]

export default function SettingsPage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const activeTab = searchParams.get('tab') || 'integrations'
  const { data: modules = [] } = useModules()

  return (
    <div className="h-full flex flex-col overflow-hidden">
      <div className="px-6 py-4 border-b border-[rgba(255,255,255,0.06)]">
        <div className="flex items-center gap-3">
          <Settings size={18} className="text-rail-purple" />
          <h1 className="text-base font-semibold text-white">Platform Settings</h1>
        </div>
        <div className="flex gap-4 mt-3">
          {TABS.map((tab) => (
            <button
              type="button"
              key={tab.key}
              onClick={() => setSearchParams({ tab: tab.key })}
              className={`text-xs font-medium pb-1 border-b-2 transition-colors ${
                activeTab === tab.key
                  ? 'text-rail-purple border-rail-purple'
                  : 'text-[#4A4A55] border-transparent hover:text-[#A0A0B0]'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-6">
        {activeTab === 'integrations' && (
          <div className="max-w-3xl space-y-5">
            {/* Installed Modules */}
            <div className="bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-xl p-5">
              <div className="text-[10px] text-[#4A4A55] uppercase tracking-wider font-medium mb-3 flex items-center gap-2">
                <Puzzle size={12} className="text-rail-purple" /> Modules
              </div>
              <div className="space-y-2">
                {modules.map((mod) => (
                  <div key={mod.id} className="flex items-center justify-between p-3 bg-[rgba(255,255,255,0.02)] rounded-lg">
                    <div>
                      <div className="text-sm text-white">{mod.name}</div>
                      <div className="text-[10px] text-[#4A4A55]">{mod.description}</div>
                    </div>
                    <div className="flex gap-1">
                      {mod.services.map((s) => (
                        <span key={s.subtype} className="text-[9px] px-1.5 py-0.5 bg-[rgba(139,92,246,0.08)] text-rail-purple rounded capitalize">{s.subtype}</span>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}

        {activeTab === 'git-sources' && <GitSourcesTab />}
        {activeTab === 'organizations' && <OrganizationsTab />}
        {activeTab === 'deploy-keys' && <DeployKeysTab />}
        {activeTab === 'updates' && <UpdatesTab />}
      </div>
    </div>
  )
}

function UpdatesTab() {
  const queryClient = useQueryClient()
  const [applying, setApplying] = useState(false)

  const { data: updateInfo, isLoading, isError } = useQuery<AppUpdateInfo>({
    queryKey: ['app-update'],
    queryFn: () => updateApi.getInfo(),
    staleTime: 30_000,
  })

  const checkMutation = useMutation({
    mutationFn: () => updateApi.check(),
    onSuccess: (data) => {
      queryClient.setQueryData(['app-update'], data)
      if (data.updateAvailable) {
        toast.success(`Update available: v${data.latestVersion}`)
      } else {
        toast.success("You're up to date")
      }
    },
    onError: (err: Error) => toast.error(`Check failed: ${err.message}`),
  })

  const toggleAutoUpdate = useMutation({
    mutationFn: (enabled: boolean) => updateApi.setAutoUpdate(enabled),
    onSuccess: (data) => {
      queryClient.setQueryData(['app-update'], (old: AppUpdateInfo | undefined) =>
        old ? { ...old, autoUpdateEnabled: data.autoUpdateEnabled } : old
      )
      toast.success(data.autoUpdateEnabled ? 'Auto-update enabled' : 'Auto-update disabled')
    },
    onError: (err: Error) => toast.error(`Failed: ${err.message}`),
  })

  const handleApply = async () => {
    setApplying(true)
    try {
      const result = await updateApi.apply()
      if (result.success) {
        toast.success(result.message || 'Update applied — restarting now')
      } else {
        toast.error(result.error || 'Update failed')
      }
      queryClient.invalidateQueries({ queryKey: ['app-update'] })
    } catch (err) {
      toast.error(`Apply failed: ${err instanceof Error ? err.message : 'Unknown error'}`)
    } finally {
      setApplying(false)
    }
  }

  const formatDate = (iso: string | null) => {
    if (!iso) return 'Not yet checked'
    try {
      return new Date(iso).toLocaleString()
    } catch {
      return iso
    }
  }

  const hasChecked = !!updateInfo?.checkedAt

  return (
    <div className="max-w-3xl space-y-5">
      <div className="bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-xl p-5">
        <div className="text-[10px] text-[#4A4A55] uppercase tracking-wider font-medium mb-4 flex items-center gap-2">
          <ArrowUpCircle size={12} className="text-rail-purple" /> Version & Updates
        </div>

        {isLoading ? (
          <div className="text-[11px] text-[#4A4A55]">Loading...</div>
        ) : isError ? (
          <div className="text-[11px] text-red-400">Failed to load update info</div>
        ) : updateInfo ? (
          <div className="space-y-4">
            {/* Current version + last checked */}
            <div className="flex items-center justify-between p-3 bg-[rgba(255,255,255,0.02)] rounded-lg">
              <div>
                <div className="text-[11px] text-[#4A4A55]">Current Version</div>
                <div className="text-sm text-white font-mono mt-0.5">{updateInfo.currentVersion}</div>
              </div>
              <div className="text-[10px] text-[#4A4A55] text-right">
                Last checked: <span className="text-white/60">{formatDate(updateInfo.checkedAt)}</span>
              </div>
            </div>

            {/* Update available banner */}
            {updateInfo.updateAvailable ? (
              <div className="p-3 bg-[rgba(34,197,94,0.08)] border border-[rgba(34,197,94,0.2)] rounded-lg">
                <div className="flex items-center justify-between gap-3">
                  <div className="min-w-0">
                    <div className="text-sm text-green-400 font-medium flex items-center gap-2">
                      Update Available
                      {updateInfo.prerelease && (
                        <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-amber-500/15 text-amber-400 font-medium uppercase tracking-wider">
                          Pre-release
                        </span>
                      )}
                    </div>
                    <div className="text-[11px] text-[#A0A0B0] mt-0.5">
                      Version <span className="font-mono text-white/80">{updateInfo.latestVersion}</span> is available
                      {updateInfo.publishedAt && <> (released {formatDate(updateInfo.publishedAt)})</>}
                    </div>
                  </div>
                  {updateInfo.releaseUrl && (
                    <a
                      href={updateInfo.releaseUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-[11px] text-rail-purple hover:text-rail-purple/80 underline shrink-0"
                    >
                      Release Notes
                    </a>
                  )}
                </div>
              </div>
            ) : hasChecked ? (
              <div className="p-3 bg-[rgba(255,255,255,0.02)] rounded-lg">
                <div className="text-sm text-[#A0A0B0]">You're up to date</div>
                {updateInfo.latestVersion && (
                  <div className="text-[11px] text-[#4A4A55] mt-0.5">
                    Latest available: <span className="font-mono text-white/60">{updateInfo.latestVersion}</span>
                  </div>
                )}
              </div>
            ) : null}

            {/* Actions */}
            <div className="flex items-center gap-3 pt-2">
              <Button
                size="sm"
                onClick={() => checkMutation.mutate()}
                disabled={checkMutation.isPending}
                className="bg-[rgba(255,255,255,0.06)] hover:bg-[rgba(255,255,255,0.1)] text-white text-xs h-8"
              >
                <RefreshCw size={12} className={`mr-1.5 ${checkMutation.isPending ? 'animate-spin' : ''}`} />
                {checkMutation.isPending ? 'Checking...' : 'Check for Updates'}
              </Button>

              {updateInfo.updateAvailable && updateInfo.canApply && (
                <Button
                  size="sm"
                  onClick={handleApply}
                  disabled={applying}
                  className="bg-rail-purple hover:bg-rail-purple/90 text-white text-xs h-8"
                >
                  <Rocket size={12} className="mr-1.5" />
                  {applying ? 'Applying...' : 'Apply Update'}
                </Button>
              )}

              {updateInfo.updateAvailable && !updateInfo.canApply && (
                <div className="p-3 bg-[rgba(245,158,11,0.08)] border border-[rgba(245,158,11,0.2)] rounded-lg">
                  <div className="text-[11px] text-amber-400 font-medium mb-1">Manual update required</div>
                  <div className="text-[10px] text-[#A0A0B0] mb-2">
                    RailDock is running inside a container without host access. Run this on the host:
                  </div>
                  <code className="block text-[10px] font-mono text-white/80 bg-black/30 rounded px-2 py-1.5">
                    cd /opt/raildock && ./install.sh update
                  </code>
                </div>
              )}
            </div>
          </div>
        ) : null}
      </div>

      {/* Auto-update settings */}
      <div className="bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-xl p-5">
        <div className="text-[10px] text-[#4A4A55] uppercase tracking-wider font-medium mb-4 flex items-center gap-2">
          <RefreshCw size={12} className="text-rail-purple" /> Auto-Update
        </div>
        <div className="flex items-center justify-between p-3 bg-[rgba(255,255,255,0.02)] rounded-lg gap-4">
          <div className="min-w-0">
            <div className="text-sm text-white">Automatic Updates</div>
            <div className="text-[11px] text-[#4A4A55] mt-0.5">
              When enabled, RailDock checks for updates every 6 hours and applies them automatically.
            </div>
          </div>
          <button
            type="button"
            onClick={() => toggleAutoUpdate.mutate(!updateInfo?.autoUpdateEnabled)}
            disabled={toggleAutoUpdate.isPending}
            aria-pressed={updateInfo?.autoUpdateEnabled ?? false}
            className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors shrink-0 ${
              updateInfo?.autoUpdateEnabled
                ? 'bg-rail-purple'
                : 'bg-[rgba(255,255,255,0.1)]'
            }`}
          >
            <span
              className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                updateInfo?.autoUpdateEnabled ? 'translate-x-6' : 'translate-x-1'
              }`}
            />
          </button>
        </div>
      </div>
    </div>
  )
}

function DeployKeysTab() {
  const { data: keys = [], isLoading } = useDeployKeys()
  const createKey = useCreateDeployKey()
  const deleteKey = useDeleteDeployKey()
  const [name, setName] = useState('')
  const [dialogOpen, setDialogOpen] = useState(false)
  const { copiedKey, copy } = useCopy(2000)

  const handleCreate = () => {
    if (!name.trim()) return
    createKey.mutate({ name: name.trim() }, {
      onSuccess: () => {
        setName('')
        setDialogOpen(false)
      },
    })
  }

  return (
    <div className="max-w-3xl space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-sm font-medium text-white">Deploy Keys</h2>
          <p className="text-[11px] text-[#4A4A55] mt-0.5">SSH keys for cloning private repositories</p>
        </div>
        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
          <DialogTrigger asChild>
            <Button size="sm" className="bg-rail-purple hover:bg-rail-purple/90 text-white text-xs h-8">
              <Plus size={14} className="mr-1" />
              New Key
            </Button>
          </DialogTrigger>
          <DialogContent className="bg-[#161618] border-[rgba(255,255,255,0.06)] text-[#F0F1F3]">
            <DialogHeader>
              <DialogTitle className="text-sm">Create Deploy Key</DialogTitle>
              <DialogDescription className="text-[11px] text-[#4A4A55]">
                Generates a new ED25519 SSH key pair. The private key is stored encrypted.
              </DialogDescription>
            </DialogHeader>
            <div className="py-2">
              <label className="text-[11px] text-[#A0A0B0] mb-1 block">Name</label>
              <Input
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="production-server"
                className="bg-[rgba(255,255,255,0.04)] border-[rgba(255,255,255,0.08)] text-sm h-9"
              />
            </div>
            <DialogFooter>
              <Button
                onClick={handleCreate}
                disabled={createKey.isPending || !name.trim()}
                className="bg-rail-purple hover:bg-rail-purple/90 text-white text-xs"
              >
                {createKey.isPending ? 'Generating...' : 'Generate'}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>

      {isLoading ? (
        <div className="text-[11px] text-[#4A4A55]">Loading...</div>
      ) : keys.length === 0 ? (
        <div className="bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-xl p-8 text-center">
          <Key size={24} className="text-[#4A4A55] mx-auto mb-2" />
          <p className="text-sm text-[#A0A0B0]">No deploy keys yet</p>
          <p className="text-[11px] text-[#4A4A55] mt-1">Create one to deploy from private Git repos via SSH.</p>
        </div>
      ) : (
        <div className="space-y-2">
          {keys.map((key) => (
            <div
              key={key.id}
              className="flex flex-col gap-2 p-4 rounded-xl border bg-[rgba(255,255,255,0.02)] border-[rgba(255,255,255,0.05)]"
            >
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <Key size={14} className="text-rail-purple" />
                  <span className="text-sm text-white font-medium">{key.name}</span>
                </div>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => {
                    if (confirm(`Delete "${key.name}"? This cannot be undone.`)) {
                      deleteKey.mutate(key.id)
                    }
                  }}
                  className="text-[11px] text-[#4A4A55] hover:text-red-400 h-7"
                >
                  <Trash2 size={13} />
                </Button>
              </div>
              <div className="text-[10px] text-[#4A4A55]">Fingerprint: {key.fingerprint}</div>
              <div className="flex items-center gap-2">
                <code className="flex-1 text-[10px] font-mono text-[#A0A0B0] bg-[rgba(255,255,255,0.03)] rounded px-2 py-1 truncate">
                  {key.publicKey}
                </code>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => copy(key.publicKey, key.id)}
                  className="text-[10px] text-[#A0A0B0] hover:text-white h-7 shrink-0"
                >
                  {copiedKey === key.id ? 'Copied!' : 'Copy'}
                </Button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

function OrganizationsTab() {
  const { data: organizations = [], isLoading } = useOrganizations()
  const createOrg = useCreateOrganization()
  const deleteOrg = useDeleteOrganization()
  const { currentOrganizationId, setCurrentOrganizationId } = useAuthStore()
  const [name, setName] = useState('')
  const [slug, setSlug] = useState('')
  const [dialogOpen, setDialogOpen] = useState(false)

  const handleCreate = () => {
    if (!name.trim() || !slug.trim()) return
    createOrg.mutate({ name: name.trim(), slug: slug.trim() }, {
      onSuccess: () => {
        setName('')
        setSlug('')
        setDialogOpen(false)
      },
    })
  }

  return (
    <div className="max-w-3xl space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-sm font-medium text-white">Organizations</h2>
          <p className="text-[11px] text-[#4A4A55] mt-0.5">Manage teams and shared resources</p>
        </div>
        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
          <DialogTrigger asChild>
            <Button size="sm" className="bg-rail-purple hover:bg-rail-purple/90 text-white text-xs h-8">
              <Plus size={14} className="mr-1" />
              New Organization
            </Button>
          </DialogTrigger>
          <DialogContent className="bg-[#161618] border-[rgba(255,255,255,0.06)] text-[#F0F1F3]">
            <DialogHeader>
              <DialogTitle className="text-sm">Create Organization</DialogTitle>
              <DialogDescription className="text-[11px] text-[#4A4A55]">
                Organizations let you share projects and git sources with your team.
              </DialogDescription>
            </DialogHeader>
            <div className="space-y-3 py-2">
              <div>
                <label className="text-[11px] text-[#A0A0B0] mb-1 block">Name</label>
                <Input
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="Acme Corp"
                  className="bg-[rgba(255,255,255,0.04)] border-[rgba(255,255,255,0.08)] text-sm h-9"
                />
              </div>
              <div>
                <label className="text-[11px] text-[#A0A0B0] mb-1 block">Slug</label>
                <Input
                  value={slug}
                  onChange={(e) => setSlug(e.target.value)}
                  placeholder="acme-corp"
                  className="bg-[rgba(255,255,255,0.04)] border-[rgba(255,255,255,0.08)] text-sm h-9"
                />
              </div>
            </div>
            <DialogFooter>
              <Button
                onClick={handleCreate}
                disabled={createOrg.isPending || !name.trim() || !slug.trim()}
                className="bg-rail-purple hover:bg-rail-purple/90 text-white text-xs"
              >
                {createOrg.isPending ? 'Creating...' : 'Create'}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>

      {isLoading ? (
        <div className="text-[11px] text-[#4A4A55]">Loading...</div>
      ) : organizations.length === 0 ? (
        <div className="bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-xl p-8 text-center">
          <Building2 size={24} className="text-[#4A4A55] mx-auto mb-2" />
          <p className="text-sm text-[#A0A0B0]">No organizations yet</p>
          <p className="text-[11px] text-[#4A4A55] mt-1">Create one to share projects with your team.</p>
        </div>
      ) : (
        <div className="space-y-2">
          {organizations.map((org) => (
            <div
              key={org.id}
              className={`flex items-center justify-between p-4 rounded-xl border transition-colors ${
                currentOrganizationId === org.id
                  ? 'bg-[rgba(139,92,246,0.06)] border-[rgba(139,92,246,0.2)]'
                  : 'bg-[rgba(255,255,255,0.02)] border-[rgba(255,255,255,0.05)]'
              }`}
            >
              <div className="flex items-center gap-3">
                <div className="w-8 h-8 rounded-lg bg-[rgba(139,92,246,0.12)] flex items-center justify-center text-rail-purple text-xs font-bold">
                  {org.name.slice(0, 2).toUpperCase()}
                </div>
                <div>
                  <div className="text-sm text-white font-medium">{org.name}</div>
                  <div className="text-[10px] text-[#4A4A55] flex items-center gap-2">
                    <span>@{org.slug}</span>
                    <span className="flex items-center gap-1">
                      <Users size={10} />
                      {org.memberCount ?? 1} members
                    </span>
                  </div>
                </div>
              </div>
              <div className="flex items-center gap-2">
                {currentOrganizationId === org.id ? (
                  <span className="text-[10px] px-2 py-0.5 rounded-full bg-rail-purple/10 text-rail-purple">Active</span>
                ) : (
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => setCurrentOrganizationId(org.id)}
                    className="text-[11px] text-[#A0A0B0] hover:text-white h-7"
                  >
                    Switch
                  </Button>
                )}
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => {
                    if (confirm(`Delete "${org.name}"? This cannot be undone.`)) {
                      deleteOrg.mutate(org.id)
                      if (currentOrganizationId === org.id) setCurrentOrganizationId(null)
                    }
                  }}
                  className="text-[11px] text-[#4A4A55] hover:text-red-400 h-7"
                >
                  <Trash2 size={13} />
                </Button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
