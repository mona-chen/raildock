import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import type { UnmanagedDatastoreScan } from '@/types'
import ServerUnmanagedDatastoresModal from '@/features/servers/ServerUnmanagedDatastoresModal'

const state = vi.hoisted(() => ({
  scan: null as UnmanagedDatastoreScan | null,
  mutate: vi.fn(),
  refetch: vi.fn(),
}))

vi.mock('@/hooks/useServers', () => ({
  useUnmanagedDatastores: () => ({
    data: state.scan ?? undefined,
    isLoading: false,
    isError: false,
    error: null,
    refetch: state.refetch,
    isFetching: false,
  }),
  useAdoptDatastore: () => ({ mutate: state.mutate, isPending: false }),
}))

vi.mock('@/hooks/useProjects', () => ({
  useProjects: () => ({ data: [{ id: 'proj-1', name: 'tween', serverId: 'srv-1' }] }),
}))

function renderModal() {
  return render(<ServerUnmanagedDatastoresModal serverId="srv-1" serverName="tween-prod" onClose={vi.fn()} />)
}

describe('ServerUnmanagedDatastoresModal', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    state.scan = {
      resources: [
        {
          name: 'tween-jean-postgres',
          subtype: 'postgres',
          serviceType: 'database',
          status: 'running',
          linkedApps: ['tween-jean-646e2ba9'],
        },
        {
          name: 'alexandrie-mysql-b68592a0',
          subtype: 'mysql',
          serviceType: 'database',
          status: 'stopped',
          linkedApps: [],
        },
      ],
      errors: [],
    }
  })

  it('lists datastores RailDock does not track, with their subtype and links', () => {
    renderModal()

    expect(screen.getByText('tween-jean-postgres')).toBeInTheDocument()
    expect(screen.getByText('postgres')).toBeInTheDocument()
    expect(screen.getByText(/tween-jean-646e2ba9/)).toBeInTheDocument()
  })

  it('adopts a datastore into the server project', async () => {
    renderModal()

    fireEvent.click(screen.getAllByRole('button', { name: /^adopt$/i })[0])
    fireEvent.click(screen.getByRole('button', { name: /confirm adoption/i }))

    await waitFor(() => {
      expect(state.mutate).toHaveBeenCalledWith(
        { resourceName: 'tween-jean-postgres', projectId: 'proj-1' },
        expect.anything()
      )
    })
  })

  it('says so when every datastore is already tracked', () => {
    state.scan = { resources: [], errors: [] }

    renderModal()

    expect(screen.getByText(/every datastore on this host is tracked/i)).toBeInTheDocument()
  })

  it('surfaces per-plugin scan failures', () => {
    state.scan = { resources: [], errors: ['postgres:list failed: plugin exploded'] }

    renderModal()

    expect(screen.getByText(/postgres:list failed/)).toBeInTheDocument()
  })
})
