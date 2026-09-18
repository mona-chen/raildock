// Single source of truth for how a service or deployment status is labelled and
// coloured. Before this existed the same mapping was re-implemented inline in
// ServiceCard, OverviewTab and ServicePanel, and they disagreed ("error" vs
// "Error"), so the same service looked different depending on where you saw it.

export interface StatusMeta {
  /** Human label shown to the user. */
  label: string
  /** Hex colour for a status dot / accent. */
  color: string
  /** Tailwind classes for a pill/badge. */
  badge: string
}

const STATUS_META: Record<string, StatusMeta> = {
  running: { label: 'Online', color: '#22c55e', badge: 'bg-emerald-500/15 text-emerald-300 border-emerald-500/20' },
  succeeded: { label: 'Succeeded', color: '#22c55e', badge: 'bg-emerald-500/15 text-emerald-300 border-emerald-500/20' },
  building: { label: 'Building', color: '#eab308', badge: 'bg-amber-500/15 text-amber-300 border-amber-500/20' },
  deploying: { label: 'Deploying', color: '#8b5cf6', badge: 'bg-[#8b5cf6]/15 text-[#c4b5fd] border-[#8b5cf6]/25' },
  stopped: { label: 'Stopped', color: '#f97316', badge: 'bg-orange-500/15 text-orange-300 border-orange-500/20' },
  error: { label: 'Error', color: '#ef4444', badge: 'bg-red-500/15 text-red-300 border-red-500/20' },
  failed: { label: 'Failed', color: '#ef4444', badge: 'bg-red-500/15 text-red-300 border-red-500/20' },
  crashed: { label: 'Crashed', color: '#ef4444', badge: 'bg-red-500/15 text-red-300 border-red-500/20' },
  cancelled: { label: 'Cancelled', color: '#6b7280', badge: 'bg-white/[0.06] text-white/60 border-white/[0.08]' },
  pending: { label: 'Pending', color: '#a0a0b0', badge: 'bg-white/[0.06] text-white/70 border-white/[0.08]' },
  queued: { label: 'Queued', color: '#a0a0b0', badge: 'bg-white/[0.06] text-white/70 border-white/[0.08]' },
  connected: { label: 'Connected', color: '#22c55e', badge: 'bg-emerald-500/15 text-emerald-300 border-emerald-500/20' },
  disconnected: { label: 'Disconnected', color: '#6b7280', badge: 'bg-white/[0.06] text-white/60 border-white/[0.08]' },
}

const FALLBACK: StatusMeta = {
  label: 'Unknown',
  color: '#6b6b7b',
  badge: 'bg-white/[0.06] text-white/60 border-white/[0.08]',
}

/**
 * Map a raw status string to its canonical label, dot colour and badge classes.
 * Unknown statuses fall back to a title-cased label so nothing renders blank.
 */
export function statusMeta(status: string | null | undefined): StatusMeta {
  if (!status) return FALLBACK

  const known = STATUS_META[status.toLowerCase()]
  if (known) return known

  return {
    ...FALLBACK,
    label: status.charAt(0).toUpperCase() + status.slice(1).replace(/_/g, ' '),
  }
}
