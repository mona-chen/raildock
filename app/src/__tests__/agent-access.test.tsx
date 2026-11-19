import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import AgentAccessTab from '@/features/settings/AgentAccessTab'
import type { ApiToken, CreatedApiToken } from '@/types'

const { createMutate, revokeMutate } = vi.hoisted(() => ({
  createMutate: vi.fn(),
  revokeMutate: vi.fn(),
}))

const tokensState: { data: ApiToken[]; isLoading: boolean; isError: boolean; error: Error | null } = {
  data: [],
  isLoading: false,
  isError: false,
  error: null,
}

vi.mock('@/hooks/useApiTokens', () => ({
  useApiTokens: () => tokensState,
  useCreateApiToken: () => ({ mutate: createMutate, isPending: false }),
  useRevokeApiToken: () => ({ mutate: revokeMutate, isPending: false }),
}))

vi.mock('@/hooks/useProjects', () => ({
  useProjects: () => ({
    data: [
      {
        id: 'proj-1',
        name: 'Demo',
        environments: [
          { id: 'env-1', name: 'production', slug: 'production', isDefault: true },
        ],
      },
    ],
  }),
}))

vi.mock('@/hooks/useCopy', () => ({
  useCopy: () => ({ copiedKey: null, copy: vi.fn() }),
}))

function token(overrides: Partial<ApiToken> = {}): ApiToken {
  return {
    id: 'tok-1',
    name: 'CI agent',
    prefix: 'abc12345',
    scopes: ['read'],
    projectId: null,
    environmentId: null,
    createdAt: '2026-11-19T00:00:00Z',
    ...overrides,
  }
}

function renderTab() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  return render(
    <QueryClientProvider client={queryClient}>
      <AgentAccessTab />
    </QueryClientProvider>,
  )
}

describe('AgentAccessTab', () => {
  beforeEach(() => {
    createMutate.mockReset()
    revokeMutate.mockReset()
    tokensState.data = []
    tokensState.isLoading = false
    tokensState.isError = false
    tokensState.error = null
  })

  it('shows the empty state', () => {
    renderTab()

    expect(screen.getByText('No tokens yet')).toBeInTheDocument()
  })

  it('creates a token and reveals the secret once', async () => {
    const created: CreatedApiToken = {
      token: token({ scopes: ['read', 'deploy'] }),
      secret: 'rd_secret_value',
    }
    createMutate.mockImplementation((_input, options) => options?.onSuccess?.(created))

    renderTab()

    fireEvent.click(screen.getByRole('button', { name: /create token/i }))

    const dialog = screen.getByRole('dialog')
    fireEvent.change(within(dialog).getByLabelText('Name'), { target: { value: 'Claude Code' } })
    fireEvent.click(within(dialog).getByRole('checkbox', { name: 'Deploy' }))
    fireEvent.click(within(dialog).getByRole('button', { name: /^create token$/i }))

    await waitFor(() => expect(createMutate).toHaveBeenCalledTimes(1))
    expect(createMutate.mock.calls[0][0]).toMatchObject({
      name: 'Claude Code',
      scopes: ['read', 'deploy'],
      projectId: null,
      environmentId: null,
    })

    expect(await screen.findByText('rd_secret_value')).toBeInTheDocument()
    expect(screen.getByText(/only time the secret is shown/i)).toBeInTheDocument()
  })

  it('renders scope, binding and prefix without the secret', () => {
    tokensState.data = [token({ projectId: 'proj-1', environmentId: 'env-1' })]

    renderTab()

    expect(screen.getByText('CI agent')).toBeInTheDocument()
    expect(screen.getByText('rd_abc12345…')).toBeInTheDocument()
    expect(screen.getByText(/Demo · production/)).toBeInTheDocument()
  })

  it('revokes a token after confirmation', async () => {
    tokensState.data = [token()]

    renderTab()

    fireEvent.click(screen.getByRole('button', { name: 'Revoke' }))
    fireEvent.click(await screen.findByRole('button', { name: 'Revoke token' }))

    await waitFor(() => expect(revokeMutate).toHaveBeenCalledWith('tok-1', expect.anything()))
  })
})
