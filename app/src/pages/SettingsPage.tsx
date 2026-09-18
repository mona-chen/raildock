import { useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Settings, Puzzle, Building2, Plus, Trash2, Users, Key, FolderGit2, RefreshCw, ArrowUpCircle, Rocket, Mail, Cloud, Cog, Search } from 'lucide-react'
import { useCopy } from '@/hooks/useCopy'
import { useModules, useInstallPlugin, useEnablePlugin, useDisablePlugin, useUninstallPlugin, usePluginSettings, useUpdatePluginSettings } from '@/hooks/useModules'
import { useOrganizations, useCreateOrganization, useDeleteOrganization } from '@/hooks/useOrganizations'
import { useDeployKeys, useCreateDeployKey, useDeleteDeployKey } from '@/hooks/useDeployKeys'
import { useAuthStore } from '@/stores/useAuthStore'
import ConfirmDialog from '@/features/shared/ConfirmDialog'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import ConfigSchemaForm from '@/components/ConfigSchemaForm'
import GitSourcesTab from '@/features/settings/GitSourcesTab'
import MembersTab from '@/features/settings/MembersTab'
import BackupDestinationsTab from '@/features/settings/BackupDestinationsTab'
import SmtpConfigPanel from '@/features/settings/SmtpConfigPanel'
import { updateApi } from '@/lib/api'
import { toast } from 'sonner'
import type { AppUpdateInfo, Module } from '@/types'

// Two scopes live here: things the current organization owns, and things that
// are configured once for this RailDock instance. Grouping them stops a user
// from hunting for "Members" among instance-level plugin settings.
const TAB_GROUPS = [
  {
    label: 'Organization',
    tabs: [
      { key: 'members', label: 'Members', icon: Users },
      { key: 'organizations', label: 'Organizations', icon: Building2 },
      { key: 'git-sources', label: 'Git Sources', icon: FolderGit2 },
      { key: 'backup-destinations', label: 'Backups', icon: Cloud },
      { key: 'deploy-keys', label: 'Deploy Keys', icon: Key },
    ],
  },
  {
    label: 'Instance',
    tabs: [
      { key: 'integrations', label: 'Integrations', icon: Puzzle },
      { key: 'email', label: 'Email', icon: Mail },
      { key: 'updates', label: 'Updates', icon: ArrowUpCircle },
    ],
  },
]

export default function SettingsPage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const activeTab = searchParams.get('tab') || 'integrations'
  const { data: modules = [], isLoading: modulesLoading } = useModules()
  const { user } = useAuthStore()
  const isAdmin = user?.admin === true
  const [filter, setFilter] = useState('')

  // Railway-style settings: one list of sections, filterable, one pane at a
  // time. Eight tabs in a horizontal strip is unreadable once it scrolls.
  const query = filter.trim().toLowerCase()
  const groups = TAB_GROUPS
    .map((group) => ({ ...group, tabs: group.tabs.filter((tab) => tab.label.toLowerCase().includes(query)) }))
    .filter((group) => group.tabs.length > 0)
  const activeGroup = TAB_GROUPS.find((group) => group.tabs.some((tab) => tab.key === activeTab))

  return (
    <div className="h-full flex flex-col overflow-hidden">
      <header className="px-6 py-4 border-b border-[rgba(255,255,255,0.06)] flex items-center gap-3">
        <Settings size={18} className="text-rail-purple" />
        <div>
          <h1 className="text-base font-semibold text-white">Settings</h1>
          <p className="text-[11px] text-[#8a8a99] mt-0.5">
            {activeGroup?.label === 'Instance' ? 'This RailDock instance' : 'Your organization workspace'}
          </p>
        </div>
      </header>

      <div className="flex-1 flex min-h-0">
        <aside className="w-[224px] flex-shrink-0 border-r border-[rgba(255,255,255,0.06)] flex flex-col">
          <div className="p-3">
            <div className="relative">
              <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-[#6b6b7b]" />
              <input
                value={filter}
                onChange={(e) => setFilter(e.target.value)}
                placeholder="Filter settings…"
                aria-label="Filter settings"
                className="w-full rounded-lg bg-black/40 border border-white/[0.08] pl-8 pr-2 py-1.5 text-[12px] text-white/80 placeholder:text-[#6b6b7b] focus:outline-none focus:border-rail-purple/40"
              />
            </div>
          </div>
          <nav className="flex-1 overflow-y-auto px-2 pb-3">
            {groups.map((group) => (
              <div key={group.label} className="mb-1">
                <div className="px-2 pt-2 pb-1 text-[10px] uppercase tracking-wider text-[#6b6b7b]">{group.label}</div>
                {group.tabs.map((tab) => {
                  const isActive = activeTab === tab.key
                  return (
                    <button
                      key={tab.key}
                      type="button"
                      onClick={() => setSearchParams({ tab: tab.key })}
                      aria-current={isActive ? 'page' : undefined}
                      className={`w-full flex items-center gap-2 rounded-lg px-2 py-1.5 text-[12.5px] transition-colors ${
                        isActive ? 'bg-white/[0.06] text-white/85' : 'text-[#8a8a99] hover:text-[#A0A0B0] hover:bg-white/[0.03]'
                      }`}
                    >
                      <tab.icon size={14} className={isActive ? 'text-rail-purple' : ''} />
                      {tab.label}
                    </button>
                  )
                })}
              </div>
            ))}
            {groups.length === 0 && (
              <p className="px-2 py-4 text-[11px] text-[#6b6b7b]">No settings match “{filter}”.</p>
            )}
          </nav>
        </aside>

        <div className="flex-1 min-w-0 overflow-y-auto p-6">
          {activeTab === 'integrations' && (
            <PluginManager modules={modules} isLoading={modulesLoading} isAdmin={isAdmin} />
          )}

          {activeTab === 'git-sources' && <GitSourcesTab />}
          {activeTab === 'organizations' && <OrganizationsTab />}
          {activeTab === 'members' && <MembersTab />}
          {activeTab === 'backup-destinations' && <BackupDestinationsTab />}
          {activeTab === 'deploy-keys' && <DeployKeysTab />}
          {activeTab === 'email' && <div className="max-w-3xl"><SmtpConfigPanel /></div>}
          {activeTab === 'updates' && <UpdatesTab />}
        </div>
      </div>
    </div>
  )
}

function PluginManager({ modules, isLoading, isAdmin }: { modules: Module[]; isLoading: boolean; isAdmin: boolean }) {
  const [installOpen, setInstallOpen] = useState(false)
  const [configPlugin, setConfigPlugin] = useState<Module | null>(null)

  return (
    <div className="max-w-3xl space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-sm font-medium text-white">Plugins & Integrations</h2>
          <p className="text-[11px] text-[#6b6b7b] mt-0.5">
            Enable, install, and configure plugins that extend RailDock capabilities.
          </p>
        </div>
        {isAdmin && (
          <Dialog open={installOpen} onOpenChange={setInstallOpen}>
            <DialogTrigger asChild>
              <Button size="sm" className="bg-rail-purple hover:bg-rail-purple/90 text-white text-xs h-8">
                <Plus size={14} className="mr-1" />
                Install Plugin
              </Button>
            </DialogTrigger>
            <DialogContent className="bg-[#161618] border-[rgba(255,255,255,0.06)] text-[#F0F1F3]">
              <InstallPluginDialog onClose={() => setInstallOpen(false)} />
            </DialogContent>
          </Dialog>
        )}
      </div>

      {isLoading ? (
        <div className="text-[11px] text-[#6b6b7b]">Loading plugins...</div>
      ) : (
        <div className="space-y-3">
          {modules.map((mod) => (
            <PluginCard
              key={mod.id}
              mod={mod}
              isAdmin={isAdmin}
              onConfigure={() => setConfigPlugin(mod)}
            />
          ))}
          {modules.length === 0 && (
            <div className="bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-xl p-8 text-center">
              <Puzzle size={24} className="text-[#6b6b7b] mx-auto mb-2" />
              <p className="text-sm text-[#A0A0B0]">No plugins loaded</p>
            </div>
          )}
        </div>
      )}

      <PluginConfigDialog plugin={configPlugin} onClose={() => setConfigPlugin(null)} />
    </div>
  )
}

function PluginCard({ mod, isAdmin, onConfigure }: { mod: Module; isAdmin: boolean; onConfigure: () => void }) {
  const enable = useEnablePlugin()
  const disable = useDisablePlugin()
  const uninstall = useUninstallPlugin()
  const [uninstallOpen, setUninstallOpen] = useState(false)
  const isBuiltIn = mod.status === 'built_in'
  const isEnabled = mod.status === 'built_in' || mod.status === 'enabled'
  const hasConfig = mod.configSchema && Object.keys(mod.configSchema).length > 0

  const toggle = () => {
    if (isBuiltIn) return
    if (isEnabled) {
      disable.mutate(mod.slug)
    } else {
      enable.mutate(mod.slug)
    }
  }

  return (
    <>
    <div className="flex items-center justify-between p-4 bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-xl">
      <div className="min-w-0">
        <div className="flex items-center gap-2">
          <div className="text-sm text-white font-medium">{mod.name}</div>
          <span className={`text-[9px] px-1.5 py-0.5 rounded capitalize ${
            isBuiltIn
              ? 'bg-[rgba(139,92,246,0.08)] text-rail-purple'
              : isEnabled
                ? 'bg-green-500/10 text-green-400'
                : 'bg-[rgba(255,255,255,0.08)] text-[#A0A0B0]'
          }`}>
            {mod.status.replace('_', ' ')}
          </span>
        </div>
        <div className="text-[10px] text-[#6b6b7b] mt-0.5 truncate">{mod.description}</div>
        <div className="flex flex-wrap gap-1 mt-2">
          {mod.serviceSubtypes.map((s) => (
            <span key={s.subtype} className="text-[9px] px-1.5 py-0.5 bg-[rgba(139,92,246,0.08)] text-rail-purple rounded capitalize">
              {s.subtype}
            </span>
          ))}
          {mod.builders.map((b) => (
            <span key={b.slug} className="text-[9px] px-1.5 py-0.5 bg-[rgba(6,182,212,0.08)] text-cyan-400 rounded">
              {b.slug}
            </span>
          ))}
        </div>
      </div>

      <div className="flex items-center gap-2 shrink-0 ml-4">
        {hasConfig && (
          <Button
            variant="ghost"
            size="sm"
            onClick={onConfigure}
            className="text-[11px] text-[#A0A0B0] hover:text-white h-7"
          >
            <Cog size={13} className="mr-1" />
            Configure
          </Button>
        )}
        {isAdmin && !isBuiltIn && (
          <button
            type="button"
            onClick={toggle}
            disabled={enable.isPending || disable.isPending}
            className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
              isEnabled ? 'bg-rail-purple' : 'bg-[rgba(255,255,255,0.1)]'
            }`}
          >
            <span
              className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                isEnabled ? 'translate-x-6' : 'translate-x-1'
              }`}
            />
          </button>
        )}
        {isAdmin && !isBuiltIn && (
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setUninstallOpen(true)}
            disabled={uninstall.isPending}
            className="text-[11px] text-[#6b6b7b] hover:text-red-400 h-7"
            aria-label={`Uninstall ${mod.name}`}
          >
            <Trash2 size={13} />
          </Button>
        )}
      </div>
    </div>
    <ConfirmDialog
      open={uninstallOpen}
      onOpenChange={setUninstallOpen}
      title={`Uninstall ${mod.name}?`}
      description="The plugin is removed from RailDock. Any datastores or apps it provisions stay on the host, but RailDock will no longer manage or back them up."
      confirmLabel="Uninstall plugin"
      destructive
      pending={uninstall.isPending}
      onConfirm={async () => {
        try {
          await uninstall.mutateAsync(mod.slug)
          setUninstallOpen(false)
        } catch {
          /* surfaced by the mutation hook */
        }
      }}
    />
    </>
  )
}

function InstallPluginDialog({ onClose }: { onClose: () => void }) {
  const install = useInstallPlugin()
  const [sourceType, setSourceType] = useState('remote')
  const [sourceUrl, setSourceUrl] = useState('')
  const [sourceRef, setSourceRef] = useState('')

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!sourceUrl.trim()) return
    install.mutate(
      { sourceUrl: sourceUrl.trim(), sourceType, sourceRef: sourceRef.trim() || undefined },
      { onSuccess: () => onClose() }
    )
  }

  return (
    <form onSubmit={handleSubmit}>
      <DialogHeader>
        <DialogTitle className="text-sm">Install Plugin</DialogTitle>
        <DialogDescription className="text-[11px] text-[#6b6b7b]">
          Install a plugin from a remote manifest URL (YAML or JSON).
        </DialogDescription>
      </DialogHeader>
      <div className="space-y-3 py-4">
        <div>
          <Label htmlFor="source-type" className="text-[11px] text-[#A0A0B0] mb-1 block">Source Type</Label>
          <Select value={sourceType} onValueChange={setSourceType}>
            <SelectTrigger id="source-type" className="bg-[rgba(255,255,255,0.04)] border-[rgba(255,255,255,0.08)] text-sm h-9 text-white">
              <SelectValue />
            </SelectTrigger>
            <SelectContent className="bg-[#1A1A1F] border-[rgba(255,255,255,0.1)]">
              <SelectItem value="remote" className="text-sm text-white">Remote manifest</SelectItem>
              <SelectItem value="github" className="text-sm text-white">GitHub repository</SelectItem>
              <SelectItem value="local" className="text-sm text-white">Local file</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div>
          <Label htmlFor="source-url" className="text-[11px] text-[#A0A0B0] mb-1 block">Manifest URL</Label>
          <Input
            id="source-url"
            value={sourceUrl}
            onChange={(e) => setSourceUrl(e.target.value)}
            placeholder="https://example.com/raildock-plugin.yml"
            className="bg-[rgba(255,255,255,0.04)] border-[rgba(255,255,255,0.08)] text-sm h-9 text-white placeholder:text-[#6b6b7b]"
          />
        </div>
        <div>
          <Label htmlFor="source-ref" className="text-[11px] text-[#A0A0B0] mb-1 block">Ref (branch/tag, optional)</Label>
          <Input
            id="source-ref"
            value={sourceRef}
            onChange={(e) => setSourceRef(e.target.value)}
            placeholder="main"
            className="bg-[rgba(255,255,255,0.04)] border-[rgba(255,255,255,0.08)] text-sm h-9 text-white placeholder:text-[#6b6b7b]"
          />
        </div>
      </div>
      <DialogFooter>
        <Button
          type="submit"
          disabled={install.isPending || !sourceUrl.trim()}
          className="bg-rail-purple hover:bg-rail-purple/90 text-white text-xs"
        >
          {install.isPending ? 'Installing...' : 'Install'}
        </Button>
      </DialogFooter>
    </form>
  )
}

function PluginConfigDialog({
  plugin,
  onClose,
}: {
  plugin: Module | null
  onClose: () => void
}) {
  const { data: settingsData, isLoading } = usePluginSettings(plugin?.slug)
  const updateSettings = useUpdatePluginSettings()

  return (
    <Dialog open={!!plugin} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="bg-[#161618] border-[rgba(255,255,255,0.06)] text-[#F0F1F3]">
        <DialogHeader>
          <DialogTitle className="text-sm">{plugin ? `${plugin.name} Settings` : 'Plugin Settings'}</DialogTitle>
          <DialogDescription className="text-[11px] text-[#6b6b7b]">
            Configure this plugin before enabling it.
          </DialogDescription>
        </DialogHeader>
        {plugin && (
          <div className="py-2">
            {isLoading ? (
              <div className="text-[11px] text-[#6b6b7b]">Loading settings...</div>
            ) : (
              <ConfigSchemaForm
                key={plugin.slug}
                schema={plugin.configSchema || {}}
                initialValues={settingsData?.settings}
                onSubmit={(values) => updateSettings.mutate({ slug: plugin.slug, settings: values }, { onSuccess: onClose })}
                isSubmitting={updateSettings.isPending}
              />
            )}
          </div>
        )}
      </DialogContent>
    </Dialog>
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
        <div className="text-[10px] text-[#6b6b7b] uppercase tracking-wider font-medium mb-4 flex items-center gap-2">
          <ArrowUpCircle size={12} className="text-rail-purple" /> Version & Updates
        </div>

        {isLoading ? (
          <div className="text-[11px] text-[#6b6b7b]">Loading...</div>
        ) : isError ? (
          <div className="text-[11px] text-red-400">Failed to load update info</div>
        ) : updateInfo ? (
          <div className="space-y-4">
            {/* Current version + last checked */}
            <div className="flex items-center justify-between p-3 bg-[rgba(255,255,255,0.02)] rounded-lg">
              <div>
                <div className="text-[11px] text-[#6b6b7b]">Current Version</div>
                <div className="text-sm text-white font-mono mt-0.5">{updateInfo.currentVersion}</div>
              </div>
              <div className="text-[10px] text-[#6b6b7b] text-right">
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
                  <div className="text-[11px] text-[#6b6b7b] mt-0.5">
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
        <div className="text-[10px] text-[#6b6b7b] uppercase tracking-wider font-medium mb-4 flex items-center gap-2">
          <RefreshCw size={12} className="text-rail-purple" /> Auto-Update
        </div>
        <div className="flex items-center justify-between p-3 bg-[rgba(255,255,255,0.02)] rounded-lg gap-4">
          <div className="min-w-0">
            <div className="text-sm text-white">Automatic Updates</div>
            <div className="text-[11px] text-[#6b6b7b] mt-0.5">
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
  const [removeTarget, setRemoveTarget] = useState<{ id: string; name: string } | null>(null)
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
          <p className="text-[11px] text-[#6b6b7b] mt-0.5">SSH keys for cloning private repositories</p>
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
              <DialogDescription className="text-[11px] text-[#6b6b7b]">
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
        <div className="text-[11px] text-[#6b6b7b]">Loading...</div>
      ) : keys.length === 0 ? (
        <div className="bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-xl p-8 text-center">
          <Key size={24} className="text-[#6b6b7b] mx-auto mb-2" />
          <p className="text-sm text-[#A0A0B0]">No deploy keys yet</p>
          <p className="text-[11px] text-[#6b6b7b] mt-1">Create one to deploy from private Git repos via SSH.</p>
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
                  onClick={() => setRemoveTarget({ id: key.id, name: key.name })}
                  className="text-[11px] text-[#6b6b7b] hover:text-red-400 h-7"
                  aria-label={`Delete deploy key ${key.name}`}
                >
                  <Trash2 size={13} />
                </Button>
              </div>
              <div className="text-[10px] text-[#6b6b7b]">Fingerprint: {key.fingerprint}</div>
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

      <ConfirmDialog
        open={removeTarget !== null}
        onOpenChange={(open) => !open && setRemoveTarget(null)}
        title={`Delete deploy key${removeTarget ? ` "${removeTarget.name}"` : ''}?`}
        description="Any service still cloning a private repo with this key will fail on its next deploy until a new key is added."
        confirmLabel="Delete key"
        destructive
        pending={deleteKey.isPending}
        onConfirm={async () => {
          if (!removeTarget) return
          try {
            await deleteKey.mutateAsync(removeTarget.id)
            setRemoveTarget(null)
          } catch {
            /* surfaced by the mutation hook */
          }
        }}
      />
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
  const [removeTarget, setRemoveTarget] = useState<{ id: string; name: string } | null>(null)

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
          <p className="text-[11px] text-[#6b6b7b] mt-0.5">Manage teams and shared resources</p>
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
              <DialogDescription className="text-[11px] text-[#6b6b7b]">
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
        <div className="text-[11px] text-[#6b6b7b]">Loading...</div>
      ) : organizations.length === 0 ? (
        <div className="bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-xl p-8 text-center">
          <Building2 size={24} className="text-[#6b6b7b] mx-auto mb-2" />
          <p className="text-sm text-[#A0A0B0]">No organizations yet</p>
          <p className="text-[11px] text-[#6b6b7b] mt-1">Create one to share projects with your team.</p>
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
                  <div className="text-[10px] text-[#6b6b7b] flex items-center gap-2">
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
                  onClick={() => setRemoveTarget(org)}
                  className="text-[11px] text-[#6b6b7b] hover:text-red-400 h-7"
                  aria-label={`Delete organization ${org.name}`}
                >
                  <Trash2 size={13} />
                </Button>
              </div>
            </div>
          ))}
        </div>
      )}

      <ConfirmDialog
        open={removeTarget !== null}
        onOpenChange={(open) => !open && setRemoveTarget(null)}
        title="Delete organization?"
        description={
          <>
            <span className="font-medium text-white">{removeTarget?.name}</span>, its projects, services and
            servers will be removed from RailDock. Apps and datastores already running on your hosts are left
            untouched, but RailDock will no longer deploy to or back them up.
          </>
        }
        confirmLabel="Delete organization"
        destructive
        confirmWord={removeTarget?.name}
        confirmWordLabel={
          <>
            Type <span className="font-mono font-medium text-white">{removeTarget?.name}</span> to confirm
          </>
        }
        pending={deleteOrg.isPending}
        onConfirm={async () => {
          if (!removeTarget) return
          try {
            await deleteOrg.mutateAsync(removeTarget.id)
            if (currentOrganizationId === removeTarget.id) setCurrentOrganizationId(null)
            setRemoveTarget(null)
          } catch {
            /* surfaced by the mutation hook */
          }
        }}
      />
    </div>
  )
}
