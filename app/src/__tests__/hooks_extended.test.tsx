import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
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
    services: {
      link: vi.fn(),
      unlink: vi.fn(),
      rollback: vi.fn(),
      backup: vi.fn(),
      restore: vi.fn(),
      containerStatus: vi.fn(),
    },
    templates: {
      list: vi.fn(),
      deploy: vi.fn(),
    },
  },
}))

import { toast } from 'sonner'
import { api } from '@/lib/api'
import {
  useLinkService,
  useUnlinkService,
  useRollbackService,
  useBackupService,
  useRestoreService,
  useContainerStatus,
} from '@/hooks/useServices'
import { useTemplates, useDeployTemplate } from '@/hooks/useModules'

function createWrapper() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  })
  return function Wrapper({ children }: { children: ReactNode }) {
    return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  }
}

describe('useLinkService', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(api.services.link).mockResolvedValue({
      success: true,
      linked_service_ids: ['svc-2'],
    })
  })

  it('calls api.services.link and shows toast on success', async () => {
    const { result } = renderHook(() => useLinkService(), { wrapper: createWrapper() })
    result.current.mutate({ id: 'svc-1', targetId: 'svc-2' })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(api.services.link).toHaveBeenCalledWith('svc-1', 'svc-2')
    expect(toast.success).toHaveBeenCalledWith('Service linked')
  })
})

describe('useUnlinkService', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(api.services.unlink).mockResolvedValue({
      success: true,
      linked_service_ids: [],
    })
  })

  it('calls api.services.unlink and shows toast on success', async () => {
    const { result } = renderHook(() => useUnlinkService(), { wrapper: createWrapper() })
    result.current.mutate({ id: 'svc-1', targetId: 'svc-2' })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(api.services.unlink).toHaveBeenCalledWith('svc-1', 'svc-2')
    expect(toast.success).toHaveBeenCalledWith('Service unlinked')
  })
})

describe('useRollbackService', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(api.services.rollback).mockResolvedValue(undefined)
  })

  it('calls api.services.rollback and shows toast on success', async () => {
    const { result } = renderHook(() => useRollbackService(), { wrapper: createWrapper() })
    result.current.mutate({ id: 'svc-1', deploymentId: 'dep-1' })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(api.services.rollback).toHaveBeenCalledWith('svc-1', 'dep-1')
    expect(toast.success).toHaveBeenCalledWith('Rollback initiated')
  })
})

describe('useBackupService', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(api.services.backup).mockResolvedValue({ success: true })
  })

  it('calls api.services.backup and shows toast on success', async () => {
    const { result } = renderHook(() => useBackupService(), { wrapper: createWrapper() })
    result.current.mutate('svc-1')
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(api.services.backup).toHaveBeenCalledWith('svc-1')
    expect(toast.success).toHaveBeenCalledWith('Backup created')
  })
})

describe('useRestoreService', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(api.services.restore).mockResolvedValue({ success: true })
  })

  it('calls api.services.restore and shows toast on success', async () => {
    const { result } = renderHook(() => useRestoreService(), { wrapper: createWrapper() })
    result.current.mutate({ id: 'svc-1' })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(api.services.restore).toHaveBeenCalledWith('svc-1', undefined)
    expect(toast.success).toHaveBeenCalledWith('Restore initiated')
  })
})

describe('useContainerStatus', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(api.services.containerStatus).mockResolvedValue({ status: 'running' })
  })

  it('calls api.services.containerStatus and returns data', async () => {
    const { result } = renderHook(() => useContainerStatus('svc-1'), {
      wrapper: createWrapper(),
    })
    await waitFor(() => expect(result.current.data).toEqual({ status: 'running' }))
    expect(api.services.containerStatus).toHaveBeenCalledWith('svc-1')
  })

  it('has a refetchInterval of 10000', async () => {
    const queryClient = new QueryClient({
      defaultOptions: { queries: { retry: false } },
    })
    function Wrapper({ children }: { children: ReactNode }) {
      return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    }

    renderHook(() => useContainerStatus('svc-1'), { wrapper: Wrapper })

    const query = queryClient.getQueryCache().find({
      queryKey: ['services', 'svc-1', 'container-status'],
    })
    expect((query?.options as any).refetchInterval).toBe(10000)
  })
})

describe('useTemplates', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(api.templates.list).mockResolvedValue([
      {
        id: 't1',
        name: 'Rails',
        category: 'web',
        description: 'Rails app',
        services: [],
      },
    ])
  })

  it('calls api.templates.list and returns templates', async () => {
    const { result } = renderHook(() => useTemplates(), { wrapper: createWrapper() })
    await waitFor(() => expect(result.current.data).toHaveLength(1))
    expect(result.current.data?.[0].name).toBe('Rails')
    expect(api.templates.list).toHaveBeenCalled()
  })
})

describe('useDeployTemplate', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(api.templates.deploy).mockResolvedValue({
      created: [{ id: 'svc-new', name: 'web', type: 'app' as const, subtype: 'web' }],
    })
  })

  it('calls api.templates.deploy and shows toast on success', async () => {
    const { result } = renderHook(() => useDeployTemplate(), { wrapper: createWrapper() })
    result.current.mutate({ templateId: 't1', projectId: 'proj-1' })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(api.templates.deploy).toHaveBeenCalledWith('t1', 'proj-1')
    expect(toast.success).toHaveBeenCalledWith('Template deployed')
  })
})
