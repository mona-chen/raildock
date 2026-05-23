import { QueryClient } from '@tanstack/react-query'

// Don't retry on 429 (rate limit) or 401 (unauthorized) —
// retrying 429s makes the problem worse.
function shouldRetry(failureCount: number, error: unknown): boolean {
  if (error instanceof Error) {
    const msg = error.message
    if (msg.includes('429') || msg.includes('401')) {
      return false
    }
  }
  return failureCount < 2
}

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30 * 1000,        // Data stays fresh for 30s
      gcTime: 5 * 60 * 1000,       // Cache for 5 minutes after unmount
      retry: shouldRetry,
      refetchOnWindowFocus: true,
      refetchOnReconnect: true,
    },
    mutations: {
      retry: 1,
    },
  },
})
