import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { SettingsPanel } from '@/features/service-settings/SettingsPanel'
import type { Service } from '@/types'

vi.mock('@/hooks/useServices', () => ({
  useUpdateService: () => ({ mutate: vi.fn(), isPending: false }),
  useUpdateServiceConfig: () => ({ mutate: vi.fn(), isPending: false }),
  useDestroyService: () => ({ mutate: vi.fn() }),
  useService: vi.fn(),
}))

vi.mock('@/hooks/useGitSources', () => ({
  useGitSources: () => ({ data: [], isLoading: false }),
  useGitSourceBranches: () => ({ data: [], isLoading: false }),
  useGitSourceDirectories: () => ({ data: [], isLoading: false }),
}))

vi.mock('@/hooks/useProjects', () => ({ useProject: vi.fn() }))
vi.mock('@/hooks/useServers', () => ({ useServers: vi.fn() }))
vi.mock('@/hooks/useModules', () => ({
  useNetworks: vi.fn(),
  useValidateNetwork: () => ({ mutate: vi.fn() }),
}))
vi.mock('@/hooks/useCopy', () => ({ useCopy: () => ({ copy: vi.fn(), copiedKey: null }) }))
vi.mock('@/lib/api', () => ({ api: { services: { update: vi.fn() } } }))

import { useProject } from '@/hooks/useProjects'
import { useServers } from '@/hooks/useServers'
import { useNetworks } from '@/hooks/useModules'

function renderWithClient(ui: React.ReactElement) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  return render(
    <MemoryRouter initialEntries={['/dashboard/project/proj-1']}>
      <QueryClientProvider client={queryClient}>{ui}</QueryClientProvider>
    </MemoryRouter>
  )
}

function mockService(overrides = {}): Service {
  return {
    id: 'svc-1',
    projectId: 'proj-1',
    name: 'Test Service',
    type: 'app',
    subtype: 'web',
    status: 'running',
    envVars: [],
    domains: [],
    storageMounts: [],
    logs: [],
    backups: [],
    linkedServiceIds: [],
    linkedByServiceIds: [],
    proxy: { enabled: true, proxyType: 'traefik', portMappings: [] },
    traefik: { labels: {}, properties: {} },
    dockerOptions: [],
    resourceLimits: [],
    resourceReservations: [],
    checks: { enabled: true, wait: 10, timeout: 60, skipList: [] },
    letsencrypt: { enabled: false, email: '', staging: false, autoRenew: true },
    git: { deployBranch: 'main', keepGitDir: false, revEnvVar: true },
    restartPolicy: 'on-failure',
    restartMaxRetries: 10,
    locked: false,
    processTypes: [{ name: 'web', quantity: 1, running: 1, command: 'rails server' }],
    autoDeploy: false,
    maintenanceMode: false,
    externalNetworks: [],
    ...overrides,
  } as Service
}

beforeEach(() => {
  vi.clearAllMocks()
  vi.mocked(useProject).mockReturnValue({ data: { id: 'proj-1', serverId: 'srv-1' } as any, isLoading: false } as any)
  vi.mocked(useServers).mockReturnValue({ data: [{ id: 'srv-1', name: 'Core' }] as any[], isLoading: false } as any)
  vi.mocked(useNetworks).mockReturnValue({ data: [], isLoading: false } as any)
})

const filter = () => screen.getByLabelText('Filter settings')

describe('SettingsPanel structure', () => {
  it('shares one bordered container between rows instead of a card per setting', () => {
    const { container } = renderWithClient(<SettingsPanel svc={mockService()} />)

    const group = container.querySelector('.divide-y')
    expect(group).not.toBeNull()
    expect(group!.className).toContain('rounded-lg')
    expect(group!.className).toContain('border')
    // Display Name and Container Port are rows of the same container.
    expect(group!.children).toHaveLength(2)
    expect(group!.textContent).toContain('Display Name')
    expect(group!.textContent).toContain('Container Port')
  })

  it('keeps identity settings apart from source settings', () => {
    renderWithClient(<SettingsPanel svc={mockService()} />)

    expect(screen.getByText('Display Name')).toBeInTheDocument()
    expect(screen.queryByText('Git Repository')).toBeNull()
    expect(screen.queryByText('Builder')).toBeNull()

    fireEvent.click(screen.getByText('Source'))

    expect(screen.getByText('Git Repository')).toBeInTheDocument()
    expect(screen.getByText('Builder')).toBeInTheDocument()
    expect(screen.queryByText('Display Name')).toBeNull()
  })
})

describe('SettingsPanel search', () => {
  it('matches settings by row name, not only by section label', () => {
    renderWithClient(<SettingsPanel svc={mockService()} />)

    fireEvent.change(filter(), { target: { value: 'port' } })

    // Container Port lives in General; Port Mappings lives in Routing, which is
    // not the visible pane, so finding it proves row titles are searched.
    expect(screen.getAllByText('Container Port').length).toBeGreaterThan(0)
    expect(screen.getByText('Port Mappings')).toBeInTheDocument()
    expect(screen.queryByText('Source')).toBeNull()
    expect(screen.queryByText('Danger Zone')).toBeNull()
  })

  it('finds a row inside a section whose label does not match', () => {
    renderWithClient(<SettingsPanel svc={mockService()} />)

    fireEvent.change(filter(), { target: { value: 'cron' } })

    expect(screen.getByText('Advanced')).toBeInTheDocument()
    expect(screen.getByText('Cron Jobs')).toBeInTheDocument()
    expect(screen.queryByText('General')).toBeNull()
  })

  it('still matches plain section names', () => {
    renderWithClient(<SettingsPanel svc={mockService()} />)

    fireEvent.change(filter(), { target: { value: 'routing' } })

    expect(screen.getByText('Routing')).toBeInTheDocument()
    expect(screen.queryByText('Advanced')).toBeNull()
  })

  it('reports when nothing matches', () => {
    renderWithClient(<SettingsPanel svc={mockService()} />)

    fireEvent.change(filter(), { target: { value: 'zzzz' } })

    expect(screen.getByText(/No settings match/)).toBeInTheDocument()
  })
})
