import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { beforeEach, expect, it, vi } from 'vitest'
import HttpTrafficSetup from '@/features/servers/HttpTrafficSetup'
const { discover, setup, save } = vi.hoisted(() => ({discover: vi.fn(), setup: vi.fn(), save: vi.fn()}))
vi.mock('@/lib/api', () => ({observabilityApi: {discoverTraffic: discover, setupTraffic: setup, saveTraffic: save}}))
beforeEach(() => { vi.clearAllMocks() })
const renderSetup = () => render(<QueryClientProvider client={new QueryClient()}><HttpTrafficSetup serverId="1" settings={{enabled: false, format: 'traefik', retentionDays: 7}} onAdvanced={vi.fn()}/></QueryClientProvider>)
it('requires a review and explicit restart action before changing the proxy', async () => {
  discover.mockResolvedValue({candidates: [{container: 'coolify-proxy', image: 'traefik:v3.6', canManage: true, reviewToken: 'reviewed-source'}]})
  setup.mockResolvedValue({accepted: true})
  renderSetup()
  fireEvent.click(screen.getByRole('button', {name: 'Set up HTTP analytics'}))
  fireEvent.click(await screen.findByRole('button', {name: 'Review setup'}))
  expect(setup).not.toHaveBeenCalled()
  expect(screen.getByText(/Connections may briefly drop/)).toBeInTheDocument()
  fireEvent.click(screen.getByRole('button', {name: 'Enable logging and restart proxy'}))
  await waitFor(() => expect(setup).toHaveBeenCalledWith('1', 'reviewed-source'))
})
it('can connect a discovered log without restarting the proxy', async () => {
  discover.mockResolvedValue({candidates: [{container: 'proxy', image: 'traefik:v3.6', path: '/var/log/proxy/access.log', canManage: false}]})
  save.mockResolvedValue({})
  renderSetup()
  fireEvent.click(screen.getByRole('button', {name: 'Set up HTTP analytics'}))
  fireEvent.click(await screen.findByRole('button', {name: 'Connect existing log'}))
  await waitFor(() => expect(save).toHaveBeenCalledWith('1', expect.objectContaining({enabled: true, path: '/var/log/proxy/access.log'})))
  expect(setup).not.toHaveBeenCalled()
})
