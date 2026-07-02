import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import BackupDestinationsTab from '@/features/settings/BackupDestinationsTab'

const mockDestinations = [
  { id: 'dest-1', name: 'Production S3', provider: 's3', bucket: 'backups', region: 'us-east-1', status: 'verified', configured: true },
]

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
}))

function renderWithClient(ui: React.ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(<QueryClientProvider client={client}>{ui}</QueryClientProvider>)
}

describe('BackupDestinationsTab', () => {
  beforeEach(() => {
    vi.clearAllMocks()
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
      expect(screen.getByText(/save this recovery key now/i)).toBeInTheDocument()
      expect(screen.getByText('abcd1234')).toBeInTheDocument()
    })
  })
})
