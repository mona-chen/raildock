import { describe, it, expect, vi, afterEach } from 'vitest'
import { api } from '@/lib/api'

function stubFetch(body: unknown = {}) {
  const fetch = vi.fn().mockResolvedValue({ ok: true, status: 200, json: () => Promise.resolve(body) })
  vi.stubGlobal('fetch', fetch)
  return fetch
}

/**
 * The controller only permits snake_case keys. These payloads used to be sent
 * camelCase, so `retentionCount`/`destinationIds`/`storageMountId` were dropped:
 * every schedule created from the dashboard failed validation and an edited
 * retention window silently did nothing.
 */
describe('backup schedule payloads', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('creates a database schedule with snake_case keys', async () => {
    const fetch = stubFetch()
    await api.services.createBackupSchedule('7', { frequency: 'weekly', retentionCount: 4, destinationIds: ['2'] })

    expect(JSON.parse(fetch.mock.calls[0][1].body)).toEqual({
      backup_schedule: { frequency: 'weekly', retention_count: 4, destination_ids: ['2'], backup_kind: 'database' },
    })
  })

  it('creates a volume schedule with its mount', async () => {
    const fetch = stubFetch()
    await api.services.createSnapshotSchedule('7', { frequency: 'daily', retentionCount: 7, storageMountId: '3' })

    expect(JSON.parse(fetch.mock.calls[0][1].body)).toEqual({
      backup_schedule: { frequency: 'daily', retention_count: 7, storage_mount_id: '3', backup_kind: 'volume' },
    })
  })

  it('only sends the fields being changed, so a pause cannot drop destinations', async () => {
    const fetch = stubFetch({ id: 1, metadata: { destination_ids: [2] } })
    await api.services.updateBackupSchedule('7', '1', { enabled: false })

    expect(JSON.parse(fetch.mock.calls[0][1].body)).toEqual({ backup_schedule: { enabled: false } })
  })

  it('normalizes schedule ids and lifts destination ids out of metadata', async () => {
    stubFetch([{ id: 5, storage_mount_id: 3, storage_mount: { id: 3, container_path: '/data' }, metadata: { destination_ids: [2] } }])
    const [schedule] = await api.services.backupSchedules('7')

    expect(schedule.id).toBe('5')
    expect(schedule.storageMountId).toBe('3')
    expect(schedule.storageMount?.id).toBe('3')
    expect(schedule.destinationIds).toEqual(['2'])
  })

  it('lets a manual snapshot follow the service default when no destinations are given', async () => {
    const fetch = stubFetch()
    await api.services.snapshotVolume('7', '3')

    expect(JSON.parse(fetch.mock.calls[0][1].body)).toEqual({})
  })
})
