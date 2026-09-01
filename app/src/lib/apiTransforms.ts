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

import type { Service, Project, Server, ActivityEvent, GitSource } from '@/types'

export function normalizeService(data: unknown): Service {
  const camel = camelizeKeys(data) as Record<string, unknown>
  // Ensure ID is a string so query keys match consistently
  if (camel.id != null && typeof camel.id !== 'string') {
    camel.id = String(camel.id)
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
  return camel as unknown as Project
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
