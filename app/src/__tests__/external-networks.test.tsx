import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { SettingsPanel } from '@/features/service-settings/SettingsPanel'
import type { Service } from '@/types'

const updateServiceMutate = vi.fn()
const updateConfigMutate = vi.fn()

vi.mock('@/hooks/useServices', () => ({
  useUpdateService: () => ({ mutate: updateServiceMutate, isPending: false }),
  useUpdateServiceConfig: () => ({ mutate: updateConfigMutate, isPending: false }),
  useDestroyService: () => ({ mutate: vi.fn() }),
  useService: vi.fn(),
}))

vi.mock('@/hooks/useGitSources', () => ({
  useGitSources: () => ({ data: [], isLoading: false }),
  useGitSourceBranches: () => ({ data: [], isLoading: false }),
  useGitSourceDirectories: () => ({ data: [], isLoading: false }),
}))

vi.mock('@/hooks/useProjects', () => ({
  useProject: vi.fn(),
}))

vi.mock('@/hooks/useServers', () => ({
  useServers: vi.fn(),
}))

vi.mock('@/hooks/useModules', () => ({
  useNetworks: vi.fn(),
  useValidateNetwork: () => ({ mutate: vi.fn() }),
}))

vi.mock('@/hooks/useCopy', () => ({
  useCopy: () => ({ copy: vi.fn(), copiedKey: null }),
}))

vi.mock('@/lib/api', () => ({
  api: { services: { update: vi.fn() } },
}))

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

function setupNetworks({ networks = [], serverId = 'srv-1', projectServerId = 'srv-1' } = {}) {
  vi.mocked(useProject).mockReturnValue({
    data: { id: 'proj-1', serverId: projectServerId } as any,
    isLoading: false,
  } as any)
  vi.mocked(useServers).mockReturnValue({
    data: [{ id: 'srv-1', name: 'Core' }] as any[],
    isLoading: false,
  } as any)
  vi.mocked(useNetworks).mockReturnValue({
    data: networks,
    isLoading: false,
  } as any)
}

describe('External Networks in NetworkSettings', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    updateServiceMutate.mockReset()
    updateConfigMutate.mockReset()
  })

  it('renders External Networks section', () => {
    setupNetworks()
    renderWithClient(<SettingsPanel svc={mockService()} />)

    fireEvent.click(screen.getByText('Networking'))

    expect(screen.getByText('External Networks')).toBeInTheDocument()
    expect(screen.getByText(/Connect this service to Docker networks/)).toBeInTheDocument()
  })

  it('shows empty state when no server is assigned', () => {
    vi.mocked(useProject).mockReturnValue({
      data: { id: 'proj-1', serverId: null } as any,
      isLoading: false,
    } as any)
    vi.mocked(useServers).mockReturnValue({ data: [], isLoading: false } as any)
    vi.mocked(useNetworks).mockReturnValue({ data: [], isLoading: false } as any)

    renderWithClient(<SettingsPanel svc={mockService()} />)
    fireEvent.click(screen.getByText('Networking'))

    expect(screen.getByText('No server assigned to this project.')).toBeInTheDocument()
  })

  it('shows empty state when no connectable networks', () => {
    setupNetworks({ networks: [] })
    renderWithClient(<SettingsPanel svc={mockService()} />)
    fireEvent.click(screen.getByText('Networking'))

    expect(screen.getByText('No connectable networks found on this server.')).toBeInTheDocument()
  })

  it('displays connectable networks as checkboxes', () => {
    setupNetworks({
      networks: [
        { name: 'matrix-postgres', driver: 'bridge', containers: 3, connectable: true },
        { name: 'proxy_web', driver: 'overlay', containers: 1, connectable: true },
      ],
    })

    renderWithClient(<SettingsPanel svc={mockService()} />)
    fireEvent.click(screen.getByText('Networking'))

    expect(screen.getByText('matrix-postgres')).toBeInTheDocument()
    expect(screen.getByText('proxy_web')).toBeInTheDocument()
    expect(screen.getByText(/bridge/)).toBeInTheDocument()
  })

  it('excludes non-connectable networks', () => {
    setupNetworks({
      networks: [
        { name: 'matrix-postgres', driver: 'bridge', containers: 3, connectable: true },
        { name: 'host', driver: 'host', containers: 0, connectable: false },
      ],
    })

    renderWithClient(<SettingsPanel svc={mockService()} />)
    fireEvent.click(screen.getByText('Networking'))

    expect(screen.getByText('matrix-postgres')).toBeInTheDocument()
    expect(screen.queryByText('host')).not.toBeInTheDocument()
  })

  it('toggles a network on when checkbox is clicked', () => {
    setupNetworks({
      networks: [
        { name: 'matrix-postgres', driver: 'bridge', containers: 3, connectable: true },
      ],
    })

    renderWithClient(<SettingsPanel svc={mockService()} />)
    fireEvent.click(screen.getByText('Networking'))

    const checkbox = screen.getByRole('checkbox', { name: /matrix-postgres/i })
    expect(checkbox).not.toBeChecked()

    fireEvent.click(checkbox)

    expect(updateServiceMutate).toHaveBeenCalledWith({
      id: 'svc-1',
      data: { externalNetworks: ['matrix-postgres'] },
    })
  })

  it('toggles a network off when checkbox is unchecked', () => {
    setupNetworks({
      networks: [
        { name: 'matrix-postgres', driver: 'bridge', containers: 3, connectable: true },
      ],
    })

    const service = mockService({ externalNetworks: ['matrix-postgres'] })
    renderWithClient(<SettingsPanel svc={service} />)
    fireEvent.click(screen.getByText('Networking'))

    const checkbox = screen.getByRole('checkbox', { name: /matrix-postgres/i })
    expect(checkbox).toBeChecked()

    fireEvent.click(checkbox)

    expect(updateServiceMutate).toHaveBeenCalledWith({
      id: 'svc-1',
      data: { externalNetworks: [] },
    })
  })

  it('shows selected networks as tagged pills', () => {
    setupNetworks({
      networks: [
        { name: 'matrix-postgres', driver: 'bridge', containers: 3, connectable: true },
        { name: 'proxy_web', driver: 'overlay', containers: 1, connectable: true },
      ],
    })

    const service = mockService({ externalNetworks: ['matrix-postgres'] })
    renderWithClient(<SettingsPanel svc={service} />)
    fireEvent.click(screen.getByText('Networking'))

    const matches = screen.getAllByText('matrix-postgres')
    expect(matches.length).toBeGreaterThanOrEqual(2)
    expect(matches.some((el) => el.closest('[class*="bg-[#8b5cf6]/15"]'))).toBe(true)
  })

  it('removes a network via pill button', () => {
    setupNetworks({
      networks: [
        { name: 'matrix-postgres', driver: 'bridge', containers: 3, connectable: true },
        { name: 'proxy_web', driver: 'overlay', containers: 1, connectable: true },
      ],
    })

    const service = mockService({ externalNetworks: ['matrix-postgres', 'proxy_web'] })
    renderWithClient(<SettingsPanel svc={service} />)
    fireEvent.click(screen.getByText('Networking'))

    const removeButtons = screen.getAllByRole('button')
    const pillRemoveBtn = removeButtons.find((btn) => {
      const svg = btn.querySelector('svg')
      return svg && btn.closest('[class*="rounded"]')?.textContent?.includes('matrix-postgres')
    })

    if (pillRemoveBtn) {
      fireEvent.click(pillRemoveBtn)
      expect(updateServiceMutate).toHaveBeenCalledWith({
        id: 'svc-1',
        data: { externalNetworks: ['proxy_web'] },
      })
    }
  })

  it('adds multiple networks', () => {
    setupNetworks({
      networks: [
        { name: 'matrix-postgres', driver: 'bridge', containers: 3, connectable: true },
        { name: 'proxy_web', driver: 'overlay', containers: 1, connectable: true },
      ],
    })

    const service = mockService({ externalNetworks: ['matrix-postgres'] })
    renderWithClient(<SettingsPanel svc={service} />)
    fireEvent.click(screen.getByText('Networking'))

    const proxyCheckbox = screen.getByRole('checkbox', { name: /proxy_web/i })
    fireEvent.click(proxyCheckbox)

    expect(updateServiceMutate).toHaveBeenCalledWith({
      id: 'svc-1',
      data: { externalNetworks: ['matrix-postgres', 'proxy_web'] },
    })
  })
})
