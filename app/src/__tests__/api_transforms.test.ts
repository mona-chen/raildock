import { describe, expect, it } from 'vitest'
import { normalizeEnvironment, normalizeService } from '@/lib/apiTransforms'

describe('normalizeService', () => {
  it('stringifies environmentId so it matches a normalized environment id', () => {
    const service = normalizeService({ id: 1, name: 'hello-web', environment_id: 2 })
    const environment = normalizeEnvironment({ id: 2, name: 'production' })

    expect(service.environmentId).toBe('2')
    // The project canvas filters with `service.environmentId === environment.id`,
    // so a numeric environmentId silently hides every service from its own
    // environment and shows the "lives in another environment" empty state.
    expect(service.environmentId).toBe(environment.id)
  })

  it('leaves a service without an environment untouched', () => {
    const service = normalizeService({ id: 1, name: 'hello-web' })

    expect(service.environmentId).toBeUndefined()
  })
})
