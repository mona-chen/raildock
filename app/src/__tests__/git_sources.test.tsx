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
    adminSettings: {
      finishGitHubAppSetup: vi.fn(),
    },
  },
}))

import { api } from '@/lib/api'
import { useFinishGitHubAppSetup } from '@/hooks/useGitSources'
import { useAuthStore } from '@/stores/useAuthStore'

function createWrapper() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  })
  return function Wrapper({ children }: { children: ReactNode }) {
    return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  }
}

describe('useFinishGitHubAppSetup', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    useAuthStore.setState({ currentOrganizationId: 'org-1' })
  })

  it('starts GitHub authorization with the selected RailDock workspace', async () => {
    vi.mocked(api.adminSettings.finishGitHubAppSetup).mockResolvedValue({
      authorizationUrl: 'https://github.com/login/oauth/authorize?state=signed',
    })

    const { result } = renderHook(() => useFinishGitHubAppSetup(), {
      wrapper: createWrapper(),
    })

    result.current.mutate('installation-1')

    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(api.adminSettings.finishGitHubAppSetup).toHaveBeenCalledWith(
      'installation-1',
      'org-1',
    )
  })
})
