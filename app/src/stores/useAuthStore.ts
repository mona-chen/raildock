import { create } from 'zustand'
import { persist } from 'zustand/middleware'

interface User {
  id: number
  email: string
  name: string
}

interface AuthState {
  token: string | null
  user: User | null
  currentOrganizationId: string | null
  isLoading: boolean
  setToken: (token: string | null) => void
  setUser: (user: User | null) => void
  setCurrentOrganizationId: (id: string | null) => void
  setLoading: (loading: boolean) => void
  logout: () => void
  isAuthenticated: () => boolean
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      token: null,
      user: null,
      currentOrganizationId: null,
      isLoading: true,
      setToken: (token) => set({ token }),
      setUser: (user) => set({ user }),
      setCurrentOrganizationId: (id) => set({ currentOrganizationId: id }),
      setLoading: (isLoading) => set({ isLoading }),
      logout: () => set({ token: null, user: null, currentOrganizationId: null }),
      isAuthenticated: () => !!get().token,
    }),
    { name: 'raildock-auth' }
  )
)
