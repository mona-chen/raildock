import { create } from 'zustand'

interface CanvasState {
  zoom: number
  pan: { x: number; y: number }
  activeServiceId: string | null
  filter: 'all' | 'app' | 'database' | 'cache' | 'queue' | 'search' | 'service'
  searchQuery: string

  setZoom: (zoom: number | ((prev: number) => number)) => void
  setPan: (pan: { x: number; y: number }) => void
  setActiveService: (id: string | null) => void
  setFilter: (filter: CanvasState['filter']) => void
  setSearchQuery: (query: string) => void
  resetView: () => void
}

export const useCanvasStore = create<CanvasState>((set) => ({
  zoom: 1,
  pan: { x: 0, y: 0 },
  activeServiceId: null,
  filter: 'all',
  searchQuery: '',

  setZoom: (zoom) => set((state) => ({ zoom: Math.max(0.3, Math.min(2, typeof zoom === 'function' ? (zoom as (prev: number) => number)(state.zoom) : zoom)) })),
  setPan: (pan) => set({ pan }),
  setActiveService: (id) => set({ activeServiceId: id }),
  setFilter: (filter) => set({ filter }),
  setSearchQuery: (query) => set({ searchQuery: query }),
  resetView: () => set({ zoom: 1, pan: { x: 0, y: 0 } }),
}))
