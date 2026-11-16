import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { beforeEach, expect, it, vi } from 'vitest'
import HttpTrafficPanel from '@/features/servers/HttpTrafficPanel'
const { traffic, discover, setup } = vi.hoisted(() => ({traffic: vi.fn(), discover: vi.fn(), setup: vi.fn()}))
vi.mock('@/lib/api', () => ({observabilityApi: {traffic, discoverTraffic: discover, setupTraffic: setup, saveTraffic: vi.fn()}}))
beforeEach(() => { vi.clearAllMocks() })
const response = (overrides = {}) => ({ settings: {enabled: true, format: 'traefik', retentionDays: 7, capturePaths: false, managedLogging: true, setupState: 'completed'}, collection: {checkedAt: new Date().toISOString()}, summary: {requests: 12, bandwidth: 2048, statuses: {'2xx': 12}, paths: []}, samples: [], coverage: 'complete', ...overrides })
const renderPanel = () => render(<QueryClientProvider client={new QueryClient()}><HttpTrafficPanel serverId="1"/></QueryClientProvider>)
it('lets an automatically configured server reopen the reviewed setup to change path retention', async () => {
  traffic.mockResolvedValue(response())
  discover.mockResolvedValue({candidates: [{container: 'matrix-traefik', image: 'traefik:v3', canManage: true, reviewToken: 'reviewed-source'}]})
  renderPanel()
  fireEvent.click(await screen.findByRole('button', {name: 'Collection settings'}))
  expect(screen.getByText('Not collected')).toBeInTheDocument()
  fireEvent.click(screen.getByRole('button', {name: 'Review setup'}))
  expect(await screen.findByRole('heading', {name: 'Change HTTP analytics logging'})).toBeInTheDocument()
  fireEvent.click(screen.getByRole('button', {name: 'Set up HTTP analytics'}))
  await waitFor(() => expect(discover).toHaveBeenCalledWith('1', false))
  fireEvent.click(screen.getByRole('switch', {name: 'Retain normalized request paths'}))
  await waitFor(() => expect(discover).toHaveBeenLastCalledWith('1', true))
  fireEvent.click(screen.getByRole('button', {name: 'Close'}))
  expect(screen.queryByRole('heading', {name: 'Change HTTP analytics logging'})).not.toBeInTheDocument()
})
