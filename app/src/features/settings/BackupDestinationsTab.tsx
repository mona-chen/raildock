import { useState } from 'react'
import { Cloud, Plus, Trash2, AlertCircle, Loader2, KeyRound, Star, Pencil, RefreshCw } from 'lucide-react'
import { useAuthStore } from '@/stores/useAuthStore'
import {
  useBackupDestinations,
  useCreateBackupDestination,
  useUpdateBackupDestination,
  useDeleteBackupDestination,
  useVerifyBackupDestination,
  useBackupDestinationDefaults,
  useUpdateBackupDestinationDefaults,
} from '@/hooks/useBackupDestinations'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { IconButton } from '@/components/ui/icon-button'
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
import { useCopy } from '@/hooks/useCopy'
import { useDataSafety } from '@/hooks/useDataSafety'
import ConfirmDialog from '@/features/shared/ConfirmDialog'
import type { BackupDestination } from '@/types'

interface ProviderPreset {
  value: string
  label: string
  defaultRegion: string
  regionPlaceholder: string
  endpointPlaceholder: string
  /** No endpoint can be derived from the region, so the user must supply one. */
  endpointRequired: boolean
  hint: string
}

// Mirrors BackupDestination::PROVIDERS on the backend. Presets with a derived
// endpoint fill it from the region when the field is left blank.
const PROVIDER_PRESETS: ProviderPreset[] = [
  { value: 's3', label: 'Amazon S3', defaultRegion: 'us-east-1', regionPlaceholder: 'us-east-1', endpointPlaceholder: 'Leave blank for AWS', endpointRequired: false, hint: 'Use an IAM user whose policy is limited to this bucket.' },
  { value: 'r2', label: 'Cloudflare R2', defaultRegion: 'auto', regionPlaceholder: 'auto', endpointPlaceholder: 'https://<account-id>.r2.cloudflarestorage.com', endpointRequired: true, hint: 'Create an R2 API token with Object Read & Write on this bucket. Region is always auto.' },
  { value: 'b2', label: 'Backblaze B2', defaultRegion: 'us-west-004', regionPlaceholder: 'us-west-004', endpointPlaceholder: 'https://s3.<region>.backblazeb2.com', endpointRequired: false, hint: 'Use an application key. The region is part of the bucket’s S3 endpoint.' },
  { value: 'wasabi', label: 'Wasabi', defaultRegion: 'us-east-1', regionPlaceholder: 'us-east-1', endpointPlaceholder: 'https://s3.<region>.wasabisys.com', endpointRequired: false, hint: 'Use the region the bucket was created in; Wasabi rejects requests signed for another.' },
  { value: 'spaces', label: 'DigitalOcean Spaces', defaultRegion: 'nyc3', regionPlaceholder: 'nyc3', endpointPlaceholder: 'https://<region>.digitaloceanspaces.com', endpointRequired: false, hint: 'Use a Spaces access key. The region is the datacenter slug, such as nyc3 or fra1.' },
  { value: 'hetzner', label: 'Hetzner Object Storage', defaultRegion: 'fsn1', regionPlaceholder: 'fsn1', endpointPlaceholder: 'https://<region>.your-objectstorage.com', endpointRequired: false, hint: 'Locations are fsn1, nbg1 and hel1. Create the credentials in the Cloud Console project.' },
  { value: 'minio', label: 'MinIO', defaultRegion: 'us-east-1', regionPlaceholder: 'us-east-1', endpointPlaceholder: 'https://minio.example.com:9000', endpointRequired: true, hint: 'Path-style addressing is used, so no wildcard DNS is needed.' },
  { value: 'gcs', label: 'Google Cloud Storage', defaultRegion: 'auto', regionPlaceholder: 'auto', endpointPlaceholder: 'https://storage.googleapis.com', endpointRequired: false, hint: 'Create an HMAC key under Cloud Storage → Settings → Interoperability.' },
]

function presetFor(provider: string): ProviderPreset {
  return PROVIDER_PRESETS.find((preset) => preset.value === provider) ?? PROVIDER_PRESETS[0]
}

const RECOVERY_KEY_PATTERN = /^[0-9a-f]{64}$/i

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

type FormState = typeof EMPTY_FORM

const INPUT_CLASS = 'bg-[rgba(255,255,255,0.04)] border-[rgba(255,255,255,0.08)] text-sm h-9'

function formatTimestamp(value?: string) {
  if (!value) return null
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? null : date.toLocaleString()
}

export default function BackupDestinationsTab() {
  const { currentOrganizationId, currentOrganization } = useAuthStore()
  // Role is unknown until the organization list loads; the API still enforces
  // owner/admin, so an unknown role keeps the controls rather than hiding them.
  const role = typeof currentOrganization === 'function' ? currentOrganization()?.role : undefined
  const canManage = role !== 'member'

  const { data: destinations = [], isLoading } = useBackupDestinations(currentOrganizationId || undefined)
  const create = useCreateBackupDestination()
  const update = useUpdateBackupDestination()
  const remove = useDeleteBackupDestination()
  const verify = useVerifyBackupDestination()
  const { data: defaultDestinationIds = [] } = useBackupDestinationDefaults(currentOrganizationId || undefined)
  const updateDefaults = useUpdateBackupDestinationDefaults()
  const { data: safety } = useDataSafety(currentOrganizationId || undefined)
  const { copiedKey, copy } = useCopy(2000)

  const criticalFindings = safety?.findings.filter((finding) => finding.severity === 'critical') ?? []
  const warningFindings = safety?.findings.filter((finding) => finding.severity === 'warning') ?? []
  const [dialogOpen, setDialogOpen] = useState(false)
  // null while adding; the destination being edited otherwise.
  const [editing, setEditing] = useState<BackupDestination | null>(null)
  const [recoveryKey, setRecoveryKey] = useState<string | null>(null)
  const [removeTarget, setRemoveTarget] = useState<BackupDestination | null>(null)
  const [removeError, setRemoveError] = useState<string | null>(null)
  const [verifying, setVerifying] = useState<Set<string>>(() => new Set())
  const [form, setForm] = useState<FormState>(EMPTY_FORM)
  const [ownKey, setOwnKey] = useState(false)
  const [customKey, setCustomKey] = useState('')

  const preset = presetFor(form.provider)
  const isEditing = editing !== null
  const customKeyInvalid = ownKey && !RECOVERY_KEY_PATTERN.test(customKey.trim())
  const endpointMissing = preset.endpointRequired && !form.endpoint.trim()
  // Editing keeps stored secrets when the fields are left blank.
  const secretsMissing = !isEditing && (!form.access_key_id.trim() || !form.secret_access_key.trim())
  const submitDisabled =
    create.isPending || update.isPending || !form.name.trim() || !form.bucket.trim() || !form.region.trim() ||
    endpointMissing || secretsMissing || (!isEditing && customKeyInvalid)

  const resetForm = () => {
    setForm(EMPTY_FORM)
    setOwnKey(false)
    setCustomKey('')
  }

  const openCreate = () => {
    setEditing(null)
    setRecoveryKey(null)
    resetForm()
    setDialogOpen(true)
  }

  const openEdit = (destination: BackupDestination) => {
    setEditing(destination)
    setRecoveryKey(null)
    setOwnKey(false)
    setCustomKey('')
    setForm({
      name: destination.name,
      provider: destination.provider,
      endpoint: destination.endpoint ?? '',
      region: destination.region,
      bucket: destination.bucket,
      path_prefix: destination.pathPrefix ?? '',
      access_key_id: '',
      secret_access_key: '',
    })
    setDialogOpen(true)
  }

  const closeDialog = () => {
    setDialogOpen(false)
    setEditing(null)
    setRecoveryKey(null)
    resetForm()
  }

  const changeProvider = (provider: string) => {
    setForm((current) => {
      const previous = presetFor(current.provider)
      // Only replace a region the user has not chosen themselves.
      const region = !current.region.trim() || current.region === previous.defaultRegion
        ? presetFor(provider).defaultRegion
        : current.region
      return { ...current, provider, region }
    })
  }

  const handleSubmit = () => {
    if (!currentOrganizationId) return
    const data: Record<string, string> = { ...form }
    if (!data.access_key_id.trim()) delete data.access_key_id
    if (!data.secret_access_key.trim()) delete data.secret_access_key

    if (editing) {
      update.mutate(
        { organizationId: currentOrganizationId, destinationId: editing.id, data },
        { onSuccess: closeDialog }
      )
      return
    }

    if (ownKey) data.encryption_key = customKey.trim().toLowerCase()
    create.mutate(
      { organizationId: currentOrganizationId, data },
      {
        onSuccess: (created) => {
          // Only a generated key comes back; one the user supplied is already
          // in their hands.
          if (created.recoveryKey) {
            setRecoveryKey(created.recoveryKey)
            resetForm()
          } else {
            closeDialog()
          }
        },
      }
    )
  }

  const runVerify = (destinationId: string) => {
    if (!currentOrganizationId) return
    setVerifying((current) => new Set(current).add(destinationId))
    verify.mutate(
      { organizationId: currentOrganizationId, destinationId },
      {
        onSettled: () =>
          setVerifying((current) => {
            const next = new Set(current)
            next.delete(destinationId)
            return next
          }),
      }
    )
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
          {!canManage && (
            <p className="text-[11px] text-[#6b6b7b] mt-1">Only owners and admins can change backup destinations.</p>
          )}
        </div>
        {canManage && (
          <Button size="sm" onClick={openCreate} className="bg-rail-purple hover:bg-rail-purple/90 text-white text-xs h-8">
            <Plus size={14} className="mr-1" />
            Add Destination
          </Button>
        )}
      </div>

      <Dialog open={dialogOpen} onOpenChange={(open) => (open ? setDialogOpen(true) : closeDialog())}>
        <DialogContent className="bg-[#161618] border-[rgba(255,255,255,0.06)] text-[#F0F1F3] max-w-lg">
          <DialogHeader>
            <DialogTitle className="text-sm">{isEditing ? `Edit ${editing?.name}` : 'Add Backup Destination'}</DialogTitle>
            <DialogDescription className="text-[11px] text-[#6b6b7b]">
              {isEditing
                ? 'Changed connection settings are verified before they replace the current ones. The recovery key cannot change.'
                : 'Files are encrypted with AES-256-GCM before leaving this server.'}
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
                  RailDock database itself is lost. It is shown only once.
                </p>
              </div>
              <div className="flex items-center gap-2">
                <input
                  readOnly
                  aria-label="Recovery key"
                  value={recoveryKey}
                  onFocus={(event) => event.currentTarget.select()}
                  className="flex-1 text-[10px] font-mono text-[#A0A0B0] bg-[rgba(255,255,255,0.03)] rounded px-2 py-1.5 truncate border border-[rgba(255,255,255,0.08)] focus:outline-hidden"
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
            <>
              <div className="grid grid-cols-2 gap-3 py-2">
                <div className="col-span-2">
                  <label htmlFor="destination-name" className="text-[11px] text-[#A0A0B0] mb-1 block">Name</label>
                  <Input
                    id="destination-name"
                    value={form.name}
                    onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))}
                    placeholder="Production S3"
                    className={INPUT_CLASS}
                  />
                </div>
                <div>
                  <span id="destination-provider-label" className="text-[11px] text-[#A0A0B0] mb-1 block">Provider</span>
                  <Select value={form.provider} onValueChange={changeProvider}>
                    <SelectTrigger aria-labelledby="destination-provider-label" className={INPUT_CLASS}>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {PROVIDER_PRESETS.map((option) => (
                        <SelectItem key={option.value} value={option.value}>{option.label}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <label htmlFor="destination-region" className="text-[11px] text-[#A0A0B0] mb-1 block">Region</label>
                  <Input
                    id="destination-region"
                    value={form.region}
                    onChange={(e) => setForm((f) => ({ ...f, region: e.target.value }))}
                    placeholder={preset.regionPlaceholder}
                    className={INPUT_CLASS}
                  />
                </div>
                <p className="col-span-2 -mt-1 text-[10px] text-[#6b6b7b]" data-testid="provider-hint">{preset.hint}</p>
                <div className="col-span-2">
                  <label htmlFor="destination-endpoint" className="text-[11px] text-[#A0A0B0] mb-1 block">
                    {preset.endpointRequired
                      ? 'Endpoint'
                      : preset.value === 's3'
                        ? 'Endpoint (optional for AWS S3)'
                        : 'Endpoint (optional, derived from the region)'}
                  </label>
                  <Input
                    id="destination-endpoint"
                    value={form.endpoint}
                    onChange={(e) => setForm((f) => ({ ...f, endpoint: e.target.value }))}
                    placeholder={preset.endpointPlaceholder}
                    aria-required={preset.endpointRequired}
                    className={INPUT_CLASS}
                  />
                </div>
                <div>
                  <label htmlFor="destination-bucket" className="text-[11px] text-[#A0A0B0] mb-1 block">Bucket</label>
                  <Input
                    id="destination-bucket"
                    value={form.bucket}
                    onChange={(e) => setForm((f) => ({ ...f, bucket: e.target.value }))}
                    placeholder="my-backups"
                    className={INPUT_CLASS}
                  />
                </div>
                <div>
                  <label htmlFor="destination-prefix" className="text-[11px] text-[#A0A0B0] mb-1 block">Path prefix</label>
                  <Input
                    id="destination-prefix"
                    value={form.path_prefix}
                    onChange={(e) => setForm((f) => ({ ...f, path_prefix: e.target.value }))}
                    placeholder="raildock"
                    className={INPUT_CLASS}
                  />
                </div>
                <div>
                  <label htmlFor="destination-access-key" className="text-[11px] text-[#A0A0B0] mb-1 block">Access key ID</label>
                  <Input
                    id="destination-access-key"
                    value={form.access_key_id}
                    onChange={(e) => setForm((f) => ({ ...f, access_key_id: e.target.value }))}
                    placeholder={isEditing ? 'Leave blank to keep current' : 'AKIA...'}
                    autoComplete="off"
                    className={INPUT_CLASS}
                  />
                </div>
                <div>
                  <label htmlFor="destination-secret" className="text-[11px] text-[#A0A0B0] mb-1 block">Secret access key</label>
                  <Input
                    id="destination-secret"
                    type="password"
                    value={form.secret_access_key}
                    onChange={(e) => setForm((f) => ({ ...f, secret_access_key: e.target.value }))}
                    placeholder={isEditing ? 'Leave blank to keep current' : '••••••••'}
                    autoComplete="new-password"
                    className={INPUT_CLASS}
                  />
                </div>
                {!isEditing && (
                  <div className="col-span-2 space-y-2">
                    <label className="flex items-center gap-2 text-[11px] text-[#A0A0B0]">
                      <input
                        type="checkbox"
                        checked={ownKey}
                        onChange={(e) => setOwnKey(e.target.checked)}
                        className="accent-rail-purple"
                      />
                      Use my own recovery key
                    </label>
                    {ownKey && (
                      <div>
                        <Input
                          aria-label="Your recovery key"
                          value={customKey}
                          onChange={(e) => setCustomKey(e.target.value)}
                          placeholder="64 hexadecimal characters"
                          autoComplete="off"
                          aria-invalid={customKey.length > 0 && customKeyInvalid}
                          className={`${INPUT_CLASS} font-mono text-[11px]`}
                        />
                        <p className={`mt-1 text-[10px] ${customKey.length > 0 && customKeyInvalid ? 'text-red-400' : 'text-[#6b6b7b]'}`}>
                          {customKey.length > 0 && customKeyInvalid
                            ? `Must be exactly 64 hexadecimal characters (${customKey.trim().length} entered).`
                            : 'Generate one with: openssl rand -hex 32. It cannot be changed later.'}
                        </p>
                      </div>
                    )}
                  </div>
                )}
              </div>
              <DialogFooter>
                <Button
                  onClick={handleSubmit}
                  disabled={submitDisabled}
                  className="bg-rail-purple hover:bg-rail-purple/90 text-white text-xs"
                >
                  {create.isPending || update.isPending ? (
                    <>
                      <Loader2 size={12} className="mr-1 animate-spin" />
                      Verifying…
                    </>
                  ) : (
                    'Verify & save'
                  )}
                </Button>
              </DialogFooter>
            </>
          )}
        </DialogContent>
      </Dialog>

      {(criticalFindings.length > 0 || warningFindings.length > 0) && (
        <div
          className={`rounded-xl border p-3 ${
            criticalFindings.length > 0
              ? 'border-red-500/20 bg-red-500/4'
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
          {destinations.map((destination: BackupDestination) => {
            const isDefault = defaultDestinationIds.includes(destination.id)
            const isVerifying = verifying.has(destination.id)
            // A default receives every service's backups; an unproven or
            // broken destination would make all of them fail. Removing an
            // existing star is always allowed.
            const canStar = destination.status === 'verified' || isDefault
            const starTitle = !canManage
              ? 'Only owners and admins can change the default'
              : !canStar
                ? 'Verify this destination before making it a default: every service would back up to it'
                : isDefault
                  ? 'Stop using this destination by default'
                  : 'Use this destination by default'
            const lastVerified = formatTimestamp(destination.lastVerifiedAt)

            return (
              <div
                key={destination.id}
                className="flex flex-col gap-2 p-4 rounded-xl border bg-[rgba(255,255,255,0.02)] border-[rgba(255,255,255,0.05)]"
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <Cloud size={14} className="text-rail-purple" />
                    <span className="text-sm text-white font-medium">{destination.name}</span>
                    <StatusBadge destination={destination} />
                    {isDefault && (
                      <span className="rounded bg-amber-400/10 px-1.5 py-0.5 text-[10px] text-amber-300">default</span>
                    )}
                  </div>
                  <div className="flex items-center gap-1">
                    <IconButton
                      onClick={() => toggleDefault(destination.id)}
                      disabled={!canManage || !canStar || updateDefaults.isPending}
                      aria-pressed={isDefault}
                      aria-label={`Use ${destination.name} by default`}
                      title={starTitle}
                    >
                      <Star className={isDefault ? 'fill-amber-300 text-amber-300' : ''} />
                    </IconButton>
                    {canManage && (
                      <>
                        <IconButton
                          onClick={() => runVerify(destination.id)}
                          disabled={isVerifying}
                          aria-label={`Verify ${destination.name}`}
                          title={isVerifying ? 'Verifying…' : 'Verify now: writes, reads back and deletes a small test object'}
                        >
                          {isVerifying ? <Loader2 className="animate-spin" /> : <RefreshCw />}
                        </IconButton>
                        <IconButton
                          onClick={() => openEdit(destination)}
                          aria-label={`Edit ${destination.name}`}
                          title="Edit name, endpoint or credentials"
                        >
                          <Pencil />
                        </IconButton>
                        <IconButton
                          onClick={() => {
                            setRemoveError(null)
                            setRemoveTarget(destination)
                          }}
                          aria-label={`Delete destination ${destination.name}`}
                          title="Delete destination"
                          className="hover:text-red-400"
                        >
                          <Trash2 />
                        </IconButton>
                      </>
                    )}
                  </div>
                </div>
                <div className="text-[10px] text-[#6b6b7b] flex flex-wrap gap-x-4 gap-y-1">
                  <span>{presetFor(destination.provider).label}</span>
                  <span>{destination.bucket}</span>
                  <span>{destination.region}</span>
                  {destination.pathPrefix && <span>prefix: {destination.pathPrefix}</span>}
                  <span>{lastVerified ? `last verified ${lastVerified}` : 'never verified'}</span>
                </div>
                {destination.status === 'failed' && destination.lastError && (
                  <p className="text-[10px] text-red-400/90 break-words" role="status">
                    {destination.lastError}
                  </p>
                )}
              </div>
            )
          })}
        </div>
      )}

      <ConfirmDialog
        open={removeTarget !== null}
        onOpenChange={(open) => {
          if (!open) {
            setRemoveTarget(null)
            setRemoveError(null)
          }
        }}
        title="Delete backup destination?"
        description={
          <>
            RailDock will remove <span className="font-medium text-white">{removeTarget?.name}</span> and its stored
            credentials and recovery key. A destination that still holds backups, backup copies or a point-in-time
            recovery configuration cannot be deleted: remove those first. Nothing in the bucket itself is deleted.
          </>
        }
        confirmLabel="Delete destination"
        destructive
        pending={remove.isPending}
        error={removeError}
        onConfirm={async () => {
          if (!removeTarget || !currentOrganizationId) return
          setRemoveError(null)
          try {
            await remove.mutateAsync({ organizationId: currentOrganizationId, destinationId: removeTarget.id })
            setRemoveTarget(null)
          } catch (error) {
            setRemoveError(error instanceof Error ? error.message : 'The destination could not be deleted.')
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
