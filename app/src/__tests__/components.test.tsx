import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

vi.mock('@/hooks/useServices', () => ({
  useService: vi.fn(),
  useScaleProcess: () => ({ mutate: vi.fn(), isPending: false }),
  useSetEnvVar: () => ({ mutate: vi.fn() }),
  useUnsetEnvVar: () => ({ mutate: vi.fn() }),
  useServiceMetrics: () => ({ data: null }),
  useServiceDeployments: () => ({ data: [] }),
  useAddDomain: () => ({ mutate: vi.fn() }),
  useRemoveDomain: () => ({ mutate: vi.fn() }),
  useAddStorageMount: () => ({ mutate: vi.fn() }),
  useRemoveStorageMount: () => ({ mutate: vi.fn() }),
  useBackupService: () => ({ mutate: vi.fn(), isPending: false }),
  useRestoreService: () => ({ mutate: vi.fn(), isPending: false }),
  useBackups: () => ({ data: null, isLoading: false, isError: false, refetch: vi.fn() }),
  useRollbackService: () => ({ mutate: vi.fn(), isPending: false }),
  useContainerStatus: () => ({ data: null }),
  useUpdateService: () => ({ mutate: vi.fn() }),
  useDeployService: () => ({ mutate: vi.fn(), isPending: false }),
  useStartService: () => ({ mutate: vi.fn(), isPending: false }),
  useStopService: () => ({ mutate: vi.fn(), isPending: false }),
  useRestartService: () => ({ mutate: vi.fn(), isPending: false }),
  useRebuildService: () => ({ mutate: vi.fn(), isPending: false }),
  useDeployment: () => ({ data: null, isLoading: false }),
  useServiceLogs: () => ({ data: null }),
  useLinkedByServices: () => ({ data: [] }),
  useLinkService: () => ({ mutate: vi.fn(), isPending: false }),
  useUnlinkService: () => ({ mutate: vi.fn(), isPending: false }),
}))

vi.mock('@/hooks/useWebSocketLogs', () => ({
  useWebSocketLogs: () => ({ lines: [], isConnected: false, clear: vi.fn() }),
}))

vi.mock('@/hooks/useWebSocketDeployments', () => ({
  useWebSocketDeployments: () => ({ lastUpdate: null, isConnected: false }),
}))

vi.mock('@/hooks/useServers', () => ({
  useServers: vi.fn(),
  useCreateServer: () => ({ mutate: vi.fn(), isPending: false }),
  useTestServer: () => ({ mutate: vi.fn(), isPending: false, error: null }),
  useDestroyServer: () => ({ mutate: vi.fn() }),
  useValidateServer: () => ({ mutate: vi.fn(), isPending: false }),
  useUpdateServer: () => ({ mutate: vi.fn(), isPending: false }),
}))

vi.mock('@/hooks/useOrganizations', () => ({
  useOrganizations: () => ({ data: [], isLoading: false }),
  useCreateOrganization: () => ({ mutate: vi.fn(), isPending: false }),
  useDeleteOrganization: () => ({ mutate: vi.fn(), isPending: false }),
  useServerBootstrap: () => ({
    data: {
      publicKey: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExample raildock',
      command: 'curl -fsSL http://localhost/bootstrap.sh | bash -s -- ssh-ed25519...',
    },
    isLoading: false,
    isError: false,
    error: null,
  }),
}))

vi.mock('@/hooks/useModules', () => ({
  useNetworks: () => ({ data: [], isLoading: false }),
  useValidateNetwork: () => ({ mutate: vi.fn(), isPending: false }),
}))

vi.mock('@/stores/useAuthStore', () => ({
  useAuthStore: (selector?: (state: unknown) => unknown) => {
    const state = {
      setToken: vi.fn(),
      setUser: vi.fn(),
      isAuthenticated: () => false,
      currentOrganizationId: 'org-1',
      currentOrganization: () => ({ id: 'org-1', name: 'Acme', slug: 'acme', role: 'owner' }),
    }
    return selector ? selector(state) : state
  },
}))

vi.mock('@/lib/api', () => ({
  authApi: {
    login: vi.fn(),
    register: vi.fn(),
  },
}))

import { useService } from '@/hooks/useServices'
import { useServers } from '@/hooks/useServers'
import ServicePanel from '@/pages/ServicePanel'
import AuthPage from '@/pages/AuthPage'
import ServerPage from '@/pages/ServerPage'
import CanvasToolbar from '@/features/project-canvas/components/CanvasToolbar'
import { ErrorBoundary } from '@/features/shared/ErrorBoundary'

function renderWithClient(ui: React.ReactElement) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  return render(<QueryClientProvider client={queryClient}>{ui}</QueryClientProvider>)
}

function mockService(overrides = {}) {
  return {
    id: 'svc-1',
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
    nginx: {
      clientMaxBodySize: '1m',
      readTimeout: '60s',
      keepaliveTimeout: '75s',
      hsts: true,
      hstsMaxAge: 15724800,
      hstsIncludeSubdomains: true,
      hstsPreload: false,
      bindAddressIpv4: '0.0.0.0',
      bindAddressIpv6: '[::]',
    },
    proxy: { enabled: true, proxyType: 'traefik', portMappings: [] },
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
    ...overrides,
  }
}

describe('ServicePanel', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('renders tabs and shows service name for app service', () => {
    ;(useService as ReturnType<typeof vi.fn>).mockReturnValue({ data: mockService() })

    renderWithClient(<ServicePanel serviceId="svc-1" onClose={vi.fn()} />)

    expect(screen.getAllByText('Test Service').length).toBeGreaterThanOrEqual(1)
    expect(screen.getByText('Overview')).toBeInTheDocument()
    expect(screen.getAllByText('Deploy').length).toBeGreaterThanOrEqual(1)
    expect(screen.getByText('Logs')).toBeInTheDocument()
    expect(screen.getByText('Variables')).toBeInTheDocument()
    expect(screen.getByText('Domains')).toBeInTheDocument()
    expect(screen.getByText('Storage')).toBeInTheDocument()
    expect(screen.getByText('Metrics')).toBeInTheDocument()
    expect(screen.getByText('Settings')).toBeInTheDocument()
  })

  it('switches tabs when clicked', () => {
    ;(useService as ReturnType<typeof vi.fn>).mockReturnValue({ data: mockService() })

    renderWithClient(<ServicePanel serviceId="svc-1" onClose={vi.fn()} />)

    fireEvent.click(screen.getByText('Logs'))
    expect(screen.getByText('Waiting for logs...')).toBeInTheDocument()
  })

  it('shows database and backups tabs for database service', () => {
    ;(useService as ReturnType<typeof vi.fn>).mockReturnValue({
      data: mockService({ type: 'database', subtype: 'postgres' }),
    })

    renderWithClient(<ServicePanel serviceId="svc-1" onClose={vi.fn()} />)

    expect(screen.getByText('Database')).toBeInTheDocument()
    expect(screen.getByText('Backups')).toBeInTheDocument()
  })
})

describe('AuthPage', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        json: () => Promise.resolve({ required: false }),
      })
    )
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('shows login form with validation attributes', () => {
    render(
      <MemoryRouter initialEntries={['/login']}>
        <AuthPage />
      </MemoryRouter>
    )

    expect(screen.getByRole('heading', { name: 'Sign In' })).toBeInTheDocument()
    const emailInput = screen.getByPlaceholderText('admin@example.com')
    const passwordInput = screen.getByPlaceholderText('••••••••')

    expect(emailInput).toHaveAttribute('type', 'email')
    expect(emailInput).toHaveAttribute('required')
    expect(passwordInput).toHaveAttribute('type', 'password')
    expect(passwordInput).toHaveAttribute('required')
    expect(passwordInput).toHaveAttribute('minLength', '6')
  })

  it('shows first-user setup form', () => {
    render(
      <MemoryRouter initialEntries={['/setup']}>
        <AuthPage />
      </MemoryRouter>
    )

    expect(screen.getByText('Create Admin Account')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('Admin User')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('admin@example.com')).toBeInTheDocument()
  })
})

describe('ServerPage', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('renders server list', () => {
    ;(useServers as ReturnType<typeof vi.fn>).mockReturnValue({
      data: [
        {
          id: 'srv-1',
          name: 'Production',
          host: '1.2.3.4',
          status: 'connected',
          dokkuVersion: '0.35.13',
          dockerVersion: '26.1.0',
          os: 'Ubuntu 22.04',
          uptime: '10d',
          diskUsage: { used: 20, total: 100 },
          memoryUsage: { used: 4, total: 16 },
          projectIds: [],
          defaultProxy: 'traefik',
        },
      ],
      isLoading: false,
    })

    render(<ServerPage />)

    expect(screen.getByText('Production')).toBeInTheDocument()
    expect(screen.getByText(/1\.2\.3\.4/)).toBeInTheDocument()
    expect(screen.getByText(/Ubuntu 22\.04/)).toBeInTheDocument()
  })

  it('shows add server wizard when button is clicked', () => {
    ;(useServers as ReturnType<typeof vi.fn>).mockReturnValue({
      data: [],
      isLoading: false,
    })

    render(<ServerPage />)

    fireEvent.click(screen.getByText('Add Server'))
    expect(screen.getByText('Connect a remote Dokku host')).toBeInTheDocument()
    expect(screen.getByText('Organization public key')).toBeInTheDocument()
    expect(screen.getByText('Bootstrap command')).toBeInTheDocument()

    fireEvent.click(screen.getByText('Continue'))
    expect(screen.getByPlaceholderText('dokku-prod-01')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('192.168.1.100')).toBeInTheDocument()
  })

  it('shows external Traefik settings for a server', () => {
    ;(useServers as ReturnType<typeof vi.fn>).mockReturnValue({
      data: [
        {
          id: 'srv-1',
          name: 'Production',
          host: '1.2.3.4',
          status: 'connected',
          dokkuVersion: '0.35.13',
          dockerVersion: '26.1.0',
          os: 'Ubuntu 22.04',
          uptime: '10d',
          diskUsage: { used: 20, total: 100 },
          memoryUsage: { used: 4, total: 16 },
          projectIds: [],
          defaultProxy: 'traefik',
          proxyMode: 'managed',
          externalProxyHttpEntrypoint: 'web',
          externalProxyHttpsEntrypoint: 'websecure',
          externalProxyDefaultLabels: {},
        },
      ],
      isLoading: false,
    })

    render(<ServerPage />)
    fireEvent.click(screen.getByTitle('Proxy settings'))
    fireEvent.change(screen.getByLabelText('Proxy Mode'), { target: { value: 'external' } })

    expect(screen.getByText('Existing Traefik')).toBeInTheDocument()
    expect(screen.getByLabelText('Traefik Docker Network')).toBeInTheDocument()
    expect(screen.getByLabelText('HTTP entrypoint')).toHaveValue('web')
    expect(screen.getByLabelText('HTTPS entrypoint')).toHaveValue('websecure')
  })
})

describe('CanvasToolbar', () => {
  it('renders project name and environment', () => {
    renderWithClient(
      <MemoryRouter>
        <CanvasToolbar projectId="test-project" projectName="My Project" projectEnvironment="production" connectionState="live" />
      </MemoryRouter>
    )

    expect(screen.getByText('My Project')).toBeInTheDocument()
    expect(screen.getByText('production')).toBeInTheDocument()
  })
})

describe('ErrorBoundary', () => {
  it('catches errors and shows fallback UI', () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {})

    const Thrower = () => {
      throw new Error('Test error')
    }

    render(
      <ErrorBoundary>
        <Thrower />
      </ErrorBoundary>
    )

    expect(screen.getByText('Something went wrong')).toBeInTheDocument()
    expect(screen.getByText('Test error')).toBeInTheDocument()
    expect(screen.getByText('Try again')).toBeInTheDocument()

    consoleError.mockRestore()
  })

  it('renders children when there is no error', () => {
    render(
      <ErrorBoundary>
        <div>Safe content</div>
      </ErrorBoundary>
    )

    expect(screen.getByText('Safe content')).toBeInTheDocument()
  })
})
