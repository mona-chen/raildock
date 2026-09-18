import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import BackupDestinationsTab from '@/features/settings/BackupDestinationsTab'

const mockDestinations = [
  { id: 'dest-1', name: 'Production S3', provider: 's3', bucket: 'backups', region: 'us-east-1', status: 'verified', configured: true },
]

// Organization default, mutated per test.
const defaultsState = { ids: [] as string[] }
const updateDefaults = vi.fn()

vi.mock('@/stores/useAuthStore', () => ({
  useAuthStore: () => ({ currentOrganizationId: 'org-1' }),
}))

vi.mock('@/hooks/useBackupDestinations', () => ({
  useBackupDestinations: (organizationId?: string) => ({
    data: organizationId ? mockDestinations : [],
    isLoading: false,
  }),
  useCreateBackupDestination: () => ({
    mutate: vi.fn((_, options) => options?.onSuccess?.({ recoveryKey: 'abcd1234' })),
    isPending: false,
  }),
  useDeleteBackupDestination: () => ({ mutate: vi.fn(), isPending: false }),
  useVerifyBackupDestination: () => ({ mutate: vi.fn(), isPending: false }),
  useUpdateBackupDestination: () => ({ mutate: vi.fn(), isPending: false }),
  useBackupDestinationDefaults: () => ({ data: defaultsState.ids, isLoading: false }),
  useUpdateBackupDestinationDefaults: () => ({ mutate: updateDefaults, isPending: false }),
}))

function renderWithClient(ui: React.ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(<QueryClientProvider client={client}>{ui}</QueryClientProvider>)
}

describe('BackupDestinationsTab', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    defaultsState.ids = []
  })

  it('marks the organization default and makes one on demand', () => {
    renderWithClient(<BackupDestinationsTab />)

    fireEvent.click(screen.getByRole('button', { name: /use production s3 by default/i }))

    expect(updateDefaults).toHaveBeenCalledWith({ organizationId: 'org-1', destinationIds: ['dest-1'] })
  })

  it('shows which destination new backups use by default', () => {
    defaultsState.ids = ['dest-1']

    renderWithClient(<BackupDestinationsTab />)

    expect(screen.getByText('default')).toBeInTheDocument()
  })

  it('lists configured destinations', () => {
    renderWithClient(<BackupDestinationsTab />)
    expect(screen.getByText('Production S3')).toBeInTheDocument()
    expect(screen.getByText('Verified')).toBeInTheDocument()
  })

  it('opens the add-destination dialog', () => {
    renderWithClient(<BackupDestinationsTab />)
    fireEvent.click(screen.getByRole('button', { name: /add destination/i }))
    expect(screen.getByText('Add Backup Destination')).toBeInTheDocument()
    expect(screen.getByPlaceholderText('Production S3')).toBeInTheDocument()
  })

  it('shows the recovery key after creating a destination', async () => {
    renderWithClient(<BackupDestinationsTab />)
    fireEvent.click(screen.getByRole('button', { name: /add destination/i }))
    fireEvent.change(screen.getByPlaceholderText('Production S3'), { target: { value: 'New Destination' } })
    fireEvent.change(screen.getByPlaceholderText('my-backups'), { target: { value: 'bucket' } })
    fireEvent.change(screen.getByPlaceholderText('AKIA...'), { target: { value: 'key' } })
    fireEvent.change(screen.getByPlaceholderText('••••••••'), { target: { value: 'secret' } })
    fireEvent.click(screen.getByRole('button', { name: /verify & save/i }))

    await waitFor(() => {
      expect(screen.getByDisplayValue('abcd1234')).toBeInTheDocument()
    })
  })

  // Telling a user they need the key to restore is wrong — RailDock keeps it
  // encrypted server-side and restores never prompt for it.
  it('explains that restores do not require the recovery key', async () => {
    renderWithClient(<BackupDestinationsTab />)
    fireEvent.click(screen.getByRole('button', { name: /add destination/i }))
    fireEvent.change(screen.getByPlaceholderText('Production S3'), { target: { value: 'New Destination' } })
    fireEvent.change(screen.getByPlaceholderText('my-backups'), { target: { value: 'bucket' } })
    fireEvent.change(screen.getByPlaceholderText('AKIA...'), { target: { value: 'key' } })
    fireEvent.change(screen.getByPlaceholderText('••••••••'), { target: { value: 'secret' } })
    fireEvent.click(screen.getByRole('button', { name: /verify & save/i }))

    await waitFor(() => {
      expect(screen.getByText(/restores already work without this key/i)).toBeInTheDocument()
    })
    expect(screen.queryByText(/you need it to restore/i)).not.toBeInTheDocument()
  })
})
