import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

/**
 * Border styling for "type the name to confirm" inputs.
 *
 * An empty field keeps a neutral border: the input is autofocused but has no
 * value yet, so an error-coloured border reads as a validation failure the user
 * cannot fix. Red is reserved for text that was actually typed and does not
 * match; green means the value is ready to submit.
 */
export function confirmationFieldTone(value: string, isValid: boolean) {
  if (value.length === 0) {
    return 'border-[rgba(255,255,255,0.08)] focus:border-[rgba(255,255,255,0.2)]'
  }

  return isValid
    ? 'border-emerald-500/40 focus:border-emerald-500/50'
    : 'border-red-500/40 focus:border-red-500/50'
}

/**
 * Render a host metric as GB.
 *
 * The API stores `disk_*` and `memory_*` in MB, so the raw number must be
 * scaled before it is labelled GB — printing `18400/60000 GB` overstates the
 * host by three orders of magnitude. Values are rounded to one decimal (or to
 * whole GB once they are large enough that the fraction is noise).
 */
export function formatMbAsGb(mb: number) {
  if (!Number.isFinite(mb) || mb <= 0) return '0'

  const gb = mb / 1024
  return String(gb >= 100 ? Math.round(gb) : Math.round(gb * 10) / 10)
}
