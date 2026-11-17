import { beforeEach, expect, it, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import ProjectsPage from '@/pages/ProjectsPage'
import CanvasFilterBar from '@/features/project-canvas/components/CanvasFilterBar'
import CanvasControls from '@/features/project-canvas/components/CanvasControls'
import { useCanvasStore } from '@/stores/useCanvasStore'
import type { Service } from '@/types'

const { create, projects } = vi.hoisted(() => ({ create: vi.fn(), projects: [
  { id: '1', name: 'Orbit', description: 'Customer app', createdAt: '2026-11-14', serviceCounts: { total: 2, app: 1, database: 1, cache: 0 } },
  { id: '2', name: 'Atlas', description: 'Mobile API', createdAt: '2026-11-13', serviceCounts: { total: 0, app: 0, database: 0, cache: 0 } },
] }))
vi.mock('@/hooks/useProjects', () => ({ useProjects: () => ({ data: projects }), useCreateProject: () => ({ mutate: create }), useDestroyProject: () => ({ mutateAsync: vi.fn() }) }))
vi.mock('@/components/OnboardingChecklist', () => ({ default: () => null }))
beforeEach(() => { vi.clearAllMocks(); useCanvasStore.setState({ filter: 'all', searchQuery: '' }) })

it('requires a project name, creates on Enter, and opens its canvas', async () => {
  const user = userEvent.setup()
  create.mockImplementation((data, options) => options.onSuccess({ id: 'new-project', ...data }))
  render(<MemoryRouter><Routes><Route path="/" element={<ProjectsPage />} /><Route path="/dashboard/project/new-project" element={<p>New project canvas</p>} /></Routes></MemoryRouter>)
  await user.click(screen.getByRole('button', { name: 'New Project' }))
  expect(screen.getByRole('button', { name: 'Create Project' })).toBeDisabled()
  await user.type(screen.getByLabelText('Project Name'), '  Launch  {Enter}')
  expect(create).toHaveBeenCalledWith(expect.objectContaining({ name: 'Launch' }), expect.anything())
  expect(screen.getByText('New project canvas')).toBeInTheDocument()
})

it('restores keyboard focus after dismissing project creation', async () => {
  const user = userEvent.setup()
  render(<MemoryRouter><ProjectsPage /></MemoryRouter>)
  const trigger = screen.getByRole('button', { name: 'New Project' })
  await user.click(trigger)
  expect(screen.getByLabelText('Project Name')).toHaveFocus()
  await user.keyboard('{Escape}')
  await waitFor(() => expect(trigger).toHaveFocus())
})

it('filters projects and provides a way back from no results', async () => {
  const user = userEvent.setup()
  render(<MemoryRouter><ProjectsPage /></MemoryRouter>)
  await user.type(screen.getByLabelText('Search projects'), 'missing')
  expect(screen.getByText('No matching projects')).toBeInTheDocument()
  await user.click(screen.getByRole('button', { name: 'Clear search' }))
  expect(screen.getByRole('heading', { name: 'Orbit' })).toBeInTheDocument()
})

it('exposes only available service categories with counts and clearable search', async () => {
  const user = userEvent.setup()
  const services = [{type:'app'}, {type:'app'}, {type:'queue'}] as Service[]
  render(<CanvasFilterBar services={services} onAddService={vi.fn()} />)
  expect(screen.queryByRole('button', { name: /Databases/ })).not.toBeInTheDocument()
  await user.click(screen.getByRole('button', { name: /Queues\s*1/ }))
  expect(useCanvasStore.getState().filter).toBe('queue')
  await user.type(screen.getByLabelText('Find a service'), 'worker')
  await user.click(screen.getByRole('button', { name: 'Clear service search' }))
  expect(useCanvasStore.getState().searchQuery).toBe('')
})

it('shows zoom limits and only functional canvas controls', () => {
  render(<CanvasControls zoom={0.3} onZoomIn={vi.fn()} onZoomOut={vi.fn()} onLayout={vi.fn()} />)
  expect(screen.getByRole('button', { name: 'Zoom out' })).toBeDisabled()
  expect(screen.queryByRole('button', { name: /undo/i })).not.toBeInTheDocument()
  expect(screen.queryByRole('button', { name: /layers/i })).not.toBeInTheDocument()
})

it('shows deletion progress and prevents duplicate deletion requests', () => {
  const project = projects[0] as typeof projects[number] & { deletionStatus?: string }
  project.deletionStatus = 'running'
  try {
    render(<MemoryRouter><ProjectsPage /></MemoryRouter>)
    expect(screen.getByRole('status')).toHaveTextContent('Deleting project')
    expect(screen.getByTitle('Project deletion is in progress')).toBeDisabled()
  } finally {
    delete project.deletionStatus
  }
})

it('unlocks a project whose deletion stalled so it can be retried', () => {
  const project = projects[0] as typeof projects[number] & { deletionStatus?: string; deletionPending?: boolean }
  Object.assign(project, { deletionStatus: 'running', deletionPending: false })
  try {
    render(<MemoryRouter><ProjectsPage /></MemoryRouter>)
    expect(screen.getByRole('status')).toHaveTextContent('Deletion stalled')
    const card = screen.getByText(/Deletion stalled/).closest('.group') as HTMLElement
    expect(within(card).getByTitle('Delete project')).not.toBeDisabled()
  } finally {
    delete project.deletionStatus
    delete project.deletionPending
  }
})
it('keeps deletion errors visible and offers snapshot retry or explicit data-loss acknowledgement', async () => {
  const user = userEvent.setup()
  const project = projects[0] as typeof projects[number] & { deletionStatus?: string; deletionError?: string; deletionErrorCode?: string }
  Object.assign(project, { deletionStatus: 'failed', deletionError: 'No verified destination', deletionErrorCode: 'snapshot_required' })
  try {
    render(<MemoryRouter><ProjectsPage /></MemoryRouter>)
    expect(screen.getByRole('alert')).toHaveTextContent('No verified destination')
    await user.click(screen.getAllByTitle('Delete project')[0])
    expect(screen.getByRole('button', { name: 'Retry snapshots' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Permanently delete without snapshot' })).toBeDisabled()
  } finally {
    delete project.deletionStatus
    delete project.deletionError
    delete project.deletionErrorCode
  }
})
