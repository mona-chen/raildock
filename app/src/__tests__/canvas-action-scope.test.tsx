import { render, screen, fireEvent } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { it, expect, vi } from 'vitest'
import CanvasToolbar from '@/features/project-canvas/components/CanvasToolbar'
const { deploy } = vi.hoisted(() => ({ deploy: vi.fn() }))
vi.mock('@/hooks/useProjects', () => ({
  useDeployAllServices: () => ({ mutate: deploy, isPending: false }),
  useCancelProjectDeployments: () => ({ mutate: vi.fn(), isPending: false }),
  useRestartAllServices: () => ({ mutate: vi.fn(), isPending: false }),
  useStopAllServices: () => ({ mutate: vi.fn(), isPending: false }),
}))
vi.mock('@/features/project-canvas/components/EnvironmentSwitcher', () => ({ default: () => <span>staging</span> }))
vi.mock('@/features/project-canvas/components/ProjectNavigator', () => ({ default: () => <span>shop</span> }))

it('reviews the environment and affected count before dispatching a bulk action', async () => {
  render(<MemoryRouter><CanvasToolbar projectId="1" projectName="shop" projectEnvironment="production" activeEnvironmentId="2" environments={[{ id: '2', name: 'staging', slug: 'staging', isDefault: false, serviceCount: 3 }]} serviceCount={3} appCount={2} connectionState="live" /></MemoryRouter>)
  fireEvent.pointerDown(screen.getByRole('button', { name: /staging actions/ }), { button: 0, ctrlKey: false, pointerType: 'mouse' })
  fireEvent.click(await screen.findByRole('menuitem', { name: 'Deploy All Apps' }))
  expect(deploy).not.toHaveBeenCalled()
  expect(screen.getByText(/This affects 2 apps in shop \/ staging/)).toBeInTheDocument()
  fireEvent.click(screen.getByRole('button', { name: 'Deploy apps' }))
  expect(deploy).toHaveBeenCalledWith({ projectId: '1', environmentId: '2' })
})
