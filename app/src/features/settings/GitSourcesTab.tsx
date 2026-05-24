import { useState, useEffect, useCallback, useMemo } from 'react'
import { useSearchParams } from 'react-router-dom'
import {
  FolderGit2,
  Github,
  Gitlab,
  ExternalLink,
  ChevronDown,
  ChevronRight,
  Copy,
  Check,
  Trash2,
  KeyRound,
  Building2,
  User,
  RefreshCw,
  Settings2,
  Wrench,
  CheckCircle2,
} from 'lucide-react'
import { toast } from 'sonner'
import {
  useGitSources,
  useConnectGitSource,
  useDisconnectGitSource,
  useGitSourceRepos,
  useGitHubAppConfig,
  useSystemSettings,
  useUpdateSystemSetting,
  useTestGitHubApp,
} from '@/hooks/useGitSources'
import { useAuthStore } from '@/stores/useAuthStore'
import { api } from '@/lib/api'
import type { GitSource, GitRepo } from '@/types'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'

const PROVIDER_INFO: Record<string, { name: string; icon: typeof Github; color: string }> = {
  github: { name: 'GitHub', icon: Github, color: '#8b5cf6' },
  gitlab: { name: 'GitLab', icon: Gitlab, color: '#fc6d26' },
  bitbucket: { name: 'Bitbucket', icon: FolderGit2, color: '#2684ff' },
  gitea: { name: 'Gitea', icon: FolderGit2, color: '#609926' },
}

const ALL_PROVIDERS = ['github', 'gitlab', 'bitbucket', 'gitea']

export default function GitSourcesTab() {
  const [searchParams, setSearchParams] = useSearchParams()
  const { data: gitSources = [], isLoading } = useGitSources()
  const { data: ghConfig } = useGitHubAppConfig()
  const connect = useConnectGitSource()
  const disconnect = useDisconnectGitSource()
  const user = useAuthStore((s) => s.user)
  const orgId = useAuthStore((s) => s.currentOrganizationId)

  // PAT token modal state
  const [patModalOpen, setPatModalOpen] = useState(false)
  const [patProvider, setPatProvider] = useState('')
  const [patToken, setPatToken] = useState('')

  // Expanded repo lists
  const [expandedSource, setExpandedSource] = useState<string | null>(null)

  // Handle GitHub App callback on mount
  useEffect(() => {
    const ghApp = searchParams.get('github_app')
    const gsId = searchParams.get('git_source_id')
    const message = searchParams.get('message')

    if (ghApp === 'success') {
      toast.success('GitHub App installed successfully', {
        description: gsId ? 'Your repositories are being synced.' : undefined,
      })
      // Clean URL
      const next = new URLSearchParams(searchParams)
      next.delete('github_app')
      next.delete('git_source_id')
      next.delete('message')
      setSearchParams(next, { replace: true })
    } else if (ghApp === 'error') {
      toast.error('GitHub App installation failed', {
        description: message || 'Please try again.',
      })
      const next = new URLSearchParams(searchParams)
      next.delete('github_app')
      next.delete('git_source_id')
      next.delete('message')
      setSearchParams(next, { replace: true })
    }
  }, [searchParams, setSearchParams])

  const connected = gitSources.filter((g) => g.connected)
  const disconnected = gitSources.filter((g) => !g.connected)

  const openPatModal = (provider: string) => {
    setPatProvider(provider)
    setPatToken('')
    setPatModalOpen(true)
  }

  const handlePatConnect = () => {
    if (!patToken.trim()) return
    connect.mutate({ provider: patProvider, token: patToken }, {
      onSuccess: () => setPatModalOpen(false),
    })
  }

  const handleGitHubAppInstall = () => {
    const appSlug = ghConfig?.githubApp?.appSlug
    if (!appSlug) {
      toast.error('GitHub App is not configured')
      return
    }
    const state = {
      user_id: user?.id,
      organization_id: orgId,
      account_type: orgId ? 'organization' : 'personal',
    }
    const url = api.gitSources.installUrl(appSlug, state)
    window.location.href = url
  }

  const hasGitHubConnected = connected.some((g) => g.provider === 'github')

  return (
    <div className="max-w-3xl space-y-5">
      {/* Connected Sources */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-sm font-medium text-white">Connected Git Sources</h2>
          <p className="text-[11px] text-[#4A4A55] mt-0.5">
            Repositories synced from your connected accounts
          </p>
        </div>
      </div>

      {isLoading ? (
        <div className="text-[11px] text-[#4A4A55]">Loading...</div>
      ) : connected.length === 0 ? (
        <div className="bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-xl p-8 text-center">
          <FolderGit2 size={24} className="text-[#4A4A55] mx-auto mb-2" />
          <p className="text-sm text-[#A0A0B0]">No git sources connected</p>
          <p className="text-[11px] text-[#4A4A55] mt-1">
            Connect GitHub, GitLab, or Bitbucket to deploy from repositories.
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {connected.map((gs) => (
            <GitSourceCard
              key={gs.id}
              source={gs}
              expanded={expandedSource === gs.id}
              onToggle={() => setExpandedSource(expandedSource === gs.id ? null : gs.id)}
              onDisconnect={() => disconnect.mutate(gs.id)}
              isDisconnecting={disconnect.isPending}
            />
          ))}
        </div>
      )}

      {/* Connect New Source */}
      <div className="pt-4 border-t border-[rgba(255,255,255,0.05)]">
        <h2 className="text-sm font-medium text-white mb-3">Connect New Source</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          {ALL_PROVIDERS.map((provider) => {
            const info = PROVIDER_INFO[provider]
            const Icon = info.icon
            const isConnected = connected.some((g) => g.provider === provider)
            const isGitHub = provider === 'github'
            const ghAppEnabled = ghConfig?.githubApp?.enabled && ghConfig?.githubApp?.appSlug

            return (
              <div
                key={provider}
                className="bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-xl p-4 flex items-center justify-between"
              >
                <div className="flex items-center gap-3">
                  <div
                    className="w-9 h-9 rounded-lg flex items-center justify-center"
                    style={{ backgroundColor: `${info.color}15` }}
                  >
                    <Icon size={18} style={{ color: info.color }} />
                  </div>
                  <div>
                    <div className="text-sm text-white font-medium">{info.name}</div>
                    <div className="text-[10px] text-[#4A4A55]">
                      {isConnected ? 'Connected' : isGitHub && ghAppEnabled ? 'App or PAT' : 'Personal Access Token'}
                    </div>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  {isGitHub && ghAppEnabled && !hasGitHubConnected && (
                    <Button
                      size="sm"
                      onClick={handleGitHubAppInstall}
                      className="bg-[#8b5cf6] hover:bg-[#8b5cf6]/90 text-white text-[11px] h-8 px-3"
                    >
                      <ExternalLink size={12} className="mr-1" />
                      Install App
                    </Button>
                  )}
                  {!isConnected && (
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => openPatModal(provider)}
                      className="text-[11px] text-[#A0A0B0] hover:text-white h-8"
                    >
                      <KeyRound size={12} className="mr-1" />
                      Token
                    </Button>
                  )}
                  {isConnected && (
                    <span className="text-[10px] px-2 py-0.5 rounded-full bg-[#22c55e]/10 text-[#22c55e]">
                      Connected
                    </span>
                  )}
                </div>
              </div>
            )
          })}
        </div>
      </div>

      {/* Admin Configuration */}
      {user?.admin && (
        <AdminConfigPanel />
      )}

      {/* PAT Token Modal */}
      <Dialog open={patModalOpen} onOpenChange={setPatModalOpen}>
        <DialogContent className="bg-[#161618] border-[rgba(255,255,255,0.06)] text-[#F0F1F3]">
          <DialogHeader>
            <DialogTitle className="text-sm">
              Connect {PROVIDER_INFO[patProvider]?.name || patProvider}
            </DialogTitle>
            <DialogDescription className="text-[11px] text-[#4A4A55]">
              Enter a personal access token with repository read access.
            </DialogDescription>
          </DialogHeader>
          <div className="py-2">
            <label className="text-[11px] text-[#A0A0B0] mb-1 block">Access Token</label>
            <input
              type="password"
              value={patToken}
              onChange={(e) => setPatToken(e.target.value)}
              placeholder={patProvider === 'github' ? 'ghp_xxxxxxxxxxxx' : 'glpat-xxxxxxxxxxxx'}
              className="w-full px-3 py-2.5 bg-[rgba(255,255,255,0.04)] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-[#8b5cf6]/40"
              onKeyDown={(e) => e.key === 'Enter' && handlePatConnect()}
            />
            <p className="text-[10px] text-[#4A4A55] mt-1.5">
              The token is encrypted at rest and only used to fetch repository metadata.
            </p>
          </div>
          <DialogFooter>
            <Button
              onClick={handlePatConnect}
              disabled={connect.isPending || !patToken.trim()}
              className="bg-[#8b5cf6] hover:bg-[#8b5cf6]/90 text-white text-xs"
            >
              {connect.isPending ? 'Connecting...' : 'Connect'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

// ── Admin Config Panel ─────────────────────────

function AdminConfigPanel() {
  const [expanded, setExpanded] = useState(false)
  const { data: settings = [] } = useSystemSettings()
  const updateSettings = useUpdateSystemSetting()
  const testConnection = useTestGitHubApp()

  const settingMap = useMemo(() => {
    const map: Record<string, string> = {}
    settings.forEach((s) => { if (s.value) map[s.key] = s.value })
    return map
  }, [settings])

  const [form, setForm] = useState({
    github_app_slug: '',
    github_app_id: '',
    github_client_id: '',
    github_webhook_secret: '',
  })

  // Sync form when settings load
  useEffect(() => {
    setForm({
      github_app_slug: settingMap['github_app_slug'] || '',
      github_app_id: settingMap['github_app_id'] || '',
      github_client_id: settingMap['github_client_id'] || '',
      github_webhook_secret: settingMap['github_webhook_secret'] || '',
    })
  }, [settingMap])

  const handleSave = () => {
    updateSettings.mutate({
      github_app_slug: form.github_app_slug || undefined,
      github_app_id: form.github_app_id || undefined,
      github_client_id: form.github_client_id || undefined,
      github_webhook_secret: form.github_webhook_secret || undefined,
    })
  }

  const handleTest = () => {
    testConnection.mutate()
  }

  return (
    <div className="pt-4 border-t border-[rgba(255,255,255,0.05)]">
      <button
        onClick={() => setExpanded(!expanded)}
        className="flex items-center gap-2 text-sm text-white/60 hover:text-white transition-colors w-full"
      >
        <Wrench size={14} className="text-[#4A4A55]" />
        <span className="font-medium">Admin Configuration</span>
        <span className="text-[10px] px-1.5 py-0.5 bg-[rgba(255,255,255,0.06)] text-[#4A4A55] rounded ml-1">Admin only</span>
        {expanded ? <ChevronDown size={14} className="ml-auto" /> : <ChevronRight size={14} className="ml-auto" />}
      </button>

      {expanded && (
        <div className="mt-3 bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-xl p-4 space-y-4">
          <p className="text-[11px] text-[#4A4A55]">
            Configure your GitHub App credentials. The private key stays in Rails credentials for security.
          </p>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <label className="text-[11px] text-[#A0A0B0] mb-1 block">GitHub App Slug</label>
              <input
                type="text"
                value={form.github_app_slug}
                onChange={(e) => setForm({ ...form, github_app_slug: e.target.value })}
                placeholder="my-raildock-app"
                className="w-full px-3 py-2 bg-[rgba(255,255,255,0.04)] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-[#8b5cf6]/40"
              />
              <p className="text-[10px] text-[#4A4A55] mt-1">The app name in the GitHub URL</p>
            </div>
            <div>
              <label className="text-[11px] text-[#A0A0B0] mb-1 block">GitHub App ID</label>
              <input
                type="text"
                value={form.github_app_id}
                onChange={(e) => setForm({ ...form, github_app_id: e.target.value })}
                placeholder="123456"
                className="w-full px-3 py-2 bg-[rgba(255,255,255,0.04)] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-[#8b5cf6]/40"
              />
            </div>
            <div>
              <label className="text-[11px] text-[#A0A0B0] mb-1 block">Client ID</label>
              <input
                type="text"
                value={form.github_client_id}
                onChange={(e) => setForm({ ...form, github_client_id: e.target.value })}
                placeholder="Iv1.xxxxxxxxxxxxxxxx"
                className="w-full px-3 py-2 bg-[rgba(255,255,255,0.04)] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-[#8b5cf6]/40"
              />
            </div>
            <div>
              <label className="text-[11px] text-[#A0A0B0] mb-1 block">Webhook Secret</label>
              <input
                type="password"
                value={form.github_webhook_secret}
                onChange={(e) => setForm({ ...form, github_webhook_secret: e.target.value })}
                placeholder="••••••••••••••••"
                className="w-full px-3 py-2 bg-[rgba(255,255,255,0.04)] border border-[rgba(255,255,255,0.08)] rounded-lg text-sm text-white outline-none focus:border-[#8b5cf6]/40"
              />
            </div>
          </div>

          <div className="flex items-center gap-3 pt-2">
            <Button
              onClick={handleSave}
              disabled={updateSettings.isPending}
              className="bg-[#8b5cf6] hover:bg-[#8b5cf6]/90 text-white text-xs h-8"
            >
              {updateSettings.isPending ? 'Saving...' : 'Save Settings'}
            </Button>
            <Button
              variant="ghost"
              onClick={handleTest}
              disabled={testConnection.isPending || !form.github_app_slug}
              className="text-[11px] text-[#A0A0B0] hover:text-white h-8"
            >
              {testConnection.isPending ? (
                <RefreshCw size={12} className="mr-1 animate-spin" />
              ) : testConnection.isSuccess && testConnection.data?.valid ? (
                <CheckCircle2 size={12} className="mr-1 text-[#22c55e]" />
              ) : (
                <ExternalLink size={12} className="mr-1" />
              )}
              Test Connection
            </Button>
            {testConnection.isSuccess && testConnection.data?.valid && (
              <span className="text-[11px] text-[#22c55e]">
                {testConnection.data.name}
              </span>
            )}
          </div>
        </div>
      )}
    </div>
  )
}

// ── Sub-components ─────────────────────────────

function GitSourceCard({
  source,
  expanded,
  onToggle,
  onDisconnect,
  isDisconnecting,
}: {
  source: GitSource
  expanded: boolean
  onToggle: () => void
  onDisconnect: () => void
  isDisconnecting: boolean
}) {
  const info = PROVIDER_INFO[source.provider] || PROVIDER_INFO.github
  const Icon = info.icon
  const { data: repoData } = useGitSourceRepos(expanded ? source.id : undefined)
  const repos = repoData?.repos || source.repos || []
  const syncing = repoData?.syncing ?? false

  return (
    <div className="bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-xl overflow-hidden">
      {/* Header */}
      <div className="p-4 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div
            className="w-9 h-9 rounded-lg flex items-center justify-center"
            style={{ backgroundColor: `${info.color}15` }}
          >
            <Icon size={18} style={{ color: info.color }} />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <span className="text-sm text-white font-medium">{info.name}</span>
              {source.authMethod && (
                <span className="text-[9px] px-1.5 py-0.5 rounded bg-[rgba(255,255,255,0.06)] text-[#4A4A55]">
                  {source.authMethod === 'oauth_app' ? 'App' : 'Token'}
                </span>
              )}
            </div>
            <div className="flex items-center gap-2 mt-0.5">
              <span className="text-[11px] text-[#4A4A55]">{source.username || 'Unknown user'}</span>
              {source.accountType && (
                <span className="text-[9px] flex items-center gap-0.5 text-[#4A4A55]">
                  {source.accountType === 'organization' ? (
                    <><Building2 size={8} /> Org</>
                  ) : (
                    <><User size={8} /> Personal</>
                  )}
                </span>
              )}
            </div>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={onToggle}
            className="text-[11px] flex items-center gap-1 text-[#4A4A55] hover:text-[#A0A0B0] transition-colors"
          >
            {repos.length} repos
            {expanded ? <ChevronDown size={12} /> : <ChevronRight size={12} />}
          </button>
          <Button
            variant="ghost"
            size="sm"
            onClick={onDisconnect}
            disabled={isDisconnecting}
            className="text-[11px] text-[#4A4A55] hover:text-red-400 h-8"
          >
            <Trash2 size={13} />
          </Button>
        </div>
      </div>

      {/* Expanded Repo List */}
      {expanded && (
        <div className="border-t border-[rgba(255,255,255,0.05)] px-4 py-3">
          {syncing && repos.length === 0 ? (
            <div className="flex items-center gap-2 text-[11px] text-[#4A4A55]">
              <RefreshCw size={12} className="animate-spin" />
              Syncing repositories...
            </div>
          ) : repos.length === 0 ? (
            <div className="text-[11px] text-[#4A4A55]">No repositories found</div>
          ) : (
            <div className="space-y-1 max-h-60 overflow-y-auto">
              {repos.map((repo: GitRepo) => (
                <div
                  key={repo.id}
                  className="flex items-center justify-between py-1.5 px-2 rounded hover:bg-[rgba(255,255,255,0.02)]"
                >
                  <div className="flex items-center gap-2 min-w-0">
                    <FolderGit2 size={12} className="text-[#4A4A55] shrink-0" />
                    <span className="text-[12px] text-[#A0A0B0] truncate">{repo.fullName}</span>
                  </div>
                  <div className="flex items-center gap-2 shrink-0">
                    <span className="text-[10px] text-[#4A4A55]">{repo.defaultBranch}</span>
                    {repo.private && (
                      <span className="text-[9px] px-1.5 py-0.5 rounded bg-[rgba(255,255,255,0.06)] text-[#4A4A55]">
                        Private
                      </span>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  )
}
