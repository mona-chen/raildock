import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { Link, MemoryRouter } from 'react-router-dom'
import IconRail from '@/components/layout/IconRail'

vi.mock('@/hooks/useOrganizations', () => ({
  useOrganizations: () => ({ data: [] }),
}))

vi.mock('@/stores/useAuthStore', () => ({
  useAuthStore: () => ({
    user: { name: 'Demo Admin' },
    logout: vi.fn(),
    currentOrganizationId: '1',
    setCurrentOrganizationId: vi.fn(),
  }),
}))

/** The rail plus in-app links, so a test can really change the route. */
function Harness() {
  return (
    <>
      <IconRail />
      <Link to="/dashboard/project/2">open second project</Link>
      <Link to="/dashboard/projects">leave canvas</Link>
    </>
  )
}

function renderAt(path: string) {
  return render(
    <MemoryRouter initialEntries={[ path ]}>
      <Harness />
    </MemoryRouter>,
  )
}

describe('IconRail', () => {
  beforeEach(() => {
    localStorage.clear()
    vi.clearAllMocks()
  })

  it('starts icon-only on the project canvas', () => {
    renderAt('/dashboard/project/1')

    expect(screen.getByRole('button', { name: 'Expand sidebar' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Collapse sidebar' })).not.toBeInTheDocument()
  })

  it('stays expanded elsewhere', () => {
    renderAt('/dashboard/projects')

    expect(screen.getByRole('button', { name: 'Collapse sidebar' })).toBeInTheDocument()
  })

  it('honours a stored preference outside the canvas', () => {
    localStorage.setItem('raildock:sidebar-collapsed', '1')

    renderAt('/dashboard/servers')

    expect(screen.getByRole('button', { name: 'Expand sidebar' })).toBeInTheDocument()
  })

  it('lets a manual expand on the canvas win without changing the stored preference', () => {
    renderAt('/dashboard/project/1')

    fireEvent.click(screen.getByRole('button', { name: 'Expand sidebar' }))

    expect(screen.getByRole('button', { name: 'Collapse sidebar' })).toBeInTheDocument()
    expect(localStorage.getItem('raildock:sidebar-collapsed')).toBeNull()
  })

  it('starts the next canvas icon-only again, and keeps the stored preference', () => {
    localStorage.setItem('raildock:sidebar-collapsed', '0')
    renderAt('/dashboard/project/1')

    fireEvent.click(screen.getByRole('button', { name: 'Expand sidebar' }))
    expect(screen.getByRole('button', { name: 'Collapse sidebar' })).toBeInTheDocument()

    // Navigating to another project is a different canvas, so the rail re-arms.
    fireEvent.click(screen.getByText('open second project'))

    expect(screen.getByRole('button', { name: 'Expand sidebar' })).toBeInTheDocument()
    expect(localStorage.getItem('raildock:sidebar-collapsed')).toBe('0')
  })

  it('restores the stored preference on leaving the canvas', () => {
    renderAt('/dashboard/project/1')
    expect(screen.getByRole('button', { name: 'Expand sidebar' })).toBeInTheDocument()

    fireEvent.click(screen.getByText('leave canvas'))

    expect(screen.getByRole('button', { name: 'Collapse sidebar' })).toBeInTheDocument()
  })
})
