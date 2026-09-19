import { describe, it, expect, vi, afterEach } from 'vitest'
import { api, organizationsApi } from '@/lib/api'

function stubJson(body: unknown) {
  vi.stubGlobal(
    'fetch',
    vi.fn().mockResolvedValue({ ok: true, status: 200, json: () => Promise.resolve(body) }),
  )
}

/**
 * Rails serializes `id` as an integer, while every stored destination list (the
 * organization default, the service's remembered picker, `pitr.backupDestinationId`)
 * holds strings. `["2"].includes(2)` is false, so before this the "use by
 * default" star never lit up and the destination checkboxes never rendered as
 * checked — clicking them appeared to do nothing.
 */
describe('backup destination id normalization', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('stringifies ids from the organization destination list', async () => {
    stubJson([{ id: 2, name: 'Tween S3 Backup', bucket: 'tween-backups' }])

    const [destination] = await organizationsApi.backupDestinations.list('1')

    expect(destination.id).toBe('2')
    expect(destination.name).toBe('Tween S3 Backup')
  })

  it('stringifies ids and preference lists in the recovery overview', async () => {
    stubJson({
      destinations: [{ id: 2, name: 'Tween S3 Backup' }],
      pitr: null,
      drills: [],
      backup_preferences: {
        organization_destination_ids: [ 2 ],
        service_destination_ids: null,
        default_destination_ids: [ 2 ],
      },
    })

    const overview = await api.services.recovery('4')

    expect(overview.destinations[0].id).toBe('2')
    expect(overview.backupPreferences.organizationDestinationIds).toEqual([ '2' ])
    expect(overview.backupPreferences.defaultDestinationIds).toEqual([ '2' ])
    expect(overview.backupPreferences.serviceDestinationIds).toBeNull()
    // The comparison the pickers actually make.
    expect(overview.backupPreferences.defaultDestinationIds).toContain(overview.destinations[0].id)
  })

  it('always returns the organization default list as strings', async () => {
    stubJson({ default_destination_ids: [ 2 ] })

    expect(await organizationsApi.backupDestinations.defaults('1')).toEqual([ '2' ])
  })
})
