const DEBUG = import.meta.env.DEV

export function debugLog(...args: unknown[]) {
  if (DEBUG) console.log(...args)
}

export function debugWarn(...args: unknown[]) {
  if (DEBUG) console.warn(...args)
}
