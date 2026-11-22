import type { Backup, Service } from '@/types'

// ── Formatting ────────────────────────────────────────────────────────────

export function formatSize(bytes = 0) {
  if (!bytes) return '—'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  const unit = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1)
  return `${(bytes / 1024 ** unit).toFixed(unit ? 1 : 0)} ${units[unit]}`
}

export function formatDate(value?: string) {
  return value ? new Date(value).toLocaleString() : 'Not yet run'
}

/** "in 6h" / "2d ago" — the countdown operators actually scan for. */
export function formatRelative(value?: string) {
  if (!value) return 'not scheduled'
  const diff = new Date(value).getTime() - Date.now()
  const abs = Math.abs(diff)
  const units: [number, string][] = [[86400000, 'd'], [3600000, 'h'], [60000, 'm']]
  for (const [ms, label] of units) {
    if (abs >= ms) {
      const count = Math.round(abs / ms)
      return diff >= 0 ? `in ${count}${label}` : `${count}${label} ago`
    }
  }
  return diff >= 0 ? 'in <1m' : 'just now'
}

// ── Capabilities ──────────────────────────────────────────────────────────

/**
 * Engines whose Dokku plugin can export and import a logical dump. Mirrors the
 * `backup`/`restore` capabilities in `PluginRegistry`; Redis is a cache, not a
 * database, but it backs up like one.
 */
const LOGICAL_BACKUP_SUBTYPES = new Set(['postgres', 'mysql', 'mariadb', 'mongo', 'redis'])

export function supportsLogicalBackup(svc: Pick<Service, 'subtype'>) {
  return LOGICAL_BACKUP_SUBTYPES.has(svc.subtype)
}

export function supportsPitr(svc: Pick<Service, 'subtype'>) {
  return svc.subtype === 'postgres'
}

const ENGINE_EXTENSION: Record<string, string> = {
  postgres: '.dump',
  mysql: '.sql',
  mariadb: '.sql',
  mongo: '.archive',
  redis: '.rdb',
}

export function artifactFilename(svc: Pick<Service, 'name' | 'subtype'>, backup: Backup) {
  const base = `${svc.name}-${backup.id}`
  if (backup.backupKind === 'volume' || backup.backupKind === 'pitr_base') return `${base}.tar.gz`
  return `${base}${ENGINE_EXTENSION[svc.subtype] ?? '.backup'}`
}

// Retention defaults follow the platform conventions (a week of dailies, a
// month of weeklies, two quarters of monthlies) and match the backend.
export const DEFAULT_RETENTION: Record<string, number> = { daily: 7, weekly: 4, monthly: 6 }
export const MAX_RETENTION = 90
export const FREQUENCY_LABEL: Record<string, string> = { daily: 'Daily', weekly: 'Weekly', monthly: 'Monthly' }

const TRIGGER_LABEL: Record<string, string> = {
  manual: 'Manual',
  scheduled: 'Scheduled',
  pitr: 'PITR base',
  pre_destroy: 'Before delete',
  pre_restore: 'Before restore',
}

export function triggerLabel(backup: Backup) {
  const trigger = backup.metadata?.trigger
  if (trigger && TRIGGER_LABEL[trigger]) return TRIGGER_LABEL[trigger]
  if (backup.metadata?.scheduleId) return 'Scheduled'
  return trigger ?? null
}


export function toggleId(list: string[], id: string) {
  return list.includes(id) ? list.filter((item) => item !== id) : [...list, id]
}
