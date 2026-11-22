import { beforeEach, describe, expect, it, vi } from 'vitest'
import { render, renderHook, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import ProjectsPage from '@/pages/ProjectsPage'
import { PreflightChecklist } from '@/features/servers/ServerSetupWizard'
import { useServerSetupLogs } from '@/hooks/useServerSetupLogs'
import { parseSshPort } from '@/lib/servers'
import { preferredServerId } from '@/lib/projects'
import type { Server } from '@/types'

const { create, servers, provisionStatus } = vi.hoisted(() => ({
  create: vi.fn(),
  servers: { list: [] as Array<Partial<Server>> },
  provisionStatus: vi.fn(),
}))

vi.mock('@/hooks/useProjects', () => ({ useProjects: () => ({ data: [] }), useCreateProject: () => ({ mutate: create }), useDestroyProject: () => ({ mutateAsync: vi.fn() }) }))
vi.mock('@/hooks/useServers', () => ({ useServers: () => ({ data: servers.list }) }))
vi.mock('@/components/OnboardingChecklist', () => ({ default: () => null }))
vi.mock('@/lib/cable', () => ({ isCableAvailable: () => false, getCable: vi.fn() }))
vi.mock('@/lib/api', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/lib/api')>()
  return { ...actual, api: { ...actual.api, servers: { ...actual.api.servers, provisionStatus } } }
})

beforeEach(() => {
  vi.clearAllMocks()
  servers.list = []
})

describe('parseSshPort', () => {
  it('accepts 1-65535 and rejects anything else', () => {
    expect(parseSshPort('22')).toBe(22)
    expect(parseSshPort(' 2222 ')).toBe(2222)
    expect(parseSshPort('65535')).toBe(65535)
    for (const bad of ['', '0', '65536', '22a', '-1', '2.2', '123456']) expect(parseSshPort(bad)).toBeNull()
  })
})

describe('preferredServerId', () => {
  it('prefers a connected server, then the oldest', () => {
    expect(preferredServerId([{ id: '1', status: 'error' }, { id: '3', status: 'connected' }, { id: '2', status: 'connected' }])).toBe('2')
    expect(preferredServerId([{ id: '5', status: 'error' }, { id: '9', status: 'disconnected' }])).toBe('9')
    expect(preferredServerId([])).toBeUndefined()
  })
})

describe('PreflightChecklist', () => {
  it('lists every check and says nothing was installed when one failed', () => {
    render(<PreflightChecklist checks={[
      { key: 'os', label: 'Operating system', status: 'pass', detail: 'Ubuntu 24.04 LTS' },
      { key: 'memory', label: 'Memory', status: 'warn', detail: '0.8 GB RAM' },
      { key: 'bootstrap_reach', label: 'Reach bootstrap.sh', status: 'fail', detail: 'no response' },
    ]} />)
    expect(screen.getByText('Operating system')).toBeInTheDocument()
    expect(screen.getByText('0.8 GB RAM')).toBeInTheDocument()
    expect(screen.getByLabelText('Failed')).toBeInTheDocument()
    expect(screen.getByText('Nothing was installed')).toBeInTheDocument()
  })
})

describe('useServerSetupLogs', () => {
  it('exposes preflight results from the polled setup progress', async () => {
    provisionStatus.mockResolvedValue({
      setupId: 'abc', state: 'failed', logs: [], error: 'Preflight failed',
      preflight: [{ key: 'arch', label: 'CPU architecture', status: 'fail', detail: 'armv7l' }],
    })
    const { result } = renderHook(() => useServerSetupLogs('abc'))
    await waitFor(() => expect(result.current.preflight?.[0]?.key).toBe('arch'))
    expect(result.current.state).toBe('failed')
  })
})

describe('ProjectsPage server picker', () => {
  const openCreate = async () => {
    const user = userEvent.setup()
    render(<MemoryRouter><ProjectsPage /></MemoryRouter>)
    // The empty state repeats the header's button; either opens the dialog.
    await user.click(screen.getAllByRole('button', { name: /new project/i })[0])
    return user
  }

  it('defaults to the connected server and sends it with the project', async () => {
    servers.list = [
      { id: '1', name: 'old-box', host: '10.0.0.1', status: 'error' },
      { id: '2', name: 'prod-01', host: '10.0.0.2', status: 'connected' },
    ]
    const user = await openCreate()
    expect(screen.getByLabelText('Server')).toHaveTextContent('prod-01')
    await user.type(screen.getByLabelText('Project Name'), 'Launch{Enter}')
    expect(create).toHaveBeenCalledWith(expect.objectContaining({ name: 'Launch', serverId: '2' }), expect.anything())
  })

  it('warns when the only server was unreachable on its last check', async () => {
    servers.list = [{ id: '7', name: 'flaky', host: '10.0.0.7', status: 'error' }]
    await openCreate()
    expect(screen.getByLabelText('Server')).toHaveTextContent('flaky')
    expect(screen.getByText(/could not reach this server/i)).toBeInTheDocument()
  })

  it('hides the picker when there are no servers', async () => {
    await openCreate()
    expect(screen.queryByLabelText('Server')).not.toBeInTheDocument()
  })
})
