import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, waitFor, act } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { type ReactNode } from 'react'
import { useWebSocketLogs } from '@/hooks/useWebSocketLogs'
import { useWebSocketDeployments } from '@/hooks/useWebSocketDeployments'

const mockUnsubscribe = vi.fn()

let logHandlers: {
  received?: (data: { line?: string; message?: string }) => void
  connected?: () => void
  disconnected?: () => void
} = {}

let deploymentHandlers: {
  received?: (data: {
    deployment_id: string
    status: 'pending' | 'deploying' | 'succeeded' | 'failed'
    message: string
  }) => void
  connected?: () => void
  disconnected?: () => void
} = {}

const mockCable = {
  subscriptions: {
    create: vi.fn((channel, handlers) => {
      if (channel.channel === 'LogsChannel') {
        logHandlers = handlers
        return { unsubscribe: mockUnsubscribe }
      }
      if (channel.channel === 'DeploymentsChannel') {
        deploymentHandlers = handlers
        return { unsubscribe: vi.fn() }
      }
      return { unsubscribe: vi.fn() }
    }),
  },
}

vi.mock('@/lib/cable', () => ({
  getCable: () => mockCable,
  isCableAvailable: () => true,
}))

function createWrapper() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  })
  return function Wrapper({ children }: { children: ReactNode }) {
    return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  }
}

describe('useWebSocketLogs', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    logHandlers = {}
  })

  it('appends lines on received, tracks connected state, and clears', async () => {
    const { result } = renderHook(() => useWebSocketLogs('svc-1'), {
      wrapper: createWrapper(),
    })

    act(() => logHandlers.connected?.())
    await waitFor(() => expect(result.current.isConnected).toBe(true))

    act(() => logHandlers.received?.({ line: 'Build started' }))
    await waitFor(() => expect(result.current.lines).toHaveLength(1))
    expect(result.current.lines[0].message).toBe('Build started')
    expect(result.current.lines[0].process_type).toBe('app')

    act(() => logHandlers.received?.({ message: 'Build complete' }))
    await waitFor(() => expect(result.current.lines).toHaveLength(2))
    expect(result.current.lines[1].message).toBe('Build complete')

    act(() => result.current.clear())
    await waitFor(() => expect(result.current.lines).toHaveLength(0))
  })

  it('ignores empty messages', async () => {
    const { result } = renderHook(() => useWebSocketLogs('svc-1'), {
      wrapper: createWrapper(),
    })

    act(() => logHandlers.received?.({ line: '' }))
    await waitFor(() => expect(result.current.lines).toHaveLength(0))
  })

  it('unsubscribes on unmount', () => {
    const { unmount } = renderHook(() => useWebSocketLogs('svc-1'), {
      wrapper: createWrapper(),
    })
    unmount()
    expect(mockUnsubscribe).toHaveBeenCalled()
  })
})

describe('useWebSocketDeployments', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    deploymentHandlers = {}
  })

  it('tracks lastUpdate and invalidates queries on receive', async () => {
    const queryClient = new QueryClient({
      defaultOptions: { queries: { retry: false } },
    })
    function Wrapper({ children }: { children: ReactNode }) {
      return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    }

    const invalidateSpy = vi.spyOn(queryClient, 'invalidateQueries')

    const { result } = renderHook(() => useWebSocketDeployments('svc-1'), {
      wrapper: Wrapper,
    })

    act(() => deploymentHandlers.connected?.())
    await waitFor(() => expect(result.current.isConnected).toBe(true))

    act(() =>
      deploymentHandlers.received?.({
        deployment_id: 'dep-1',
        status: 'succeeded',
        message: 'Deployed successfully',
      })
    )

    await waitFor(() => expect(result.current.lastUpdate).not.toBeNull())
    expect(result.current.lastUpdate?.deployment_id).toBe('dep-1')
    expect(result.current.lastUpdate?.status).toBe('succeeded')

    expect(invalidateSpy).toHaveBeenCalledWith({
      queryKey: ['services', 'svc-1', 'deployments'],
    })
    expect(invalidateSpy).toHaveBeenCalledWith({
      queryKey: ['services', 'svc-1'],
    })

    invalidateSpy.mockRestore()
  })
})
