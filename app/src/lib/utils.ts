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
