import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { expect, it, vi } from 'vitest'
import { UpdatesTab } from '@/pages/SettingsPage'
const { getInfo, apply } = vi.hoisted(() => ({ getInfo: vi.fn(), apply: vi.fn() }))
vi.mock('@/lib/api', () => ({ updateApi: { getInfo, apply, check: vi.fn(), setAutoUpdate: vi.fn() } }))
it('acknowledges scheduling and waits for host verification instead of claiming success', async () => {
  getInfo.mockResolvedValue({ currentVersion:'0.1.0', latestVersion:'0.2.0', canApply:true, updateAvailable:true, applyStrategy:'ssh_to_local' })
  apply.mockResolvedValue({ success:true, message:'Update scheduled on the host' })
  const client = new QueryClient({defaultOptions:{queries:{retry:false}}})
  render(<QueryClientProvider client={client}><UpdatesTab /></QueryClientProvider>)
  const button = await screen.findByRole('button', {name:/Apply Update/i})
  fireEvent.click(button)
  await waitFor(() => expect(apply).toHaveBeenCalledOnce())
  await waitFor(() => expect(screen.getByRole('button', {name:/Updating/i})).toBeDisabled())
  expect(screen.queryByText('Update completed and verified.')).not.toBeInTheDocument()
  client.clear()
})
