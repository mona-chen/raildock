import { create } from 'zustand'

interface UIState {
  sidebarCollapsed: boolean
  theme: 'dark' | 'light' | 'system'
  toastQueue: { id: string; message: string; type: 'success' | 'error' | 'info' }[]

  toggleSidebar: () => void
  setTheme: (theme: UIState['theme']) => void
  addToast: (toast: Omit<UIState['toastQueue'][0], 'id'>) => void
  removeToast: (id: string) => void
}

export const useUIStore = create<UIState>((set) => ({
  sidebarCollapsed: false,
  theme: 'dark',
  toastQueue: [],

  toggleSidebar: () => set((state) => ({ sidebarCollapsed: !state.sidebarCollapsed })),
  setTheme: (theme) => set({ theme }),
  addToast: (toast) =>
    set((state) => ({
      toastQueue: [...state.toastQueue, { ...toast, id: `toast-${Date.now()}` }],
    })),
  removeToast: (id) =>
    set((state) => ({
      toastQueue: state.toastQueue.filter((t) => t.id !== id),
    })),
}))
