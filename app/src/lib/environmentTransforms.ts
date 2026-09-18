/**
 * Environment duplication and sync payloads.
 *
 * Kept apart from `apiTransforms` only because environments sync carries nested
 * entry lists that need their own id normalization.
 */

import type { EnvironmentSyncPlan, EnvironmentSyncResult } from '@/types'
import { camelizeKeys } from './apiTransforms'

/**
 * A sync review, with ids stringified so they compare against the ids the rest
 * of the app holds (every other normalizer does the same).
 */
export function normalizeEnvironmentSyncPlan(data: unknown): EnvironmentSyncPlan {
  const camel = camelizeKeys(data) as Record<string, unknown>
  for (const key of ['sourceEnvironmentId', 'targetEnvironmentId']) {
    if (camel[key] != null && typeof camel[key] !== 'string') camel[key] = String(camel[key])
  }
  for (const key of ['added', 'edited', 'removed']) {
    const entries = camel[key]
    if (!Array.isArray(entries)) continue
    camel[key] = entries.map((entry) => {
      const change = (entry ?? {}) as Record<string, unknown>
      if (change.serviceId != null && typeof change.serviceId !== 'string') {
        change.serviceId = String(change.serviceId)
      }
      if (!Array.isArray(change.changes)) change.changes = []
      return change
    })
  }
  const summary = (camel.summary ?? {}) as Record<string, unknown>
  if (summary.inSync == null) {
    summary.inSync = !(camel.added as unknown[] | undefined)?.length
      && !(camel.edited as unknown[] | undefined)?.length
      && !(camel.removed as unknown[] | undefined)?.length
  }
  camel.summary = summary
  return camel as unknown as EnvironmentSyncPlan
}

export function normalizeEnvironmentSyncResult(data: unknown): EnvironmentSyncResult {
  const camel = camelizeKeys(data) as Record<string, unknown>
  camel.plan = normalizeEnvironmentSyncPlan(camel.plan)
  const applied = (camel.applied ?? {}) as Record<string, unknown>
  for (const key of ['added', 'updated', 'removed']) {
    const entries = applied[key]
    applied[key] = Array.isArray(entries)
      ? entries.map((entry) => {
        const service = (entry ?? {}) as Record<string, unknown>
        if (service.id != null && typeof service.id !== 'string') service.id = String(service.id)
        return service
      })
      : []
  }
  camel.applied = applied
  return camel as unknown as EnvironmentSyncResult
}
