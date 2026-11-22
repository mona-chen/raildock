import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import PitrSubTab from '@/features/service-panel/tabs/PitrSubTab'
import { pitrWindowError, suggestRecoveredName } from '@/features/service-panel/tabs/recovery/lib'
import type { Service } from '@/types'

const restoreToNew = vi.fn()
const state: { restores: unknown[]; siblings: Partial<Service>[] } = { restores: [], siblings: [] }

const earliest = '2026-11-20T10:00:00.000Z'
const lastWal = '2026-11-22T09:00:00.000Z'

vi.mock('@/hooks/useServices', () => ({
  useRecovery: () => ({
    data: {
      destinations: [{ id: '1', name: 'R2', status: 'verified' }],
      pitr: { enabled: true, status: 'active', retentionDays: 7, backupDestinationId: '1', lastWalArchivedAt: lastWal },
      drills: [],
      pitrRestores: state.restores,
      backupPreferences: { organizationDestinationIds: [], serviceDestinationIds: null, defaultDestinationIds: [] },
    },
    isLoading: false,
    isError: false,
    refetch: vi.fn(),
  }),
  useBackups: () => ({ data: [{ id: 'b1', backupKind: 'pitr_base', status: 'completed', createdAt: earliest }] }),
  useConfigurePitr: () => ({ mutate: vi.fn(), isPending: false }),
  useDisablePitr: () => ({ mutate: vi.fn(), isPending: false }),
  useRunRestoreDrill: () => ({ mutate: vi.fn(), isPending: false }),
  useRestorePitrToNewService: () => ({ mutate: restoreToNew, reset: vi.fn(), isPending: false, error: null }),
  useServices: () => ({ data: state.siblings }),
}))

const svc = {
  id: 'svc-1',
  name: 'main-db',
  type: 'database',
  subtype: 'postgres',
  status: 'running',
  projectId: 'proj-1',
  environmentId: 'env-1',
} as unknown as Service

function renderTab() {
  return render(
    <MemoryRouter>
      <PitrSubTab svc={svc} serviceId="svc-1" />
    </MemoryRouter>,
  )
}

// datetime-local values are local time; build one from a UTC instant.
function localInput(iso: string) {
  const date = new Date(iso)
  const pad = (value: number) => String(value).padStart(2, '0')
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`
}

describe('Recover to a new service', () => {
  beforeEach(() => {
    restoreToNew.mockReset()
    state.restores = []
    state.siblings = [{ id: 'svc-1', name: 'main-db', environmentId: 'env-1' }]
  })

  it('replaces the "not available yet" note with a recovery into a new service', () => {
    renderTab()

    expect(screen.queryByText(/not available from the dashboard yet/i)).not.toBeInTheDocument()
    const section = screen.getByRole('region', { name: 'Recover to a new service' })
    expect(within(section).getByLabelText('New service name')).toHaveValue('main-db-recovered')
    expect(within(section).getByRole('button', { name: /Recover to a new service/ })).toBeDisabled()
  })

  it('confirms, then sends the chosen moment and name without touching the source', () => {
    renderTab()
    const section = screen.getByRole('region', { name: 'Recover to a new service' })
    const target = '2026-11-21T12:30:00.000Z'

    fireEvent.change(within(section).getByLabelText(/Recover to/), { target: { value: localInput(target) } })
    fireEvent.change(within(section).getByLabelText('New service name'), { target: { value: 'orders-before-bug' } })
    fireEvent.click(within(section).getByRole('button', { name: /Recover to a new service/ }))

    const dialog = screen.getByRole('dialog')
    expect(dialog).toHaveTextContent('main-db is not stopped or changed')
    fireEvent.click(within(dialog).getByRole('button', { name: 'Recover' }))

    expect(restoreToNew).toHaveBeenCalledWith(
      { id: 'svc-1', targetTime: target, name: 'orders-before-bug' },
      expect.objectContaining({ onSuccess: expect.any(Function) }),
    )
  })

  it('refuses a moment outside the recovery window', () => {
    renderTab()
    const section = screen.getByRole('region', { name: 'Recover to a new service' })

    fireEvent.change(within(section).getByLabelText(/Recover to/), { target: { value: localInput('2026-11-19T10:00:00.000Z') } })

    expect(within(section).getByText(/Pick a moment between/)).toBeInTheDocument()
    expect(within(section).getByRole('button', { name: /Recover to a new service/ })).toBeDisabled()
  })

  it('refuses a name already used in the environment', () => {
    renderTab()
    const section = screen.getByRole('region', { name: 'Recover to a new service' })

    fireEvent.change(within(section).getByLabelText(/Recover to/), { target: { value: localInput('2026-11-21T12:30:00.000Z') } })
    fireEvent.change(within(section).getByLabelText('New service name'), { target: { value: 'MAIN-DB' } })

    expect(within(section).getByText(/already exists in this environment/)).toBeInTheDocument()
    expect(within(section).getByRole('button', { name: /Recover to a new service/ })).toBeDisabled()
  })

  it('shows progress and blocks a second recovery while one runs', () => {
    state.restores = [{ id: '7', serviceName: 'main-db-recovered', restoredServiceName: 'main-db-recovered', targetTime: '2026-11-21T12:30:00.000Z', status: 'running', log: 'Recovered 4 tables; copying them into main-db-recovered' }]
    renderTab()
    const section = screen.getByRole('region', { name: 'Recover to a new service' })

    expect(within(section).getByText(/copying them into main-db-recovered/)).toBeInTheDocument()
    expect(within(section).getByText(/already running/)).toBeInTheDocument()
  })
})

describe('recovery window helpers', () => {
  const now = new Date('2026-11-22T12:00:00.000Z')

  it('accepts a moment inside the window and rejects the edges', () => {
    expect(pitrWindowError(new Date('2026-11-21T00:00:00Z'), earliest, lastWal, now)).toBeNull()
    expect(pitrWindowError(new Date(earliest), earliest, lastWal, now)).toMatch(/Pick a moment/)
    expect(pitrWindowError(new Date('2026-11-22T09:30:00Z'), earliest, lastWal, now)).toMatch(/Pick a moment/)
    expect(pitrWindowError(new Date('2026-11-21T00:00:00Z'), null, lastWal, now)).toMatch(/No base backup/)
  })

  it('suggests a free name', () => {
    expect(suggestRecoveredName('db', ['db'])).toBe('db-recovered')
    expect(suggestRecoveredName('db', ['db', 'DB-recovered', 'db-recovered-2'])).toBe('db-recovered-3')
  })
})
