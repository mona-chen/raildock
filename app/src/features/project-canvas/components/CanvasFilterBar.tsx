import { Search, Plus } from 'lucide-react'
import { useCanvasStore } from '@/stores/useCanvasStore'

interface CanvasFilterBarProps {
  onAddService: () => void
}

const filters = [
  { key: 'all' as const, label: 'All' },
  { key: 'app' as const, label: 'Apps' },
  { key: 'database' as const, label: 'Databases' },
  { key: 'cache' as const, label: 'Caches' },
  { key: 'service' as const, label: 'Services' },
] as const

export default function CanvasFilterBar({ onAddService }: CanvasFilterBarProps) {
  const filter = useCanvasStore((s) => s.filter)
  const setFilter = useCanvasStore((s) => s.setFilter)
  const searchQuery = useCanvasStore((s) => s.searchQuery)
  const setSearchQuery = useCanvasStore((s) => s.setSearchQuery)

  return (
    <div className="absolute top-3 left-4 right-4 flex items-center justify-between z-30 pointer-events-none">
      <div className="flex items-center gap-2 pointer-events-auto" onMouseDown={(e) => e.stopPropagation()}>
        <div className="flex items-center bg-[#16161a] border border-white/[0.08] rounded-lg px-2.5 py-1.5 gap-2">
          <Search size={13} className="text-white/30" />
          <input
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Filter services..."
            className="bg-transparent text-[12px] text-white/70 placeholder-white/30 outline-none w-32"
          />
        </div>
        <div className="flex items-center bg-[#16161a] border border-white/[0.08] rounded-lg overflow-hidden">
          {filters.map((f) => (
            <button
              key={f.key}
              onClick={() => setFilter(f.key)}
              className={`px-2.5 py-1.5 text-[11px] transition-all ${
                filter === f.key
                  ? 'bg-white/[0.08] text-white/80'
                  : 'text-white/40 hover:text-white/60'
              }`}
            >
              {f.label}
            </button>
          ))}
        </div>
      </div>

      <button
        onClick={onAddService}
        onMouseDown={(e) => e.stopPropagation()}
        className="pointer-events-auto flex items-center gap-1.5 px-3 py-2 bg-[#16161a] border border-white/[0.08] text-white/60 text-[12px] rounded-lg hover:border-[#8b5cf6]/40 hover:text-white transition-all"
      >
        <Plus size={14} /> Add
      </button>
    </div>
  )
}
