import { afterEach, expect, it, vi } from 'vitest'
import { servicesApi, serversApi } from '@/lib/api'

afterEach(() => vi.unstubAllGlobals())

it('reads historical resource fields after the shared API camelizes response keys', async () => {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(JSON.stringify({ collection_enabled: false, retention_days: 7, samples: [{ at: '2026-11-15T01:00:00Z', cpu: 0.05, cpu_cores: 2, memory: 40, memory_used: 1024, memory_limit: 2048, network_in: 100, network_out: 200, block_read: 300, block_write: 400 }] }))))
  const data = await servicesApi.metricsHistory('1', 1)
  expect(data.collectionEnabled).toBe(false)
  expect(data.samples[0]).toMatchObject({ cpuCores: 2, memoryUsed: 1024, networkIn: 100, blockRead: 300 })
})

it('reads host timestamps and network counters through the real API boundary', async () => {
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(JSON.stringify({ available: true, sampled_at: '2026-11-15T01:00:00Z', uptime_seconds: 86400, network_rx: 10, network_tx: 20 }))))
  expect(await serversApi.metrics('1')).toMatchObject({ sampledAt: '2026-11-15T01:00:00Z', uptimeSeconds: 86400, networkRx: 10, networkTx: 20 })
})

it('sends notification settings as a JSON object with snake case keys', async () => {
  const fetch = vi.fn().mockResolvedValue(new Response('{}'))
  vi.stubGlobal('fetch', fetch)
  const { observabilityApi } = await import('@/lib/api')
  await observabilityApi.saveNotifications({enabled:true, windowMinutes:3} as never)
  expect(JSON.parse(fetch.mock.calls[0][1].body)).toEqual({settings:{enabled:true,window_minutes:3}})
})
