import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import ProfileTab from '@/features/settings/ProfileTab'
import OrganizationsTab from '@/features/settings/OrganizationsTab'
import { useAuthStore } from '@/stores/useAuthStore'

const { orgState, updateProfileMutate, updateOrganizationMutate, createOrganizationMutate, deleteOrganizationMutate } =
  vi.hoisted(() => ({
    orgState: { organizations: [] as Array<Record<string, unknown>> },
    updateProfileMutate: vi.fn(),
    updateOrganizationMutate: vi.fn(),
    createOrganizationMutate: vi.fn(),
    deleteOrganizationMutate: vi.fn(),
  }))

vi.mock('@/hooks/useProfile', () => ({
  useUpdateProfile: () => ({
    mutate: updateProfileMutate,
    isPending: false,
    error: null,
    reset: vi.fn(),
  }),
}))

vi.mock('@/hooks/useOrganizations', () => ({
  useOrganizations: () => ({ data: orgState.organizations, isLoading: false }),
  useCreateOrganization: () => ({
    mutate: createOrganizationMutate,
    reset: vi.fn(),
    isPending: false,
    error: null,
  }),
  useUpdateOrganization: () => ({
    mutate: updateOrganizationMutate,
    reset: vi.fn(),
    isPending: false,
    error: null,
  }),
  useDeleteOrganization: () => ({
    mutateAsync: deleteOrganizationMutate,
    isPending: false,
  }),
}))

const profileUser = {
  id: 1,
  name: 'Ada Lovelace',
  email: 'ada@example.com',
  admin: false,
  organizations: [
    { id: 'org-1', name: 'Acme', slug: 'acme', role: 'owner' as const, memberCount: 3 },
  ],
}

const ownerOrganization = {
  id: 'org-1',
  name: 'Acme',
  slug: 'acme',
  role: 'owner',
  memberCount: 3,
}

const memberOrganization = {
  ...ownerOrganization,
  role: 'member',
}

beforeEach(() => {
  vi.clearAllMocks()
  orgState.organizations = [ownerOrganization]
  useAuthStore.setState({
    user: profileUser,
    currentOrganizationId: 'org-1',
    token: 'jwt',
  })
})

describe('ProfileTab', () => {
  it('updates the display name and email without a password', () => {
    render(<ProfileTab />)

    fireEvent.change(screen.getByLabelText('Display name'), { target: { value: 'Ada Byron' } })
    fireEvent.click(screen.getByRole('button', { name: /save changes/i }))

    expect(updateProfileMutate).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'Ada Byron', email: 'ada@example.com' }),
      expect.anything()
    )
  })

  it('requires the current password before allowing an email change', () => {
    render(<ProfileTab />)

    fireEvent.change(screen.getByLabelText('Email address'), { target: { value: 'new@example.com' } })

    expect(screen.getByRole('button', { name: /save changes/i })).toBeDisabled()

    fireEvent.change(screen.getByLabelText('Current password'), { target: { value: 'secret' } })

    expect(screen.getByRole('button', { name: /save changes/i })).toBeEnabled()
  })

  it('blocks a password change when the confirmation does not match', () => {
    render(<ProfileTab />)

    fireEvent.change(screen.getByLabelText('Current password'), { target: { value: 'secret' } })
    fireEvent.change(screen.getByLabelText('New password'), { target: { value: 'new-password' } })
    fireEvent.change(screen.getByLabelText('Confirm new password'), { target: { value: 'different' } })

    expect(screen.getByText('New password and confirmation do not match.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /save changes/i })).toBeDisabled()
  })
})

describe('OrganizationsTab', () => {
  it('edits the organization profile through the dialog', () => {
    render(
      <MemoryRouter>
        <OrganizationsTab />
      </MemoryRouter>
    )

    fireEvent.click(screen.getByRole('button', { name: /edit/i }))

    fireEvent.change(screen.getByLabelText('Organization name'), { target: { value: 'Acme Platform' } })
    fireEvent.change(screen.getByLabelText('Slug'), { target: { value: 'acme-platform' } })
    fireEvent.click(screen.getByRole('button', { name: /save changes/i }))

    expect(updateOrganizationMutate).toHaveBeenCalledWith(
      {
        id: ownerOrganization.id,
        data: { name: 'Acme Platform', slug: 'acme-platform', avatarUrl: '' },
      },
      expect.anything()
    )
  })

  it('hides the edit action for a member', () => {
    orgState.organizations = [memberOrganization]

    render(
      <MemoryRouter>
        <OrganizationsTab />
      </MemoryRouter>
    )

    expect(screen.getByText('Member')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /edit/i })).not.toBeInTheDocument()
  })
})
