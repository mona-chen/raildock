import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import BackupDestinationsTab from '@/features/settings/BackupDestinationsTab'

const VERIFIED = { id: 'dest-1', name: 'Production S3', provider: 's3', bucket: 'backups', region: 'us-east-1', status: 'verified', configured: true, lastVerifiedAt: '2026-11-20T10:00:00Z' }
const FAILED = { id: 'dest-2', name: 'Broken R2', provider: 'r2', endpoint: 'https://acct.r2.cloudflarestorage.com', bucket: 'gone', region: 'auto', status: 'failed', configured: true, lastError: 'NoSuchBucket: bucket gone was not found' }
let mockDestinations: Array<Record<string, unknown>> = [VERIFIED]

// Organization default, mutated per test.
const defaultsState = { ids: [] as string[] }
const updateDefaults = vi.fn()
const authState = { role: 'owner' as 'owner' | 'admin' | 'member' }
const createMutate = vi.fn((_, options) => options?.onSuccess?.({ recoveryKey: 'abcd1234' }))
const updateMutate = vi.fn()
const verifyMutate = vi.fn()
const deleteMutateAsync = vi.fn()

vi.mock('@/stores/useAuthStore', () => ({
  useAuthStore: () => ({
    currentOrganizationId: 'org-1',
    currentOrganization: () => ({ id: 'org-1', name: 'Org', slug: 'org', role: authState.role }),
  }),
}))

vi.mock('@/hooks/useBackupDestinations', () => ({
  useBackupDestinations: (organizationId?: string) => ({
    data: organizationId ? mockDestinations : [],
    isLoading: false,
  }),
  useCreateBackupDestination: () => ({ mutate: createMutate, isPending: false }),
  useDeleteBackupDestination: () => ({ mutate: vi.fn(), mutateAsync: deleteMutateAsync, isPending: false }),
  useVerifyBackupDestination: () => ({ mutate: verifyMutate, isPending: false }),
  useUpdateBackupDestination: () => ({ mutate: updateMutate, isPending: false }),
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
    authState.role = 'owner'
    mockDestinations = [VERIFIED]
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

  it('edits a destination and keeps blank secrets out of the request', () => {
    renderWithClient(<BackupDestinationsTab />)
    fireEvent.click(screen.getByRole('button', { name: /edit production s3/i }))

    expect(screen.getByDisplayValue('Production S3')).toBeInTheDocument()
    expect(screen.queryByText(/use my own recovery key/i)).not.toBeInTheDocument()
    fireEvent.change(screen.getByDisplayValue('Production S3'), { target: { value: 'Renamed' } })
    fireEvent.click(screen.getByRole('button', { name: /verify & save/i }))

    expect(updateMutate).toHaveBeenCalledTimes(1)
    const [variables] = updateMutate.mock.calls[0]
    expect(variables.destinationId).toBe('dest-1')
    expect(variables.data.name).toBe('Renamed')
    expect(variables.data).not.toHaveProperty('access_key_id')
    expect(variables.data).not.toHaveProperty('secret_access_key')
  })

  it('validates a user-supplied recovery key before saving', () => {
    renderWithClient(<BackupDestinationsTab />)
    fireEvent.click(screen.getByRole('button', { name: /add destination/i }))
    fireEvent.change(screen.getByPlaceholderText('Production S3'), { target: { value: 'Mine' } })
    fireEvent.change(screen.getByPlaceholderText('my-backups'), { target: { value: 'bucket' } })
    fireEvent.change(screen.getByPlaceholderText('AKIA...'), { target: { value: 'key' } })
    fireEvent.change(screen.getByPlaceholderText('••••••••'), { target: { value: 'secret' } })
    fireEvent.click(screen.getByLabelText(/use my own recovery key/i))
    fireEvent.change(screen.getByLabelText(/your recovery key/i), { target: { value: 'abc' } })

    expect(screen.getByText(/must be exactly 64 hexadecimal characters/i)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /verify & save/i })).toBeDisabled()

    const key = 'a'.repeat(64)
    fireEvent.change(screen.getByLabelText(/your recovery key/i), { target: { value: key } })
    fireEvent.click(screen.getByRole('button', { name: /verify & save/i }))

    expect(createMutate.mock.calls[0][0].data.encryption_key).toBe(key)
  })

  it('shows when a destination last verified and why it failed', () => {
    mockDestinations = [VERIFIED, FAILED]
    renderWithClient(<BackupDestinationsTab />)

    expect(screen.getByText(/last verified/i)).toBeInTheDocument()
    expect(screen.getByText(/never verified/i)).toBeInTheDocument()
    expect(screen.getByText(/NoSuchBucket: bucket gone was not found/)).toBeInTheDocument()
  })

  it('does not offer a failed destination as the organization default', () => {
    mockDestinations = [FAILED]
    renderWithClient(<BackupDestinationsTab />)

    const star = screen.getByRole('button', { name: /use broken r2 by default/i })
    expect(star).toBeDisabled()
    expect(star).toHaveAttribute('title', expect.stringMatching(/verify this destination/i))
  })

  it('tracks verification per row', () => {
    mockDestinations = [VERIFIED, FAILED]
    renderWithClient(<BackupDestinationsTab />)

    fireEvent.click(screen.getByRole('button', { name: /verify broken r2/i }))

    expect(verifyMutate).toHaveBeenCalledWith({ organizationId: 'org-1', destinationId: 'dest-2' }, expect.anything())
    expect(screen.getByRole('button', { name: /verify broken r2/i })).toBeDisabled()
    expect(screen.getByRole('button', { name: /verify production s3/i })).not.toBeDisabled()
  })

  it('hides destination management from members', () => {
    authState.role = 'member'
    renderWithClient(<BackupDestinationsTab />)

    expect(screen.queryByRole('button', { name: /add destination/i })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /verify production s3/i })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /delete destination/i })).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: /use production s3 by default/i })).toBeDisabled()
  })

  it('explains the refusal when a destination still holds backups', async () => {
    deleteMutateAsync.mockRejectedValueOnce(new Error('Production S3 still holds 2 backups. Remove or move them before deleting the destination.'))
    renderWithClient(<BackupDestinationsTab />)

    fireEvent.click(screen.getByRole('button', { name: /delete destination production s3/i }))
    expect(screen.getByText(/cannot be deleted/i)).toBeInTheDocument()
    expect(screen.queryByText(/you can still restore/i)).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /^delete destination$/i }))

    await waitFor(() => {
      expect(screen.getByText(/still holds 2 backups/i)).toBeInTheDocument()
    })
  })

  it('adapts the endpoint field to the provider', () => {
    renderWithClient(<BackupDestinationsTab />)
    fireEvent.click(screen.getByRole('button', { name: /add destination/i }))

    expect(screen.getByLabelText(/endpoint \(optional for aws s3\)/i)).toBeInTheDocument()
    expect(screen.getByTestId('provider-hint')).toHaveTextContent(/IAM user/)
  })
})
