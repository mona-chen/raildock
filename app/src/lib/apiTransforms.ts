/**
 * API request/response transformation helpers.
 * Rails backend uses snake_case; frontend types use camelCase.
 */

export function camelizeKeys(obj: unknown): unknown {
  if (Array.isArray(obj)) return obj.map(camelizeKeys)
  if (obj === null || typeof obj !== 'object') return obj
  const result: Record<string, unknown> = {}
  for (const [key, value] of Object.entries(obj)) {
    const camel = key.replace(/_([a-z])/g, (_, letter: string) => letter.toUpperCase())
    result[camel] = camelizeKeys(value)
  }
  return result
}

export function snakeifyKeys(obj: unknown): unknown {
  if (Array.isArray(obj)) return obj.map(snakeifyKeys)
  if (obj === null || typeof obj !== 'object') return obj
  const result: Record<string, unknown> = {}
  for (const [key, value] of Object.entries(obj)) {
    const snake = key.replace(/([A-Z])/g, '_$1').toLowerCase()
    result[snake] = snakeifyKeys(value)
  }
  return result
}

export function wrapBody(resource: string, body: unknown): string {
  return JSON.stringify({ [resource]: snakeifyKeys(body) })
}

import type {
  Service,
  Project,
  Server,
  ActivityEvent,
  GitSource,
  Environment,
  BackupDestination,
  RecoveryOverview,
  PitrRestore,
  Backup,
  BackupSchedule,
  ApiToken,
} from '@/types'

/**
 * Rails serializes `BackupDestination#id` as an integer. Every id the backup UI
 * compares it against is a string — the organization default list, the
 * service's remembered picker, `pitr.backupDestinationId` — so
 * `["2"].includes(2)` was always false: the "use by default" star never lit up
 * and the destination checkboxes never rendered as checked.
 */
export function normalizeBackupDestination(data: unknown): BackupDestination {
  const camel = camelizeKeys(data) as Record<string, unknown>
  if (camel.id != null && typeof camel.id !== 'string') camel.id = String(camel.id)
  return camel as unknown as BackupDestination
}

export function normalizeBackup(data: unknown): Backup {
  const camel = camelizeKeys(data) as Record<string, unknown>
  for (const key of ['id', 'serviceId', 'backupDestinationId']) {
    if (camel[key] != null) camel[key] = String(camel[key])
  }
  return camel as unknown as Backup
}

/**
 * Schedule ids, mount ids and destination ids arrive as integers. Destinations
 * live in `metadata.destination_ids`; lift them so the editor can compare them
 * against the (string) destination list.
 */
export function normalizeBackupSchedule(data: unknown): BackupSchedule {
  const camel = camelizeKeys(data) as Record<string, unknown>
  for (const key of ['id', 'serviceId', 'storageMountId']) {
    if (camel[key] != null) camel[key] = String(camel[key])
  }
  if (camel.storageMount && typeof camel.storageMount === 'object') {
    const mount = camel.storageMount as Record<string, unknown>
    if (mount.id != null) mount.id = String(mount.id)
  }
  const metadata = (camel.metadata ?? {}) as Record<string, unknown>
  camel.destinationIds = Array.isArray(metadata.destinationIds) ? metadata.destinationIds.map(String) : []
  return camel as unknown as BackupSchedule
}

export function normalizePitrRestore(data: unknown): PitrRestore {
  const camel = camelizeKeys(data) as Record<string, unknown>
  for (const key of ['id', 'sourceServiceId', 'restoredServiceId', 'backupId', 'projectId']) {
    if (camel[key] != null) camel[key] = String(camel[key])
  }
  return camel as unknown as PitrRestore
}

export function normalizeRecoveryOverview(data: unknown): RecoveryOverview {
  const camel = camelizeKeys(data) as Record<string, unknown>

  if (Array.isArray(camel.destinations)) {
    camel.destinations = camel.destinations.map(normalizeBackupDestination)
  }

  if (Array.isArray(camel.drills)) {
    camel.drills = camel.drills.map((drill) => {
      const normalized = drill as Record<string, unknown>
      return { ...normalized, id: String(normalized.id), backupId: String(normalized.backupId) }
    })
  }
  camel.pitrRestores = Array.isArray(camel.pitrRestores) ? camel.pitrRestores.map(normalizePitrRestore) : []
  if (camel.pitr) {
    const pitr = camel.pitr as Record<string, unknown>
    for (const key of ['id', 'serviceId', 'backupDestinationId']) {
      if (pitr[key] != null) pitr[key] = String(pitr[key])
    }
  }
  const preferences = camel.backupPreferences as Record<string, unknown> | undefined
  if (preferences) {
    const keys = [ 'organizationDestinationIds', 'serviceDestinationIds', 'defaultDestinationIds' ]
    for (const key of keys) {
      if (Array.isArray(preferences[key])) {
        preferences[key] = (preferences[key] as unknown[]).map(String)
      }
    }
  }

  return camel as unknown as RecoveryOverview
}

export function normalizeService(data: unknown): Service {
  const camel = camelizeKeys(data) as Record<string, unknown>
  // Ensure ID is a string so query keys match consistently
  if (camel.id != null && typeof camel.id !== 'string') {
    camel.id = String(camel.id)
  }
  // Every id the UI compares against another normalized id has to be a string.
  // `environmentId` was the exception: the canvas filters with
  // `service.environmentId === env.id`, and Rails sends both ids as integers, so
  // a raw numeric `environmentId` never matched a normalized environment id and
  // every canvas rendered empty even though the services existed.
  if (camel.environmentId != null && typeof camel.environmentId !== 'string') {
    camel.environmentId = String(camel.environmentId)
  }
  // Map camelized environmentVariables → envVars (our type uses envVars)
  if (camel.environmentVariables !== undefined) {
    camel.envVars = camel.environmentVariables
    delete camel.environmentVariables
  }
  // Ensure linked IDs are strings (Rails returns integers)
  if (Array.isArray(camel.linkedServiceIds)) {
    camel.linkedServiceIds = camel.linkedServiceIds.map((id) => String(id))
  }
  if (Array.isArray(camel.linkedByServiceIds)) {
    camel.linkedByServiceIds = camel.linkedByServiceIds.map((id) => String(id))
  }
  // Map camelized canvas positions back to snake_case
  if (camel.canvasX !== undefined) {
    camel.canvas_x = camel.canvasX as number | null
    delete camel.canvasX
  }
  if (camel.canvasY !== undefined) {
    camel.canvas_y = camel.canvasY as number | null
    delete camel.canvasY
  }
  const config = (camel.config || {}) as Record<string, unknown>
  delete camel.config
  const defaults = {
    proxy: { enabled: true, proxyType: 'traefik', portMappings: [] },
    dockerOptions: [],
    resourceLimits: [],
    resourceReservations: [],
    checks: { enabled: true, mode: 'enabled', wait: 5, timeout: 30, attempts: 5, waitToRetire: 60, skipList: [] },
    letsencrypt: { enabled: false, email: '', staging: false, autoRenew: true },
    git: { deployBranch: 'main', keepGitDir: false, revEnvVar: true },
    traefik: { labels: {}, properties: {} },
    envVars: [],
    domains: [],
    storageMounts: [],
    logs: [],
    backups: [],
    linkedServiceIds: [],
    processTypes: [],
    externalNetworks: [],
    locked: false,
    autoDeploy: true,
    maintenanceMode: false,
    restartPolicy: 'on-failure',
    restartMaxRetries: 10,
  }
  // Deep-merge nested objects so partial config (e.g. proxy: {}) doesn't wipe defaults
  const mergeNested = <T extends Record<string, unknown>>(def: T, val: unknown): T => {
    if (val === null || typeof val !== 'object' || Array.isArray(val)) return def
    return { ...def, ...(val as T) }
  }
  const merged = { ...defaults, ...config, ...camel } as Record<string, unknown>
  merged.proxy = mergeNested(defaults.proxy, merged.proxy)
  merged.checks = mergeNested(defaults.checks, merged.checks)
  merged.letsencrypt = mergeNested(defaults.letsencrypt, merged.letsencrypt)
  merged.git = mergeNested(defaults.git, merged.git)
  merged.traefik = mergeNested(defaults.traefik, merged.traefik)
  // Ensure array fields are always arrays (API may return null or object)
  if (!Array.isArray(merged.resourceLimits)) merged.resourceLimits = []
  if (!Array.isArray(merged.resourceReservations)) merged.resourceReservations = []
  if (!Array.isArray(merged.processTypes)) merged.processTypes = []
  if (!Array.isArray(merged.dockerOptions)) merged.dockerOptions = []
  if (!Array.isArray(merged.externalNetworks)) merged.externalNetworks = []
  return merged as unknown as Service
}

export function normalizeProject(data: unknown): Project {
  const camel = camelizeKeys(data) as Record<string, unknown>
  if (camel.id != null && typeof camel.id !== 'string') {
    camel.id = String(camel.id)
  }
  if (camel.serverId != null && typeof camel.serverId !== 'string') {
    camel.serverId = String(camel.serverId)
  }
  if (Array.isArray(camel.serviceIds)) {
    camel.serviceIds = camel.serviceIds.map((id) => String(id))
  }
  // Accept both the `environments` key and the older `environmentsForApi`
  // method-serialized name.
  const listedEnvironments = camel.environments ?? camel.environmentsForApi
  if (Array.isArray(listedEnvironments)) {
    camel.environments = (listedEnvironments as unknown[]).map(normalizeEnvironment)
  }
  delete camel.environmentsForApi
  return camel as unknown as Project
}

export function normalizeApiToken(data: unknown): ApiToken {
  const camel = camelizeKeys(data) as Record<string, unknown>
  for (const key of ['id', 'projectId', 'environmentId'] as const) {
    if (camel[key] != null && typeof camel[key] !== 'string') {
      camel[key] = String(camel[key])
    }
  }
  return camel as unknown as ApiToken
}

export function normalizeEnvironment(data: unknown): Environment {
  const camel = camelizeKeys(data) as Record<string, unknown>
  if (camel.id != null && typeof camel.id !== 'string') {
    camel.id = String(camel.id)
  }
  if (Array.isArray(camel.serviceIds)) {
    camel.serviceIds = camel.serviceIds.map((id) => String(id))
  }
  // Rails serializes the boolean column as `is_default`; be tolerant of both.
  if (camel.isDefault == null) camel.isDefault = false
  return camel as unknown as Environment
}

export function normalizeServer(data: unknown): Server {
  const camel = camelizeKeys(data) as Record<string, unknown>
  if (camel.id != null && typeof camel.id !== 'string') {
    camel.id = String(camel.id)
  }
  return camel as unknown as Server
}

export function normalizeActivityEvent(data: unknown): ActivityEvent {
  const camel = camelizeKeys(data) as Record<string, unknown>
  if (!camel.timestamp && camel.createdAt) {
    camel.timestamp = (camel.createdAt as string)
  }
  return camel as unknown as ActivityEvent
}

export function normalizeGitSource(data: unknown): GitSource {
  const camel = camelizeKeys(data) as Record<string, unknown>
  if (camel.id != null && typeof camel.id !== 'string') {
    camel.id = String(camel.id)
  }
  if (!camel.repos && (camel.metadata as Record<string, unknown>)?.repos) {
    camel.repos = (camel.metadata as Record<string, unknown>).repos
  }
  return camel as unknown as GitSource
}
