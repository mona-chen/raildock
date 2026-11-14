import { act, renderHook, waitFor } from '@testing-library/react'
import { QueryClientProvider } from '@tanstack/react-query'
import { createQueryClient } from '@/lib/queryClient'
import { useProjects, useProject } from '@/hooks/useProjects'
import { useAuthStore } from '@/stores/useAuthStore'
import { vi, it, expect } from 'vitest'
vi.mock('@/lib/api', () => ({ api: { projects: { list: vi.fn(), get: vi.fn() } } }))
import { api } from '@/lib/api'

it('loads a new project list when the selected organization changes', async () => {
  const client = createQueryClient()
  useAuthStore.setState({ currentOrganizationId: 'A' })
  vi.mocked(api.projects.list).mockImplementation(async () => [{ id: useAuthStore.getState().currentOrganizationId }] as never)
  const { result } = renderHook(() => useProjects(), { wrapper: ({ children }) => <QueryClientProvider client={client}>{children}</QueryClientProvider> })
  await waitFor(() => expect(result.current.data?.[0].id).toBe('A'))
  act(() => useAuthStore.getState().setCurrentOrganizationId('B'))
  await waitFor(() => expect(result.current.data?.[0].id).toBe('B'))
  expect(api.projects.list).toHaveBeenCalledTimes(2)
  client.clear()
})


it('keeps the organization project list separate from a project with the same id', async () => {
  const client = createQueryClient()
  useAuthStore.setState({ currentOrganizationId: '1' })
  vi.mocked(api.projects.list).mockResolvedValue([{ id: '1', name: 'Orbit' }] as never)
  vi.mocked(api.projects.get).mockResolvedValue({ id: '1', name: 'Orbit' } as never)
  const { result } = renderHook(() => ({ list: useProjects(), project: useProject('1') }), { wrapper: ({ children }) => <QueryClientProvider client={client}>{children}</QueryClientProvider> })
  await waitFor(() => expect(result.current.list.data?.[0].name).toBe('Orbit'))
  await waitFor(() => expect(result.current.project.data?.name).toBe('Orbit'))
  expect(Array.isArray(result.current.list.data)).toBe(true)
  client.clear()
})
