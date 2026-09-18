import { describe, expect, it } from 'vitest'
import { normalizeEnvironment, normalizeProject, normalizeService } from '@/lib/apiTransforms'

/**
 * The canvas shows only the services of the active environment:
 *
 *   allServices.filter((service) => service.environmentId === activeEnvironmentId)
 *
 * That is a strict comparison between two independently normalized values, and
 * Rails sends both ids as integers. `normalizeEnvironment` stringifies its `id`
 * while `normalizeService` did not stringify `environment_id`, so the filter
 * matched nothing and every project looked empty ("Nothing in production yet")
 * even though the project list — which counts services on the server — was
 * correct. These tests pin the contract between the two normalizers.
 */
describe('environment filtering', () => {
  it('keeps a service attached to the environment it belongs to', () => {
    const project = normalizeProject({
      id: 7,
      name: 'tween',
      environments: [
        { id: 1, name: 'production', slug: 'production', is_default: true, service_count: 2 },
        { id: 5, name: 'staging', slug: 'staging', is_default: false, service_count: 0 },
      ],
    })
    const services = [
      { id: 10, name: 'hello-web', environment_id: 1 },
      { id: 11, name: 'hello-db', environment_id: 1 },
      { id: 12, name: 'hello-staging', environment_id: 5 },
    ].map(normalizeService)

    const active = project.environments?.find((environment) => environment.isDefault)?.id
    const visible = services.filter((service) => service.environmentId === active)

    expect(visible.map((service) => service.name)).toEqual(['hello-web', 'hello-db'])
  })

  it('normalizes both sides of the comparison to the same type', () => {
    const service = normalizeService({ id: 10, environment_id: 3 })
    const environment = normalizeEnvironment({ id: 3, name: 'production' })

    expect(service.environmentId).toBe(environment.id)
    expect(service.id).toBe('10')
  })

  it('still filters correctly for a non-default environment', () => {
    const services = [
      { id: 10, name: 'hello-web', environment_id: 1 },
      { id: 12, name: 'hello-staging', environment_id: 5 },
    ].map(normalizeService)

    const visible = services.filter((service) => service.environmentId === normalizeEnvironment({ id: 5 }).id)

    expect(visible.map((service) => service.name)).toEqual(['hello-staging'])
  })
})
