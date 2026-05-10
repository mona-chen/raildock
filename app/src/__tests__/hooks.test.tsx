import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, waitFor, act } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { type ReactNode } from 'react'

vi.mock('sonner', () => ({
  toast: {
    success: vi.fn(),
    error: vi.fn(),
  },
}))

vi.mock('@/lib/api', () => ({
  api: {
    projects: {
      list: vi.fn(),
      get: vi.fn(),
      create: vi.fn(),
    },
    services: {
      list: vi.fn(),
      get: vi.fn(),
    },
    servers: {
      list: vi.fn(),
    },
  },
}))

import { api } from '@/lib/api'
import { useProjects, useProject, useCreateProject } from '@/hooks/useProjects'
import { useServices, useService } from '@/hooks/useServices'
import { useServers } from '@/hooks/useServers'
import { useCanvasStore } from '@/stores/useCanvasStore'

function createWrapper() {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: { retry: false },
    },
  })
  return function Wrapper({ children }: { children: ReactNode }) {
    return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  }
}

describe('React Query Hooks', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('useProjects returns projects', async () => {
    vi.mocked(api.projects.list).mockResolvedValue([
      { id: '1', name: 'Project A', environment: 'production', description: '', serviceIds: [], sharedVars: [], createdAt: '' } as any,
      { id: '2', name: 'Project B', environment: 'staging', description: '', serviceIds: [], sharedVars: [], createdAt: '' } as any,
    ])

    const { result } = renderHook(() => useProjects(), { wrapper: createWrapper() })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(result.current.data).toHaveLength(2)
    expect(result.current.data?.[0].name).toBe('Project A')
  })

  it('useProject returns a single project', async () => {
    vi.mocked(api.projects.get).mockResolvedValue({
      id: '1',
      name: 'Project A',
      environment: 'production',
      description: '',
      serviceIds: [],
      sharedVars: [],
      createdAt: '',
    } as any)

    const { result } = renderHook(() => useProject('1'), { wrapper: createWrapper() })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(result.current.data?.name).toBe('Project A')
  })

  it('useServices returns services for a project', async () => {
    vi.mocked(api.services.list).mockResolvedValue([
      { id: 's1', name: 'api', type: 'app', subtype: 'web', status: 'running', projectId: '1', linkedServiceIds: [], envVars: [], domains: [], storageMounts: [], logs: [], backups: [], nginx: {} as any, proxy: {} as any, dockerOptions: [], resourceLimits: [], resourceReservations: [], checks: {} as any, letsencrypt: {} as any, git: {} as any, restartPolicy: 'on-failure', restartMaxRetries: 10, locked: false } as any,
    ])

    const { result } = renderHook(() => useServices('1'), { wrapper: createWrapper() })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(result.current.data?.length).toBeGreaterThan(0)
    expect(result.current.data?.[0].name).toBe('api')
  })

  it('useService returns a single service', async () => {
    vi.mocked(api.services.get).mockResolvedValue({
      id: 's1',
      name: 'api',
      type: 'app',
      subtype: 'web',
      status: 'running',
      projectId: '1',
      linkedServiceIds: [],
      envVars: [],
      domains: [],
      storageMounts: [],
      logs: [],
      backups: [],
      nginx: {} as any,
      proxy: {} as any,
      dockerOptions: [],
      resourceLimits: [],
      resourceReservations: [],
      checks: {} as any,
      letsencrypt: {} as any,
      git: {} as any,
      restartPolicy: 'on-failure',
      restartMaxRetries: 10,
      locked: false,
    } as any)

    const { result } = renderHook(() => useService('s1'), { wrapper: createWrapper() })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(result.current.data?.name).toBe('api')
  })

  it('useServers returns servers', async () => {
    vi.mocked(api.servers.list).mockResolvedValue([
      { id: 'srv-1', name: 'Production', host: '1.2.3.4', status: 'connected', dokkuVersion: '', dockerVersion: '', os: '', uptime: '', diskUsage: { used: 0, total: 0 }, memoryUsage: { used: 0, total: 0 }, projectIds: [], defaultProxy: 'traefik' } as any,
    ])

    const { result } = renderHook(() => useServers(), { wrapper: createWrapper() })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(result.current.data).toHaveLength(1)
    expect(result.current.data?.[0].name).toBe('Production')
  })
})

describe('Zustand Stores', () => {
  it('useCanvasStore manages zoom', () => {
    const { result } = renderHook(() => useCanvasStore())
    expect(result.current.zoom).toBe(1)

    act(() => result.current.setZoom(1.5))
    expect(useCanvasStore.getState().zoom).toBe(1.5)

    act(() => result.current.setZoom(3))
    expect(useCanvasStore.getState().zoom).toBe(2)

    act(() => result.current.setZoom(0.1))
    expect(useCanvasStore.getState().zoom).toBe(0.3)
  })

  it('useCanvasStore manages active service', () => {
    const { result } = renderHook(() => useCanvasStore())
    expect(result.current.activeServiceId).toBeNull()

    act(() => result.current.setActiveService('svc-1'))
    expect(useCanvasStore.getState().activeServiceId).toBe('svc-1')

    act(() => result.current.setActiveService(null))
    expect(useCanvasStore.getState().activeServiceId).toBeNull()
  })

  it('useCanvasStore manages filter', () => {
    const { result } = renderHook(() => useCanvasStore())
    expect(result.current.filter).toBe('all')

    act(() => result.current.setFilter('app'))
    expect(useCanvasStore.getState().filter).toBe('app')
  })

  it('useCanvasStore resetView works', () => {
    const store = useCanvasStore.getState()
    act(() => {
      store.setZoom(1.5)
      store.setPan({ x: 100, y: 200 })
      store.resetView()
    })

    expect(useCanvasStore.getState().zoom).toBe(1)
    expect(useCanvasStore.getState().pan).toEqual({ x: 0, y: 0 })
  })
})
