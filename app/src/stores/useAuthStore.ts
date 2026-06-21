import { create } from 'zustand'
import { persist } from 'zustand/middleware'

export interface AuthOrganization {
  id: string
  name: string
  slug: string
  role?: 'owner' | 'admin' | 'member'
  memberCount?: number
}

export interface AuthUser {
  id: number
  email: string
  name: string
  admin?: boolean
  organizations?: AuthOrganization[]
}

interface AuthState {
  token: string | null
  user: AuthUser | null
  currentOrganizationId: string | null
  isLoading: boolean
  setToken: (token: string | null) => void
  setUser: (user: AuthUser | null) => void
  setCurrentOrganizationId: (id: string | null) => void
  setLoading: (loading: boolean) => void
  logout: () => void
  isAuthenticated: () => boolean
  currentOrganization: () => AuthOrganization | null
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
      logout: () => set({ token: null, user: null, currentOrganizationId: null, isLoading: false }),
      isAuthenticated: () => !!get().token,
      currentOrganization: () => {
        const state = get()
        if (!state.currentOrganizationId || !state.user) return null
        return state.user.organizations?.find((o) => o.id === state.currentOrganizationId) ?? null
      },
    }),
    { name: 'raildock-auth' }
  )
)