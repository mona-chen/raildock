import { Search, Plus, X } from 'lucide-react'
import { useCanvasStore } from '@/stores/useCanvasStore'
import type { Service } from '@/types'

interface CanvasFilterBarProps {
  onAddService: () => void
  services?: Service[]
}

const filters = [
  { key: 'all', label: 'All' },
  { key: 'app', label: 'Apps' },
  { key: 'database', label: 'Databases' },
  { key: 'cache', label: 'Caches' },
  { key: 'queue', label: 'Queues' },
  { key: 'search', label: 'Search' },
  { key: 'service', label: 'Services' },
] as const

export default function CanvasFilterBar({ onAddService, services = [] }: CanvasFilterBarProps) {
  const { filter, setFilter, searchQuery, setSearchQuery } = useCanvasStore()
  return (
    <div className="absolute top-4 left-5 right-5 z-30 flex flex-wrap items-start justify-between gap-3 pointer-events-none">
      <div className="pointer-events-auto flex max-w-full flex-wrap items-center gap-2" onMouseDown={(event) => event.stopPropagation()}>
        <label className="flex h-10 items-center gap-2 rounded-xl border border-white/[0.1] bg-[#18181e]/95 px-3 shadow-lg focus-within:border-violet-400/60">
          <Search size={15} className="shrink-0 text-[#a0a0b0]" />
          <input aria-label="Find a service" value={searchQuery} onChange={(event) => setSearchQuery(event.target.value)} placeholder="Find a service…" className="w-32 bg-transparent text-xs text-white outline-none sm:w-40" />
          {searchQuery && <button type="button" onClick={() => setSearchQuery('')} aria-label="Clear service search" className="text-[#a0a0b0] hover:text-white"><X size={14} /></button>}
        </label>
        <div className="flex max-w-full items-center overflow-x-auto rounded-xl border border-white/[0.1] bg-[#18181e]/95 p-1 shadow-lg" aria-label="Service type filters">
          {filters.map((item) => {
            const count = item.key === 'all' ? services.length : services.filter((service) => service.type === item.key).length
            if (item.key !== 'all' && count === 0 && filter !== item.key) return null
            return <button type="button" key={item.key} aria-pressed={filter === item.key} onClick={() => setFilter(item.key)} className={`flex items-center gap-1.5 whitespace-nowrap rounded-lg px-3 py-1.5 text-xs transition-colors ${filter === item.key ? 'bg-white/[0.1] text-white' : 'text-[#a0a0b0] hover:bg-white/[0.04] hover:text-white'}`}>{item.label}<span className="text-[10px] text-[#9393a5]">{count}</span></button>
          })}
        </div>
      </div>
      <button type="button" onClick={onAddService} onMouseDown={(event) => event.stopPropagation()} className="pointer-events-auto btn-primary h-10 shadow-lg"><Plus size={16} /> New service</button>
    </div>
  )
}
