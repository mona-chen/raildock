import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { HashRouter, MemoryRouter } from 'react-router-dom'
import BackupsTab from '@/features/service-panel/tabs/BackupsTab'
import type { Service } from '@/types'

vi.mock('@/hooks/useServices', () => ({
  useBackups: () => ({ data: [], isLoading: false, isError: false, refetch: vi.fn() }),
  useVolumeSnapshots: () => ({ data: [], isLoading: false, isError: false, refetch: vi.fn() }),
  useRecovery: () => ({ data: { destinations: [], pitr: null }, isLoading: false }),
  useBackupSchedules: () => ({ data: [] }),
  useBackupService: () => ({ mutate: vi.fn(), isPending: false }),
  useCreateBackupSchedule: () => ({ mutate: vi.fn(), isPending: false }),
  useCreateVolumeBackupSchedule: () => ({ mutate: vi.fn(), isPending: false }),
  useUpdateBackupSchedule: () => ({ mutate: vi.fn(), isPending: false }),
  useDeleteBackup: () => ({ mutate: vi.fn(), isPending: false }),
  useDestroyBackupSchedule: () => ({ mutate: vi.fn(), isPending: false }),
  useRestoreBackup: () => ({ mutate: vi.fn(), isPending: false }),
  useRestoreService: () => ({ mutate: vi.fn(), isPending: false }),
  useSnapshotVolume: () => ({ mutate: vi.fn(), isPending: false }),
  useCreateSnapshotSchedule: () => ({ mutate: vi.fn(), isPending: false }),
  useConfigurePitr: () => ({ mutate: vi.fn(), isPending: false }),
  useRunRestoreDrill: () => ({ mutate: vi.fn(), isPending: false }),
}))

vi.mock('@/lib/api', () => ({
  api: { services: { downloadBackup: vi.fn() } },
}))

function renderWithClient(ui: React.ReactElement) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  // The sub-tabs link out to settings with react-router, so a router has to be
  // present or rendering throws.
  return render(
    <MemoryRouter>
      <QueryClientProvider client={queryClient}>{ui}</QueryClientProvider>
    </MemoryRouter>
  )
}

function mockService(overrides = {}): Service {
  return {
    id: 'svc-1',
    name: 'Test Service',
    type: 'database',
    subtype: 'postgres',
    status: 'running',
    projectId: 'proj-1',
    linkedServiceIds: [],
    envVars: [],
    domains: [],
    storageMounts: [],
    logs: [],
    backups: [],
    proxy: { enabled: true, proxyType: 'traefik', portMappings: [] },
    dockerOptions: [],
    resourceLimits: [],
    resourceReservations: [],
    checks: { enabled: true, wait: 5, timeout: 30, skipList: [] },
    letsencrypt: { enabled: false, email: '', staging: false, autoRenew: true },
    git: { deployBranch: 'main', keepGitDir: false, revEnvVar: true },
    traefik: { labels: {}, properties: {} },
    restartPolicy: 'on-failure',
    restartMaxRetries: 10,
    locked: false,
    autoDeploy: false,
    maintenanceMode: false,
    externalNetworks: [],
    ...overrides,
  }
}

describe('BackupsTab', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('renders sub-tabs and defaults to Backups', () => {
    renderWithClient(<BackupsTab svc={mockService()} serviceId="svc-1" />)

    expect(screen.getByRole('tab', { name: /Backups/i })).toHaveAttribute('aria-selected', 'true')
    expect(screen.getByRole('tab', { name: /Snapshots/i })).toHaveAttribute('aria-selected', 'false')
    expect(screen.getByRole('tab', { name: /PITR/i })).toHaveAttribute('aria-selected', 'false')
    expect(screen.getByText('Recovery')).toBeInTheDocument()
  })

  it('switches to Snapshots sub-tab', () => {
    renderWithClient(<BackupsTab svc={mockService({ storageMounts: [{ id: 'm1', hostPath: 'data', containerPath: '/data', kind: 'volume' }] })} serviceId="svc-1" />)

    fireEvent.click(screen.getByRole('tab', { name: /Snapshots/i }))

    expect(screen.getByRole('tab', { name: /Snapshots/i })).toHaveAttribute('aria-selected', 'true')
    expect(screen.getByText('Volume snapshots')).toBeInTheDocument()
  })

  it('switches to PITR sub-tab for postgres', () => {
    renderWithClient(<BackupsTab svc={mockService()} serviceId="svc-1" />)

    fireEvent.click(screen.getByRole('tab', { name: /PITR/i }))

    expect(screen.getByRole('tab', { name: /PITR/i })).toHaveAttribute('aria-selected', 'true')
    expect(screen.getByText('PostgreSQL point-in-time recovery')).toBeInTheDocument()
  })

  // The app is served from a HashRouter, so a plain `href="/dashboard/..."`
  // performs a full page load, drops the hash, and the SPA falls through to the
  // root route — landing the user on project home instead of Backup settings.
  it('links to backup settings through the router', () => {
    const queryClient = new QueryClient({
      defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
    })
    render(
      <HashRouter>
        <QueryClientProvider client={queryClient}>
          <BackupsTab svc={mockService()} serviceId="svc-1" />
        </QueryClientProvider>
      </HashRouter>
    )

    const links = screen
      .getAllByRole('link')
      .filter((link) => link.getAttribute('href')?.includes('backup-destinations'))

    expect(links.length).toBeGreaterThan(0)
    links.forEach((link) => {
      expect(link.getAttribute('href')).toMatch(/^#\/dashboard\/settings\?tab=backup-destinations$/)
    })
  })
})
