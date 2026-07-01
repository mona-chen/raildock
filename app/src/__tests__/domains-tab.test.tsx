import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import DomainsTab from '@/features/service-panel/tabs/DomainsTab'
import type { Service, Domain } from '@/types'

const addMutate = vi.fn()
const removeMutate = vi.fn()
const generateMutate = vi.fn()

vi.mock('@/hooks/useServices', () => ({
  useAddDomain: () => ({ mutate: addMutate, isPending: false }),
  useRemoveDomain: () => ({ mutate: removeMutate, isPending: false }),
  useGenerateDomain: () => ({ mutate: generateMutate, isPending: false }),
}))

vi.mock('@/hooks/useCopy', () => ({
  useCopy: () => ({ copy: vi.fn(), copiedKey: null }),
}))

function renderWithClient(ui: React.ReactElement) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  return render(<QueryClientProvider client={queryClient}>{ui}</QueryClientProvider>)
}

function mockDomain(overrides: Partial<Domain> = {}): Domain {
  return {
    id: 'd-1',
    hostname: 'example.com',
    port: 443,
    targetPort: 3000,
    ssl: true,
    letsencrypt: true,
    temporary: false,
    wildcard: false,
    sslStatus: 'active',
    challengeType: 'http',
    ...overrides,
  }
}

function mockService(overrides = {}): Service {
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
    linkedByServiceIds: [],
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
    autoDeploy: false,
    maintenanceMode: false,
    ...overrides,
  } as Service
}

describe('DomainsTab', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    addMutate.mockReset()
    removeMutate.mockReset()
    generateMutate.mockReset()
  })

  it('normalizes https:// prefix when adding a domain', () => {
    renderWithClient(<DomainsTab svc={mockService({ detectedPort: 3000 })} />)

    const input = screen.getByPlaceholderText('example.com or *.example.com')
    fireEvent.change(input, { target: { value: 'https://api.example.com' } })

    expect(screen.getByText('api.example.com')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Add' }))

    expect(addMutate).toHaveBeenCalledWith({
      id: 'svc-1',
      hostname: 'api.example.com',
      port: 443,
    })
  })

  it('strips port and path from input', () => {
    renderWithClient(<DomainsTab svc={mockService({ detectedPort: 3000 })} />)

    const input = screen.getByPlaceholderText('example.com or *.example.com')
    fireEvent.change(input, { target: { value: 'https://app.example.com:3000/v1' } })

    expect(screen.getByText('app.example.com')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Add' }))

    expect(addMutate).toHaveBeenCalledWith({
      id: 'svc-1',
      hostname: 'app.example.com',
      port: 443,
    })
  })

  it('shows an error for invalid hostnames', () => {
    renderWithClient(<DomainsTab svc={mockService()} />)

    const input = screen.getByPlaceholderText('example.com or *.example.com')
    fireEvent.change(input, { target: { value: 'not a valid host' } })

    expect(screen.getByText(/enter a valid hostname/i)).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Add' }))
    expect(addMutate).not.toHaveBeenCalled()
  })

  it('submits on Enter key', () => {
    renderWithClient(<DomainsTab svc={mockService({ detectedPort: 3000 })} />)

    const input = screen.getByPlaceholderText('example.com or *.example.com')
    fireEvent.change(input, { target: { value: 'sub.example.com' } })
    fireEvent.keyDown(input, { key: 'Enter', code: 'Enter' })

    expect(addMutate).toHaveBeenCalledWith({
      id: 'svc-1',
      hostname: 'sub.example.com',
      port: 443,
    })
  })

  it('allows overriding target port in advanced mode', () => {
    renderWithClient(<DomainsTab svc={mockService({ detectedPort: 3000 })} />)

    fireEvent.click(screen.getByRole('button', { name: /advanced/i }))

    const portInput = screen.getByPlaceholderText('3000')
    fireEvent.change(portInput, { target: { value: '8080' } })

    const input = screen.getByPlaceholderText('example.com or *.example.com')
    fireEvent.change(input, { target: { value: 'custom.example.com' } })
    fireEvent.click(screen.getByRole('button', { name: 'Add' }))

    expect(addMutate).toHaveBeenCalledWith({
      id: 'svc-1',
      hostname: 'custom.example.com',
      port: 443,
      targetPort: 8080,
    })
  })

  it('renders configured domains with routing info', () => {
    const service = mockService({
      detectedPort: 3000,
      domains: [mockDomain({ hostname: 'api.example.com', targetPort: 3000, sslStatus: 'active' })],
    })
    renderWithClient(<DomainsTab svc={service} />)

    expect(screen.getByText('api.example.com')).toBeInTheDocument()
    expect(screen.getByText(/container port 3000/i)).toBeInTheDocument()
  })

  it('removes a domain after confirmation', () => {
    vi.stubGlobal('confirm', vi.fn(() => true))

    const service = mockService({
      detectedPort: 3000,
      domains: [mockDomain({ hostname: 'api.example.com' })],
    })
    renderWithClient(<DomainsTab svc={service} />)

    fireEvent.click(screen.getByTitle('Remove domain'))

    expect(removeMutate).toHaveBeenCalledWith({ id: 'svc-1', hostname: 'api.example.com' })

    vi.unstubAllGlobals()
  })

  it('does not remove a domain when confirmation is cancelled', () => {
    vi.stubGlobal('confirm', vi.fn(() => false))

    const service = mockService({
      detectedPort: 3000,
      domains: [mockDomain({ hostname: 'api.example.com' })],
    })
    renderWithClient(<DomainsTab svc={service} />)

    fireEvent.click(screen.getByTitle('Remove domain'))

    expect(removeMutate).not.toHaveBeenCalled()

    vi.unstubAllGlobals()
  })
})
