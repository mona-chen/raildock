import { useState } from 'react'
import {
  AlertCircle,
  Building2,
  Check,
  Crown,
  Image as ImageIcon,
  Loader2,
  Pencil,
  Plus,
  Shield,
  Trash2,
  Users,
} from 'lucide-react'
import { useAuthStore } from '@/stores/useAuthStore'
import {
  useCreateOrganization,
  useDeleteOrganization,
  useOrganizations,
  useUpdateOrganization,
} from '@/hooks/useOrganizations'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar'
import { Badge } from '@/components/ui/badge'
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
import { IconButton } from '@/components/ui/icon-button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import ConfirmDialog from '@/features/shared/ConfirmDialog'
import { cn } from '@/lib/utils'
import type { Organization } from '@/types'

function initialsFor(name: string): string {
  return name
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0])
    .join('')
    .toUpperCase() || '?'
}

function canManage(organization: Organization): boolean {
  return organization.role === 'owner' || organization.role === 'admin'
}

function roleBadge(role: Organization['role']) {
  if (role === 'owner') {
    return {
      label: 'Owner',
      icon: Crown,
      className: 'border-amber-400/25 bg-amber-400/8 text-amber-300',
    }
  }
  if (role === 'admin') {
    return {
      label: 'Admin',
      icon: Shield,
      className: 'border-rail-purple/25 bg-rail-purple/10 text-rail-purple',
    }
  }
  if (role === 'member') {
    return {
      label: 'Member',
      icon: Users,
      className: 'border-white/8 bg-white/[0.03] text-white/45',
    }
  }
  return null
}

function OrganizationAvatar({
  organization,
  className,
}: {
  organization: Pick<Organization, 'name' | 'avatarUrl'>
  className?: string
}) {
  return (
    <Avatar className={cn('size-10 ring-1 ring-white/8', className)}>
      {organization.avatarUrl && <AvatarImage src={organization.avatarUrl} alt="" />}
      <AvatarFallback className="bg-[radial-gradient(circle_at_30%_20%,rgba(139,92,246,0.3),rgba(139,92,246,0.06))] text-[12px] font-semibold tracking-wide text-rail-purple">
        {initialsFor(organization.name)}
      </AvatarFallback>
    </Avatar>
  )
}

function OrganizationFields({
  name,
  slug,
  avatarUrl,
  onName,
  onSlug,
  onAvatarUrl,
  nameId,
  slugId,
  avatarId,
}: {
  name: string
  slug: string
  avatarUrl: string
  onName: (value: string) => void
  onSlug: (value: string) => void
  onAvatarUrl: (value: string) => void
  nameId: string
  slugId: string
  avatarId: string
}) {
  return (
    <div className="space-y-4">
      <div className="space-y-1.5">
        <Label htmlFor={nameId} className="text-[11px] font-medium text-white/60">
          Organization name
        </Label>
        <Input
          id={nameId}
          value={name}
          onChange={(event) => onName(event.target.value)}
          placeholder="Acme Corp"
          className="h-10 border-white/8 bg-white/[0.03] text-[13px] text-white/85 placeholder:text-white/25"
        />
      </div>

      <div className="space-y-1.5">
        <Label htmlFor={slugId} className="text-[11px] font-medium text-white/60">
          Slug
        </Label>
        <div className="relative">
          <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 font-mono text-[12px] text-white/25">
            @
          </span>
          <Input
            id={slugId}
            value={slug}
            onChange={(event) => onSlug(event.target.value)}
            placeholder="acme-corp"
            className="h-10 border-white/8 bg-white/[0.03] pl-7 font-mono text-[12px] text-white/80 placeholder:text-white/25"
          />
        </div>
        <p className="text-[10px] leading-relaxed text-white/30">
          Used in invite links and workspace references. Changing it does not move existing projects.
        </p>
      </div>

      <div className="space-y-1.5">
        <Label htmlFor={avatarId} className="flex items-center gap-1.5 text-[11px] font-medium text-white/60">
          <ImageIcon size={11} className="text-white/30" />
          Avatar URL
          <span className="font-normal text-white/25">(optional)</span>
        </Label>
        <Input
          id={avatarId}
          type="url"
          value={avatarUrl}
          onChange={(event) => onAvatarUrl(event.target.value)}
          placeholder="https://example.com/logo.png"
          className="h-10 border-white/8 bg-white/[0.03] text-[12px] text-white/80 placeholder:text-white/25"
        />
      </div>
    </div>
  )
}

export default function OrganizationsTab() {
  const { data: organizations = [], isLoading } = useOrganizations()
  const createOrg = useCreateOrganization()
  const updateOrg = useUpdateOrganization()
  const deleteOrg = useDeleteOrganization()
  const { currentOrganizationId, setCurrentOrganizationId } = useAuthStore()

  const [createOpen, setCreateOpen] = useState(false)
  const [name, setName] = useState('')
  const [slug, setSlug] = useState('')
  const [avatarUrl, setAvatarUrl] = useState('')

  const [editTarget, setEditTarget] = useState<Organization | null>(null)
  const [editName, setEditName] = useState('')
  const [editSlug, setEditSlug] = useState('')
  const [editAvatarUrl, setEditAvatarUrl] = useState('')

  const [removeTarget, setRemoveTarget] = useState<{ id: string; name: string } | null>(null)

  const resetCreateForm = () => {
    setName('')
    setSlug('')
    setAvatarUrl('')
    createOrg.reset()
  }

  const clearCreateError = () => {
    if (createOrg.isError) createOrg.reset()
  }

  const clearEditError = () => {
    if (updateOrg.isError) updateOrg.reset()
  }

  const handleCreate = () => {
    if (!name.trim() || !slug.trim()) return
    createOrg.mutate(
      { name: name.trim(), slug: slug.trim(), avatarUrl: avatarUrl.trim() || undefined },
      {
        onSuccess: () => {
          resetCreateForm()
          setCreateOpen(false)
        },
      }
    )
  }

  const openEdit = (organization: Organization) => {
    setEditTarget(organization)
    setEditName(organization.name)
    setEditSlug(organization.slug)
    setEditAvatarUrl(organization.avatarUrl ?? '')
    updateOrg.reset()
  }

  const closeEdit = () => {
    setEditTarget(null)
    updateOrg.reset()
  }

  const editDirty =
    editTarget !== null &&
    (editName.trim() !== editTarget.name ||
      editSlug.trim() !== editTarget.slug ||
      editAvatarUrl.trim() !== (editTarget.avatarUrl ?? ''))

  const canSaveEdit =
    editTarget !== null &&
    !updateOrg.isPending &&
    editDirty &&
    editName.trim().length > 0 &&
    editSlug.trim().length > 0

  const handleEdit = () => {
    if (!editTarget || !canSaveEdit) return
    updateOrg.mutate(
      {
        id: editTarget.id,
        data: {
          name: editName.trim(),
          slug: editSlug.trim(),
          avatarUrl: editAvatarUrl.trim(),
        },
      },
      { onSuccess: () => setEditTarget(null) }
    )
  }

  return (
    <div className="max-w-3xl space-y-5">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h2 className="text-sm font-medium text-white">Organizations</h2>
          <p className="mt-1 text-[11px] leading-relaxed text-[#9292a3]">
            Every project, server and git source belongs to one organization. Switch workspaces here or update the
            profile your teammates see.
          </p>
        </div>
        <Dialog
          open={createOpen}
          onOpenChange={(open) => {
            setCreateOpen(open)
            if (!open) resetCreateForm()
          }}
        >
          <DialogTrigger asChild>
            <Button size="sm" className="h-8 shrink-0 bg-rail-purple text-[11px] text-white hover:bg-rail-purple/90">
              <Plus />
              New organization
            </Button>
          </DialogTrigger>
          <DialogContent className="border-white/8 bg-[#161618] text-[#F0F1F3] sm:max-w-md">
            <DialogHeader>
              <DialogTitle className="text-sm">Create organization</DialogTitle>
              <DialogDescription className="text-[11px] leading-relaxed text-[#9292a3]">
                Organizations share projects, servers and git sources with your team.
              </DialogDescription>
            </DialogHeader>

            <OrganizationFields
              name={name}
              slug={slug}
              avatarUrl={avatarUrl}
              onName={(value) => { clearCreateError(); setName(value) }}
              onSlug={(value) => { clearCreateError(); setSlug(value) }}
              onAvatarUrl={(value) => { clearCreateError(); setAvatarUrl(value) }}
              nameId="new-organization-name"
              slugId="new-organization-slug"
              avatarId="new-organization-avatar"
            />

            {createOrg.error && (
              <Alert variant="destructive" className="border-red-500/20 bg-red-500/[0.06] text-red-300">
                <AlertCircle />
                <AlertDescription className="text-[11px] text-red-300/90">{createOrg.error.message}</AlertDescription>
              </Alert>
            )}

            <DialogFooter>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setCreateOpen(false)}
                className="h-8 text-[11px] text-white/50"
              >
                Cancel
              </Button>
              <Button
                size="sm"
                onClick={handleCreate}
                disabled={createOrg.isPending || !name.trim() || !slug.trim()}
                className={cn(
                  'h-8 text-[11px]',
                  !createOrg.isPending && name.trim() && slug.trim()
                    ? 'bg-rail-purple text-white hover:bg-rail-purple/90'
                    : 'bg-white/8 text-white/35'
                )}
              >
                {createOrg.isPending ? <Loader2 className="animate-spin" /> : <Plus />}
                {createOrg.isPending ? 'Creating…' : 'Create organization'}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>

      {isLoading ? (
        <div className="space-y-2">
          {[0, 1].map((row) => (
            <div key={row} className="h-[72px] animate-pulse rounded-2xl border border-white/6 bg-white/[0.02]" />
          ))}
        </div>
      ) : organizations.length === 0 ? (
        <div className="rounded-2xl border border-dashed border-white/10 bg-white/[0.015] px-6 py-10 text-center">
          <Building2 size={22} className="mx-auto text-white/25" />
          <p className="mt-3 text-[12px] text-white/60">No organizations yet</p>
          <p className="mt-1 text-[11px] text-white/30">Create one to share projects with your team.</p>
        </div>
      ) : (
        <div className="space-y-2">
          {organizations.map((organization) => {
            const active = currentOrganizationId === organization.id
            const role = roleBadge(organization.role)
            const RoleIcon = role?.icon

            return (
              <div
                key={organization.id}
                className={cn(
                  'group flex flex-col gap-3 rounded-2xl border p-4 transition-colors sm:flex-row sm:items-center sm:justify-between',
                  active
                    ? 'border-rail-purple/25 bg-gradient-to-r from-rail-purple/[0.08] via-rail-purple/[0.03] to-transparent'
                    : 'border-white/6 bg-white/[0.02] hover:border-white/10 hover:bg-white/[0.03]'
                )}
              >
                <div className="flex min-w-0 items-center gap-3.5">
                  <OrganizationAvatar organization={organization} />
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-1.5">
                      <p className="truncate text-[13px] font-medium text-white">{organization.name}</p>
                      {active && (
                        <Badge
                          variant="outline"
                          className="border-rail-purple/25 bg-rail-purple/10 text-[9px] font-medium text-rail-purple"
                        >
                          Active
                        </Badge>
                      )}
                      {role && (
                        <Badge variant="outline" className={cn('gap-1 text-[9px] font-medium', role.className)}>
                          {RoleIcon && <RoleIcon size={9} />}
                          {role.label}
                        </Badge>
                      )}
                    </div>
                    <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-[10px] text-white/35">
                      <span className="font-mono">@{organization.slug}</span>
                      <span className="flex items-center gap-1">
                        <Users size={10} />
                        {organization.memberCount ?? 1} {(organization.memberCount ?? 1) === 1 ? 'member' : 'members'}
                      </span>
                    </div>
                  </div>
                </div>

                <div className="flex items-center gap-1.5 self-end sm:self-auto">
                  {canManage(organization) && (
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => openEdit(organization)}
                      className="h-8 px-2 text-[11px] text-white/45 hover:bg-white/5 hover:text-white/80"
                    >
                      <Pencil size={12} />
                      Edit
                    </Button>
                  )}
                  {!active && (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => setCurrentOrganizationId(organization.id)}
                      className="h-8 border-white/8 bg-white/[0.02] px-3 text-[11px] text-white/70 hover:bg-white/5 hover:text-white"
                    >
                      Switch
                    </Button>
                  )}
                  {organization.role === 'owner' && (
                    <IconButton
                      title={`Delete organization ${organization.name}`}
                      onClick={() => setRemoveTarget(organization)}
                      className="hover:bg-red-500/10 hover:text-red-400"
                    >
                      <Trash2 />
                    </IconButton>
                  )}
                </div>
              </div>
            )
          })}
        </div>
      )}

      <Dialog open={editTarget !== null} onOpenChange={(open) => !open && closeEdit()}>
        <DialogContent className="border-white/8 bg-[#161618] text-[#F0F1F3] sm:max-w-md">
          <DialogHeader>
            <DialogTitle className="text-sm">Edit organization</DialogTitle>
            <DialogDescription className="text-[11px] leading-relaxed text-[#9292a3]">
              Update the name, slug and avatar used across this workspace.
            </DialogDescription>
          </DialogHeader>

          {editTarget && (
            <>
              <div className="flex items-center gap-3 rounded-xl border border-white/6 bg-white/[0.02] p-3">
                <OrganizationAvatar
                  organization={{ name: editName || editTarget.name, avatarUrl: editAvatarUrl || undefined }}
                  className="size-11"
                />
                <div className="min-w-0">
                  <p className="truncate text-[12px] font-medium text-white">
                    {editName.trim() || 'Organization name'}
                  </p>
                  <p className="truncate font-mono text-[10px] text-white/35">
                    @{editSlug.trim() || 'slug'}
                  </p>
                </div>
                <Check size={14} className="ml-auto text-emerald-400/70" />
              </div>

              <OrganizationFields
                name={editName}
                slug={editSlug}
                avatarUrl={editAvatarUrl}
                onName={(value) => { clearEditError(); setEditName(value) }}
                onSlug={(value) => { clearEditError(); setEditSlug(value) }}
                onAvatarUrl={(value) => { clearEditError(); setEditAvatarUrl(value) }}
                nameId="edit-organization-name"
                slugId="edit-organization-slug"
                avatarId="edit-organization-avatar"
              />

              {updateOrg.error && (
                <Alert variant="destructive" className="border-red-500/20 bg-red-500/[0.06] text-red-300">
                  <AlertCircle />
                  <AlertDescription className="text-[11px] text-red-300/90">{updateOrg.error.message}</AlertDescription>
                </Alert>
              )}
            </>
          )}

          <DialogFooter>
            <Button
              variant="ghost"
              size="sm"
              onClick={closeEdit}
              className="h-8 text-[11px] text-white/50"
            >
              Cancel
            </Button>
            <Button
              size="sm"
              onClick={handleEdit}
              disabled={!canSaveEdit}
              className={cn(
                'h-8 text-[11px]',
                canSaveEdit
                  ? 'bg-rail-purple text-white hover:bg-rail-purple/90'
                  : 'bg-white/8 text-white/35'
              )}
            >
              {updateOrg.isPending ? <Loader2 className="animate-spin" /> : <Check />}
              {updateOrg.isPending ? 'Saving…' : 'Save changes'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <ConfirmDialog
        open={removeTarget !== null}
        onOpenChange={(open) => !open && setRemoveTarget(null)}
        title="Delete organization?"
        description={
          <>
            <span className="font-medium text-white">{removeTarget?.name}</span>, its projects, services and servers
            will be removed from RailDock. Apps and datastores already running on your hosts are left untouched, but
            RailDock will no longer deploy to or back them up.
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
