import { useState } from 'react'
import { Cloud, Plus, Trash2, Check, AlertCircle, Loader2, KeyRound, Star } from 'lucide-react'
import { useAuthStore } from '@/stores/useAuthStore'
import {
  useBackupDestinations,
  useCreateBackupDestination,
  useDeleteBackupDestination,
  useVerifyBackupDestination,
  useBackupDestinationDefaults,
  useUpdateBackupDestinationDefaults,
} from '@/hooks/useBackupDestinations'
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { useCopy } from '@/hooks/useCopy'
import { useDataSafety } from '@/hooks/useDataSafety'
import ConfirmDialog from '@/features/shared/ConfirmDialog'
import type { BackupDestination } from '@/types'

const EMPTY_FORM = {
  name: '',
  provider: 's3',
  endpoint: '',
  region: 'us-east-1',
  bucket: '',
  path_prefix: 'raildock',
  access_key_id: '',
  secret_access_key: '',
}

export default function BackupDestinationsTab() {
  const { currentOrganizationId } = useAuthStore()
  const { data: destinations = [], isLoading } = useBackupDestinations(currentOrganizationId || undefined)
  const create = useCreateBackupDestination()
  const remove = useDeleteBackupDestination()
  const verify = useVerifyBackupDestination()
  const { data: defaultDestinationIds = [] } = useBackupDestinationDefaults(currentOrganizationId || undefined)
  const updateDefaults = useUpdateBackupDestinationDefaults()
  const { data: safety } = useDataSafety(currentOrganizationId || undefined)
  const { copiedKey, copy } = useCopy(2000)

  const criticalFindings = safety?.findings.filter((finding) => finding.severity === 'critical') ?? []
  const warningFindings = safety?.findings.filter((finding) => finding.severity === 'warning') ?? []
  const [dialogOpen, setDialogOpen] = useState(false)
  const [recoveryKey, setRecoveryKey] = useState<string | null>(null)
  const [removeTarget, setRemoveTarget] = useState<BackupDestination | null>(null)
  const [form, setForm] = useState(EMPTY_FORM)

  const handleCreate = () => {
    if (!currentOrganizationId) return
    create.mutate(
      { organizationId: currentOrganizationId, data: form },
      {
        onSuccess: (data) => {
          setRecoveryKey(data.recoveryKey || null)
          setForm(EMPTY_FORM)
        },
      }
    )
  }

  const closeDialog = () => {
    setDialogOpen(false)
    setRecoveryKey(null)
    setForm(EMPTY_FORM)
  }

  // The organization-wide default: what a new backup on any service uses until
  // that service picks its own destinations.
  const toggleDefault = (destinationId: string) => {
    if (!currentOrganizationId) return
    const next = defaultDestinationIds.includes(destinationId)
      ? defaultDestinationIds.filter((id) => id !== destinationId)
      : [ ...defaultDestinationIds, destinationId ]
    updateDefaults.mutate({ organizationId: currentOrganizationId, destinationIds: next })
  }

  return (
    <div className="max-w-3xl space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-sm font-medium text-white">Backup Destinations</h2>
          <p className="text-[11px] text-[#6b6b7b] mt-0.5">
            S3-compatible destinations shared across all services in this organization. Star the ones every service
            should back up to by default.
          </p>
        </div>
        <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
          <DialogTrigger asChild>
            <Button size="sm" className="bg-rail-purple hover:bg-rail-purple/90 text-white text-xs h-8">
              <Plus size={14} className="mr-1" />
              Add Destination
            </Button>
          </DialogTrigger>
          <DialogContent className="bg-[#161618] border-[rgba(255,255,255,0.06)] text-[#F0F1F3] max-w-lg">
            <DialogHeader>
              <DialogTitle className="text-sm">Add Backup Destination</DialogTitle>
              <DialogDescription className="text-[11px] text-[#6b6b7b]">
                Files are encrypted with AES-256-GCM before leaving this server.
              </DialogDescription>
            </DialogHeader>

            {recoveryKey ? (
              <div className="space-y-3 py-2">
                <div className="p-3 rounded-lg border border-sky-500/20 bg-sky-500/10">
                  <div className="flex items-center gap-2 text-sky-300 text-[11px] font-medium mb-1">
                    <KeyRound size={13} />
                    Restores already work without this key
                  </div>
                  <p className="text-[10px] text-[#A0A0B0]">
                    RailDock keeps this key encrypted with the rest of its configuration, so restoring a backup
                    never asks you for it. Keep a copy only as a disaster-recovery escrow for the case where the
                    RailDock database itself is lost.
                  </p>
                </div>
                <div className="flex items-center gap-2">
                  <input
                    readOnly
                    value={recoveryKey}
                    onFocus={(event) => event.currentTarget.select()}
                    className="flex-1 text-[10px] font-mono text-[#A0A0B0] bg-[rgba(255,255,255,0.03)] rounded px-2 py-1.5 truncate border border-[rgba(255,255,255,0.08)] focus:outline-none"
                  />
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => copy(recoveryKey, 'recovery')}
                    className="text-[10px] text-[#A0A0B0] hover:text-white h-7 shrink-0"
                  >
                    {copiedKey === 'recovery' ? 'Copied!' : 'Copy'}
                  </Button>
                </div>
                <DialogFooter>
                  <Button onClick={closeDialog} className="bg-rail-purple hover:bg-rail-purple/90 text-white text-xs">
                    Done
                  </Button>
                </DialogFooter>
              </div>
            ) : (
              <div className="grid grid-cols-2 gap-3 py-2">
                <div className="col-span-2">
                  <label className="text-[11px] text-[#A0A0B0] mb-1 block">Name</label>
                  <Input
                    value={form.name}
                    onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))}
                    placeholder="Production S3"
                    className="bg-[rgba(255,255,255,0.04)] border-[rgba(255,255,255,0.08)] text-sm h-9"
                  />
                </div>
                <div>
                  <label className="text-[11px] text-[#A0A0B0] mb-1 block">Provider</label>
                  <Select value={form.provider} onValueChange={(v) => setForm((f) => ({ ...f, provider: v }))}>
                    <SelectTrigger className="bg-[rgba(255,255,255,0.04)] border-[rgba(255,255,255,0.08)] text-sm h-9">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="s3">Amazon S3</SelectItem>
                      <SelectItem value="r2">Cloudflare R2</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <label className="text-[11px] text-[#A0A0B0] mb-1 block">Region</label>
                  <Input
                    value={form.region}
                    onChange={(e) => setForm((f) => ({ ...f, region: e.target.value }))}
                    placeholder="us-east-1"
                    className="bg-[rgba(255,255,255,0.04)] border-[rgba(255,255,255,0.08)] text-sm h-9"
                  />
                </div>
                <div className="col-span-2">
                  <label className="text-[11px] text-[#A0A0B0] mb-1 block">Endpoint (optional for AWS S3)</label>
                  <Input
                    value={form.endpoint}
                    onChange={(e) => setForm((f) => ({ ...f, endpoint: e.target.value }))}
                    placeholder="https://s3.us-east-1.amazonaws.com"
                    className="bg-[rgba(255,255,255,0.04)] border-[rgba(255,255,255,0.08)] text-sm h-9"
                  />
                </div>
                <div>
                  <label className="text-[11px] text-[#A0A0B0] mb-1 block">Bucket</label>
                  <Input
                    value={form.bucket}
                    onChange={(e) => setForm((f) => ({ ...f, bucket: e.target.value }))}
                    placeholder="my-backups"
                    className="bg-[rgba(255,255,255,0.04)] border-[rgba(255,255,255,0.08)] text-sm h-9"
                  />
                </div>
                <div>
                  <label className="text-[11px] text-[#A0A0B0] mb-1 block">Path prefix</label>
                  <Input
                    value={form.path_prefix}
                    onChange={(e) => setForm((f) => ({ ...f, path_prefix: e.target.value }))}
                    placeholder="raildock"
                    className="bg-[rgba(255,255,255,0.04)] border-[rgba(255,255,255,0.08)] text-sm h-9"
                  />
                </div>
                <div>
                  <label className="text-[11px] text-[#A0A0B0] mb-1 block">Access key ID</label>
                  <Input
                    value={form.access_key_id}
                    onChange={(e) => setForm((f) => ({ ...f, access_key_id: e.target.value }))}
                    placeholder="AKIA..."
                    className="bg-[rgba(255,255,255,0.04)] border-[rgba(255,255,255,0.08)] text-sm h-9"
                  />
                </div>
                <div>
                  <label className="text-[11px] text-[#A0A0B0] mb-1 block">Secret access key</label>
                  <Input
                    type="password"
                    value={form.secret_access_key}
                    onChange={(e) => setForm((f) => ({ ...f, secret_access_key: e.target.value }))}
                    placeholder="••••••••"
                    className="bg-[rgba(255,255,255,0.04)] border-[rgba(255,255,255,0.08)] text-sm h-9"
                  />
                </div>
              </div>
            )}

            {!recoveryKey && (
              <DialogFooter>
                <Button
                  onClick={handleCreate}
                  disabled={create.isPending || !form.name.trim() || !form.bucket.trim() || !form.region.trim() || !form.access_key_id.trim() || !form.secret_access_key.trim()}
                  className="bg-rail-purple hover:bg-rail-purple/90 text-white text-xs"
                >
                  {create.isPending ? (
                    <>
                      <Loader2 size={12} className="mr-1 animate-spin" />
                      Verifying…
                    </>
                  ) : (
                    'Verify & save'
                  )}
                </Button>
              </DialogFooter>
            )}
          </DialogContent>
        </Dialog>
      </div>

      {(criticalFindings.length > 0 || warningFindings.length > 0) && (
        <div
          className={`rounded-xl border p-3 ${
            criticalFindings.length > 0
              ? 'border-red-500/20 bg-red-500/[0.04]'
              : 'border-amber-400/15 bg-amber-400/[0.035]'
          }`}
        >
          <div className="flex items-start gap-2">
            <AlertCircle
              size={14}
              className={`mt-0.5 shrink-0 ${criticalFindings.length > 0 ? 'text-red-400' : 'text-amber-300'}`}
            />
            <div className="min-w-0">
              <div className="text-[12px] text-white/70">
                {criticalFindings.length > 0
                  ? `${criticalFindings.length} service${criticalFindings.length === 1 ? '' : 's'} cannot be restored today`
                  : `${warningFindings.length} data protection warning${warningFindings.length === 1 ? '' : 's'}`}
              </div>
              <ul className="mt-1.5 space-y-1">
                {[...criticalFindings, ...warningFindings].slice(0, 4).map((finding) => (
                  <li key={`${finding.code}-${finding.message}`} className="text-[11px] text-white/50">
                    {finding.message}
                  </li>
                ))}
              </ul>
              {[...criticalFindings, ...warningFindings].length > 4 && (
                <div className="mt-1 text-[10px] text-white/50">
                  +{[...criticalFindings, ...warningFindings].length - 4} more
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {isLoading ? (
        <div className="text-[11px] text-[#6b6b7b]">Loading destinations…</div>
      ) : destinations.length === 0 ? (
        <div className="bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-xl p-8 text-center">
          <Cloud size={24} className="text-[#6b6b7b] mx-auto mb-2" />
          <p className="text-sm text-[#A0A0B0]">No backup destinations yet</p>
          <p className="text-[11px] text-[#6b6b7b] mt-1">
            Add an S3-compatible destination so services can back up off-site.
          </p>
        </div>
      ) : (
        <div className="space-y-2">
          {destinations.map((destination: BackupDestination) => (
            <div
              key={destination.id}
              className="flex flex-col gap-2 p-4 rounded-xl border bg-[rgba(255,255,255,0.02)] border-[rgba(255,255,255,0.05)]"
            >
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <Cloud size={14} className="text-rail-purple" />
                  <span className="text-sm text-white font-medium">{destination.name}</span>
                  <StatusBadge destination={destination} />
                  {defaultDestinationIds.includes(destination.id) && (
                    <span className="rounded bg-amber-400/10 px-1.5 py-0.5 text-[10px] text-amber-300">default</span>
                  )}
                </div>
                <div className="flex items-center gap-1">
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => toggleDefault(destination.id)}
                    disabled={updateDefaults.isPending}
                    aria-pressed={defaultDestinationIds.includes(destination.id)}
                    aria-label={`Use ${destination.name} by default`}
                    title={defaultDestinationIds.includes(destination.id)
                      ? 'Stop using this destination by default'
                      : 'Use this destination by default'}
                    className="h-7 text-[11px] text-[#A0A0B0] hover:text-white"
                  >
                    <Star
                      size={13}
                      className={defaultDestinationIds.includes(destination.id) ? 'fill-amber-300 text-amber-300' : ''}
                    />
                  </Button>
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => currentOrganizationId && verify.mutate({ organizationId: currentOrganizationId, destinationId: destination.id })}
                    disabled={verify.isPending}
                    className="text-[11px] text-[#A0A0B0] hover:text-white h-7"
                  >
                    {verify.isPending ? <Loader2 size={12} className="animate-spin" /> : <Check size={13} />}
                  </Button>
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => setRemoveTarget(destination)}
                    className="text-[11px] text-[#6b6b7b] hover:text-red-400 h-7"
                    aria-label={`Delete destination ${destination.name}`}
                  >
                    <Trash2 size={13} />
                  </Button>
                </div>
              </div>
              <div className="text-[10px] text-[#6b6b7b] flex flex-wrap gap-x-4 gap-y-1">
                <span className="capitalize">{destination.provider}</span>
                <span>{destination.bucket}</span>
                <span>{destination.region}</span>
                {destination.pathPrefix && <span>prefix: {destination.pathPrefix}</span>}
              </div>
            </div>
          ))}
        </div>
      )}

      <ConfirmDialog
        open={removeTarget !== null}
        onOpenChange={(open) => !open && setRemoveTarget(null)}
        title="Delete backup destination?"
        description={
          <>
            RailDock will stop writing backups to <span className="font-medium text-white">{removeTarget?.name}</span>.
            Backups already stored there are <span className="text-white/80">not</span> removed — you can still restore
            from them, and you would need the destination's key to read them again.
          </>
        }
        confirmLabel="Delete destination"
        destructive
        pending={remove.isPending}
        onConfirm={async () => {
          if (!removeTarget || !currentOrganizationId) return
          try {
            await remove.mutateAsync({ organizationId: currentOrganizationId, destinationId: removeTarget.id })
            setRemoveTarget(null)
          } catch {
            /* surfaced by the mutation hook */
          }
        }}
      />
    </div>
  )
}

function StatusBadge({ destination }: { destination: BackupDestination }) {
  if (destination.status === 'verified') {
    return <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400">Verified</span>
  }
  if (destination.status === 'failed') {
    return <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-red-500/10 text-red-400 flex items-center gap-1"><AlertCircle size={9} /> Failed</span>
  }
  return <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-amber-500/10 text-amber-400">Pending</span>
}
