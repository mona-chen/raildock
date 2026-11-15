import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { expect, it, vi } from 'vitest'
import ObservabilitySettingsTab from '@/features/settings/ObservabilitySettingsTab'
const { update } = vi.hoisted(() => ({ update: vi.fn() }))
vi.mock('@/stores/useAuthStore', () => ({ useAuthStore: (selector: (s: unknown) => unknown) => selector({ user: { admin: true } }) }))
vi.mock('@/lib/api', () => ({ adminSettingsApi: { list: async () => [], update } }))
it('retains collection and retention changes when saving fails', async () => {
  update.mockRejectedValue(new Error('Offline'))
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  render(<QueryClientProvider client={client}><MemoryRouter><ObservabilitySettingsTab /></MemoryRouter></QueryClientProvider>)
  const toggle = await screen.findByRole('switch', {name:/Host server metrics/})
  fireEvent.click(toggle)
  fireEvent.click(screen.getByLabelText('Metric history retention'))
  fireEvent.click(await screen.findByRole('option',{name:'7 days'}))
  fireEvent.click(screen.getByRole('button',{name:'Save changes'}))
  await waitFor(() => expect(update).toHaveBeenCalledWith(expect.objectContaining({ metrics_hosts_enabled:'false', metrics_retention_days:'7' })))
  expect(toggle).not.toBeChecked()
  expect(screen.getByLabelText('Metric history retention')).toHaveTextContent('7 days')
  client.clear()
})
