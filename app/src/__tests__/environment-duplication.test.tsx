import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import DuplicateEnvironmentDialog from '@/features/environments/DuplicateEnvironmentDialog'
import SyncEnvironmentDialog from '@/features/environments/SyncEnvironmentDialog'
import { duplicateHighlights, suggestEnvironmentName } from '@/features/environments/duplicateEnvironment'
import type { Environment, EnvironmentDuplicateSummary, EnvironmentSyncPlan } from '@/types'

const mocks = vi.hoisted(() => ({
  duplicateMutate: vi.fn(),
  syncMutate: vi.fn(),
  plan: { current: null as EnvironmentSyncPlan | null },
}))

vi.mock('@/hooks/useEnvironments', () => ({
  useDuplicateEnvironment: () => ({ mutate: mocks.duplicateMutate, isPending: false }),
  useSyncEnvironment: () => ({ mutate: mocks.syncMutate, isPending: false }),
  useEnvironmentSyncPlan: () => ({
    data: mocks.plan.current,
    isLoading: false,
    isError: false,
    refetch: vi.fn(),
  }),
}))

function environment(overrides: Partial<Environment> = {}): Environment {
  return { id: '1', name: 'production', slug: 'production', isDefault: true, serviceCount: 3, ...overrides }
}

function summary(overrides: Partial<EnvironmentDuplicateSummary> = {}): EnvironmentDuplicateSummary {
  return {
    services: 3,
    variables: 7,
    volumes: 1,
    bindMounts: 0,
    schedules: 2,
    links: 1,
    processTypes: 0,
    temporaryDomains: 1,
    domainsSkipped: 0,
    warnings: [],
    ...overrides,
  }
}

function renderWithClient(ui: React.ReactElement) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  return render(
    <MemoryRouter>
      <QueryClientProvider client={queryClient}>{ui}</QueryClientProvider>
    </MemoryRouter>,
  )
}

describe('suggestEnvironmentName', () => {
  it('offers the usual next environment first', () => {
    expect(suggestEnvironmentName('production', ['production'])).toBe('staging')
  })

  it('skips names the project already uses', () => {
    expect(suggestEnvironmentName('production', ['production', 'staging'])).toBe('development')
  })

  it('falls back to a copy name derived from the source', () => {
    expect(suggestEnvironmentName('production', ['production', 'staging', 'development', 'test'])).toBe(
      'production-copy',
    )
  })

  it('keeps counting until the name is free', () => {
    const taken = ['production', 'staging', 'development', 'test', 'production-copy', 'production-copy-2']
    expect(suggestEnvironmentName('production', taken)).toBe('production-copy-3')
  })
})

describe('duplicateHighlights', () => {
  it('reads as short phrases and drops empty counts', () => {
    expect(duplicateHighlights(summary())).toEqual([
      '3 services',
      '7 variables',
      '1 new volume',
      '2 backup schedules',
      '1 link',
      '1 temporary domain',
    ])
  })

  it('says nothing when the source environment is empty', () => {
    expect(duplicateHighlights(summary({ services: 0, variables: 0, volumes: 0, schedules: 0, links: 0, temporaryDomains: 0 }))).toEqual([])
  })
})

describe('DuplicateEnvironmentDialog', () => {
  beforeEach(() => {
    mocks.duplicateMutate.mockReset()
    mocks.syncMutate.mockReset()
  })

  it('pre-fills a name and duplicates the environment it was opened on', () => {
    renderWithClient(
      <DuplicateEnvironmentDialog
        projectId="p1"
        source={environment()}
        environments={[environment()]}
        open
        onOpenChange={vi.fn()}
      />,
    )

    const input = screen.getByLabelText('New environment name') as HTMLInputElement
    expect(input.value).toBe('staging')
    expect(screen.getByRole('heading', { name: 'Duplicate production' })).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Duplicate' }))

    expect(mocks.duplicateMutate).toHaveBeenCalledWith(
      { projectId: 'p1', id: '1', data: { name: 'staging' } },
      expect.objectContaining({ onSuccess: expect.any(Function) }),
    )
  })

  it('ends on a review of what was staged, not on a deploy', () => {
    mocks.duplicateMutate.mockImplementation((_variables, options) => {
      options.onSuccess({ environment: environment({ id: '5', name: 'staging', isDefault: false }), summary: summary() })
    })

    renderWithClient(
      <DuplicateEnvironmentDialog
        projectId="p1"
        source={environment()}
        environments={[environment()]}
        open
        onOpenChange={vi.fn()}
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: 'Duplicate' }))

    expect(screen.getByRole('heading', { name: 'staging created' })).toBeInTheDocument()
    expect(screen.getByText(/3 services · 7 variables · 1 new volume/)).toBeInTheDocument()
    expect(screen.getByText(/nothing has been deployed yet/i)).toBeInTheDocument()
  })

  it('surfaces what deliberately did not travel', () => {
    mocks.duplicateMutate.mockImplementation((_variables, options) => {
      options.onSuccess({
        environment: environment({ id: '5', name: 'staging', isDefault: false }),
        summary: summary({ domainsSkipped: 2, warnings: ['2 custom domains were not copied — two services cannot answer on the same hostname.'] }),
      })
    })

    renderWithClient(
      <DuplicateEnvironmentDialog
        projectId="p1"
        source={environment()}
        environments={[environment()]}
        open
        onOpenChange={vi.fn()}
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: 'Duplicate' }))

    expect(screen.getByText(/2 custom domains were not copied/)).toBeInTheDocument()
  })
})

describe('SyncEnvironmentDialog', () => {
  const production = environment()
  const staging = environment({ id: '2', name: 'staging', slug: 'staging', isDefault: false, serviceCount: 0 })

  function plan(overrides: Partial<EnvironmentSyncPlan> = {}): EnvironmentSyncPlan {
    return {
      sourceEnvironmentId: '1',
      sourceEnvironmentName: 'production',
      targetEnvironmentId: '2',
      targetEnvironmentName: 'staging',
      added: [],
      edited: [],
      removed: [],
      summary: { added: 0, edited: 0, removed: 0, inSync: true },
      ...overrides,
    }
  }

  beforeEach(() => {
    mocks.plan.current = null
    mocks.syncMutate.mockReset()
  })

  it('shows the staged diff before anything is applied', () => {
    mocks.plan.current = plan({
      added: [{ name: 'web', serviceId: '10', changes: ['new service'] }],
      edited: [{ name: 'db', serviceId: '11', changes: ['branch', 'environment variable DATABASE_URL'] }],
      removed: [{ name: 'staging-only', serviceId: '12', changes: ['not in production'] }],
      summary: { added: 1, edited: 1, removed: 1, inSync: false },
    })

    renderWithClient(
      <SyncEnvironmentDialog
        projectId="p1"
        target={staging}
        environments={[production, staging]}
        open
        onOpenChange={vi.fn()}
      />,
    )

    expect(screen.getByText('Added')).toBeInTheDocument()
    expect(screen.getByText('Edited')).toBeInTheDocument()
    expect(screen.getByText('Removed')).toBeInTheDocument()
    expect(screen.getByText(/branch, environment variable DATABASE_URL/)).toBeInTheDocument()
    expect(screen.getByText(/remove these individually from the canvas/)).toBeInTheDocument()
    expect(mocks.syncMutate).not.toHaveBeenCalled()
  })

  it('applies against the environment it was opened on', () => {
    mocks.plan.current = plan({
      added: [{ name: 'web', serviceId: '10', changes: ['new service'] }],
      summary: { added: 1, edited: 0, removed: 0, inSync: false },
    })

    renderWithClient(
      <SyncEnvironmentDialog
        projectId="p1"
        target={staging}
        environments={[production, staging]}
        open
        onOpenChange={vi.fn()}
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: 'Apply to staging' }))

    expect(mocks.syncMutate).toHaveBeenCalledWith({ projectId: 'p1', id: '2', sourceId: '1' })
  })

  it('disables apply when the environments already match', () => {
    mocks.plan.current = plan()

    renderWithClient(
      <SyncEnvironmentDialog
        projectId="p1"
        target={staging}
        environments={[production, staging]}
        open
        onOpenChange={vi.fn()}
      />,
    )

    expect(screen.getByText(/Already in sync with production/)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Apply to staging' })).toBeDisabled()
  })

  it('says so when there is nothing to sync from', () => {
    renderWithClient(
      <SyncEnvironmentDialog
        projectId="p1"
        target={production}
        environments={[production]}
        open
        onOpenChange={vi.fn()}
      />,
    )

    expect(screen.getByText(/no other environment to sync from yet/)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Apply to production' })).toBeDisabled()
  })
})
