import { useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Settings, Puzzle, Building2, Plus, Trash2, Users, Key } from 'lucide-react'
import { useCopy } from '@/hooks/useCopy'
import { useModules } from '@/hooks/useModules'
import { useOrganizations, useCreateOrganization, useDeleteOrganization } from '@/hooks/useOrganizations'
import { useDeployKeys, useCreateDeployKey, useDeleteDeployKey } from '@/hooks/useDeployKeys'
import { useAuthStore } from '@/stores/useAuthStore'
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

const TABS = [
  { key: 'integrations', label: 'Integrations', icon: Puzzle },
  { key: 'organizations', label: 'Organizations', icon: Building2 },
  { key: 'deploy-keys', label: 'Deploy Keys', icon: Key },
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

        {activeTab === 'organizations' && <OrganizationsTab />}
        {activeTab === 'deploy-keys' && <DeployKeysTab />}
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
