import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

vi.mock('@/hooks/useServices', () => ({
  useService: vi.fn(),
  useCreateService: () => ({ mutate: vi.fn(), isPending: false }),
  useScaleProcess: () => ({ mutate: vi.fn(), isPending: false }),
  useSetEnvVar: () => ({ mutate: vi.fn() }),
  useSetEnvVars: () => ({ mutate: vi.fn() }),
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
  useProvisionServer: () => ({ mutate: vi.fn(), isPending: false, error: null }),
  useDestroyServer: () => ({ mutate: vi.fn() }),
  useValidateServer: () => ({ mutate: vi.fn(), isPending: false }),
  useUpdateServer: () => ({ mutate: vi.fn(), isPending: false }),
}))

vi.mock('@/hooks/useServerSetupLogs', () => ({
  useServerSetupLogs: () => ({ logs: [], state: 'idle', error: null, serverId: null }),
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

const mockModules = vi.hoisted(() => [
  {
    id: 'mod-postgres',
    slug: 'postgres',
    name: 'PostgreSQL',
    description: 'Relational database',
    icon: 'database',
    category: 'database',
    status: 'built_in',
    serviceSubtypes: [
      { id: 'st-postgres', subtype: 'postgres', name: 'PostgreSQL', description: 'Relational database', serviceType: 'database', defaultVersion: '16', icon: 'postgres', color: '#3b82f6' },
    ],
    builders: [],
  },
  {
    id: 'mod-redis',
    slug: 'redis',
    name: 'Redis',
    description: 'In-memory cache',
    icon: 'zap',
    category: 'cache',
    status: 'built_in',
    serviceSubtypes: [
      { id: 'st-redis', subtype: 'redis', name: 'Redis', description: 'In-memory cache', serviceType: 'cache', defaultVersion: '7', icon: 'redis', color: '#f59e0b' },
      { id: 'st-valkey', subtype: 'valkey', name: 'Valkey', description: 'Open source Redis alternative', serviceType: 'cache', defaultVersion: '8', icon: 'valkey', color: '#f59e0b' },
    ],
    builders: [],
  },
  {
    id: 'mod-rabbitmq',
    slug: 'rabbitmq',
    name: 'RabbitMQ',
    description: 'Message broker',
    icon: 'cog',
    category: 'queue',
    status: 'built_in',
    serviceSubtypes: [
      { id: 'st-rabbitmq', subtype: 'rabbitmq', name: 'RabbitMQ', description: 'Message broker', serviceType: 'queue', defaultVersion: '3', icon: 'rabbitmq', color: '#6b7280' },
    ],
    builders: [],
  },
  {
    id: 'mod-apps',
    slug: 'core-apps',
    name: 'Core Applications',
    description: 'Application subtypes',
    icon: 'rocket',
    category: 'tool',
    status: 'built_in',
    serviceSubtypes: [
      { id: 'st-web', subtype: 'web', name: 'Web Service', description: 'Internet-facing app', serviceType: 'app', defaultVersion: '', icon: 'globe', color: '#8b5cf6' },
      { id: 'st-worker', subtype: 'worker', name: 'Worker', description: 'Background worker', serviceType: 'app', defaultVersion: '', icon: 'cpu', color: '#8b5cf6' },
      { id: 'st-docker', subtype: 'docker', name: 'Docker Image', description: 'Pre-built image', serviceType: 'app', defaultVersion: '', icon: 'container', color: '#8b5cf6' },
    ],
    builders: [
      { id: 'b-auto', slug: 'auto', name: 'Auto-detect', description: 'Dokku auto-detects the builder', dokkuBuilder: 'auto', sourceTypes: ['git'], priority: 0, languageTags: [], icon: 'wand-2', color: '#6b7280', status: 'built_in' },
      { id: 'b-dockerfile', slug: 'dockerfile', name: 'Dockerfile', description: 'Build from Dockerfile', dokkuBuilder: 'dockerfile', sourceTypes: ['git'], priority: 10, languageTags: [], icon: 'file-code', color: '#3b82f6', status: 'built_in' },
      { id: 'b-null', slug: 'null', name: 'Null Builder', description: 'Use existing image', dokkuBuilder: 'null', sourceTypes: ['docker'], priority: 0, languageTags: [], icon: 'ban', color: '#6b7280', status: 'built_in' },
    ],
  },
])

const mockBuilders = vi.hoisted(() =>
  mockModules.flatMap((m) => m.builders)
)

vi.mock('@/hooks/useModules', () => ({
  useModules: () => ({ data: mockModules, isLoading: false }),
  useServiceSubtypes: (serviceType?: string) =>
    mockModules
      .flatMap((m) => m.serviceSubtypes)
      .filter((s) => !serviceType || s.serviceType === serviceType),
  useBuilders: (sourceType?: string) => ({
    data: sourceType ? mockBuilders.filter((b) => b.sourceTypes.includes(sourceType)) : mockBuilders,
    isLoading: false,
  }),
  useBuilder: (slug?: string) => mockBuilders.find((b) => b.slug === slug),
  useNetworks: () => ({ data: [], isLoading: false }),
  useValidateNetwork: () => ({ mutate: vi.fn(), isPending: false }),
  useInstallPlugin: () => ({ mutate: vi.fn(), isPending: false }),
  useEnablePlugin: () => ({ mutate: vi.fn(), isPending: false }),
  useDisablePlugin: () => ({ mutate: vi.fn(), isPending: false }),
  useUninstallPlugin: () => ({ mutate: vi.fn(), isPending: false }),
  usePluginSettings: () => ({ data: { settings: {} }, isLoading: false }),
  useUpdatePluginSettings: () => ({ mutate: vi.fn(), isPending: false }),
}))

vi.mock('@/hooks/useGitSources', () => ({
  useGitSources: () => ({ data: [], isLoading: false }),
  useGitSourceRepos: () => ({ data: { repos: [], syncing: false }, isLoading: false }),
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
import SettingsPage from '@/pages/SettingsPage'
import AddServiceModal from '@/pages/AddServiceModal'
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
    expect(screen.getByText('Connect a remote host to RailDock')).toBeInTheDocument()
    expect(screen.getByText('Prepare server')).toBeInTheDocument()
    expect(screen.getByText('Manual setup')).toBeInTheDocument()
    expect(screen.getByText('Organization public key')).toBeInTheDocument()
    fireEvent.click(screen.getByText('Continue'))
    expect(screen.getByPlaceholderText('raildock-prod-01')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('192.168.1.100')).toBeInTheDocument()
    expect(screen.getByText('Validate Server')).toBeInTheDocument()
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
    fireEvent.click(screen.getByLabelText('Proxy Mode'))
    fireEvent.click(screen.getByText('Existing reverse proxy'))

    expect(screen.getByText('Existing reverse proxy')).toBeInTheDocument()
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

describe('SettingsPage integrations tab', () => {
  it('renders installed modules from the plugin registry', () => {
    renderWithClient(
      <MemoryRouter initialEntries={[{ pathname: '/dashboard/settings', search: '?tab=integrations' }]}>
        <SettingsPage />
      </MemoryRouter>
    )

    expect(screen.getByText('Platform Settings')).toBeInTheDocument()
    expect(screen.getByText('PostgreSQL')).toBeInTheDocument()
    expect(screen.getByText('Relational database')).toBeInTheDocument()
    expect(screen.getByText('Redis')).toBeInTheDocument()
    expect(screen.getByText('postgres')).toBeInTheDocument()
    expect(screen.getByText('redis')).toBeInTheDocument()
  })
})

describe('AddServiceModal', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('shows database subtypes from the plugin registry', () => {
    renderWithClient(
      <MemoryRouter>
        <AddServiceModal projectId="proj-1" onClose={vi.fn()} />
      </MemoryRouter>
    )

    fireEvent.click(screen.getByText('Database'))
    expect(screen.getByText('Add Database')).toBeInTheDocument()
    expect(screen.getByText('Relational database · v16')).toBeInTheDocument()
  })

  it('shows cache and queue subtypes from the plugin registry', () => {
    renderWithClient(
      <MemoryRouter>
        <AddServiceModal projectId="proj-1" onClose={vi.fn()} />
      </MemoryRouter>
    )

    fireEvent.click(screen.getByText('Cache'))
    expect(screen.getByText('Add Service')).toBeInTheDocument()
    expect(screen.getByText('In-memory cache')).toBeInTheDocument()
    expect(screen.getByText('Open source Redis alternative')).toBeInTheDocument()

    fireEvent.click(screen.getByText('Back'))
    fireEvent.click(screen.getByText('Other Service'))
    expect(screen.getByText('Message broker')).toBeInTheDocument()
  })
})
