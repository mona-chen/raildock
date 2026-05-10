import { memo, useState, useRef, useEffect } from 'react'
import { Box, Globe, Database, Zap, MessageSquare, Search, HardDrive, Link2, Unlink, X } from 'lucide-react'
import type { Service } from '@/types'

const SVC_ICON: Record<string, React.ElementType> = {
  web: Globe,
  worker: Box,
  postgres: Database,
  redis: Zap,
  mysql: Database,
  mongo: Database,
  rabbitmq: MessageSquare,
  clock: Box,
  elasticsearch: Search,
}

const SVC_CLR: Record<string, string> = {
  web: '#22c55e',
  worker: '#3b82f6',
  postgres: '#8b5cf6',
  redis: '#f59e0b',
  mysql: '#3b82f6',
  mongo: '#22c55e',
  rabbitmq: '#f97316',
  clock: '#a855f7',
  elasticsearch: '#3b82f6',
}

interface ServiceCardProps {
  service: Service
  position: { x: number; y: number }
  isSelected: boolean
  onMouseDown: (e: React.MouseEvent) => void
  otherServices?: Service[]
  onLink?: (targetId: string) => void
  onUnlink?: (targetId: string) => void
}

function ServiceCard({ service, position, isSelected, onMouseDown, otherServices, onLink, onUnlink }: ServiceCardProps) {
  const Icon = SVC_ICON[service.subtype] || Box
  const color = SVC_CLR[service.subtype] || '#A0A0B0'
  const isDb = service.type === 'database'
  const [showLinkMenu, setShowLinkMenu] = useState(false)
  const menuRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setShowLinkMenu(false)
      }
    }
    if (showLinkMenu) document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [showLinkMenu])

  const linkable = (otherServices || []).filter(
    (s) => s.id !== service.id && !service.linkedServiceIds.includes(s.id)
  )
  const linked = (otherServices || []).filter((s) => service.linkedServiceIds.includes(s.id))

  return (
    <div
      className={`absolute w-[240px] pointer-events-auto ${isSelected ? 'z-20' : 'z-10'}`}
      style={{ left: position.x, top: position.y, cursor: 'grab' }}
      onMouseDown={onMouseDown}
      data-service-id={service.id}
      role="button"
      aria-label={`${service.name} ${service.type} — ${service.status}`}
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault()
          onMouseDown(e as unknown as React.MouseEvent)
        }
      }}
    >
      <div
        className={`bg-[#16161a] border rounded-xl overflow-hidden transition-all ${
          isSelected ? 'border-[#8b5cf6]/50 shadow-xl shadow-[#8b5cf6]/5' : 'border-white/[0.06]'
        }`}
      >
        <div className="p-4">
          <div className="flex items-center gap-3">
            <div
              className="w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0"
              style={{ backgroundColor: `${color}15` }}
            >
              <Icon size={18} style={{ color }} />
            </div>
            <div className="min-w-0 flex-1">
              <div className="text-[15px] font-semibold text-white truncate">{service.name}</div>
            </div>
            {otherServices && (linkable.length > 0 || linked.length > 0) && (
              <div className="relative" ref={menuRef}>
                <button
                  onClick={(e) => { e.stopPropagation(); setShowLinkMenu(!showLinkMenu) }}
                  className="p-1 rounded hover:bg-white/[0.08] text-white/30 hover:text-white/60 transition-colors"
                  title="Link services"
                >
                  <Link2 size={14} />
                </button>
                {showLinkMenu && (
                  <div className="absolute right-0 top-7 w-44 bg-[#1a1a1e] border border-white/[0.08] rounded-xl shadow-xl shadow-black/40 py-1.5 z-50">
                    {linked.length > 0 && (
                      <>
                        <div className="px-3 py-1 text-[10px] text-white/30 uppercase tracking-wider">Linked</div>
                        {linked.map((s) => (
                          <button
                            key={s.id}
                            onClick={(e) => { e.stopPropagation(); onUnlink?.(s.id); setShowLinkMenu(false) }}
                            className="w-full px-3 py-1.5 flex items-center gap-2 hover:bg-white/[0.04] text-left"
                          >
                            <Unlink size={11} className="text-red-400/60" />
                            <span className="text-[12px] text-white/60 truncate">{s.name}</span>
                          </button>
                        ))}
                      </>
                    )}
                    {linkable.length > 0 && linked.length > 0 && <div className="my-1 border-t border-white/[0.06]" />}
                    {linkable.length > 0 && (
                      <>
                        <div className="px-3 py-1 text-[10px] text-white/30 uppercase tracking-wider">Link to</div>
                        {linkable.map((s) => (
                          <button
                            key={s.id}
                            onClick={(e) => { e.stopPropagation(); onLink?.(s.id); setShowLinkMenu(false) }}
                            className="w-full px-3 py-1.5 flex items-center gap-2 hover:bg-white/[0.04] text-left"
                          >
                            <Link2 size={11} className="text-[#8b5cf6]/60" />
                            <span className="text-[12px] text-white/60 truncate">{s.name}</span>
                          </button>
                        ))}
                      </>
                    )}
                    {linkable.length === 0 && linked.length === 0 && (
                      <div className="px-3 py-2 text-[12px] text-white/30">No other services</div>
                    )}
                  </div>
                )}
              </div>
            )}
          </div>
          <div className="flex items-center gap-2 mt-3">
            <div
              className="w-2 h-2 rounded-full"
              style={{
                backgroundColor: service.status === 'running' ? '#22c55e' : '#4A4A55',
              }}
            />
            <span className="text-[12px] text-white/60">
              {service.status === 'running' ? 'Online' : service.status}
            </span>
          </div>
        </div>
      </div>
      {isDb && (
        <div className="mt-1.5 ml-3 mr-3">
          <div className="flex items-center gap-2 px-3 py-2 bg-[#16161a]/70 border border-white/[0.04] rounded-lg">
            <HardDrive size={11} className="text-white/25" />
            <span className="text-[11px] text-white/35 font-mono">{service.name}-volume</span>
          </div>
        </div>
      )}
    </div>
  )
}

export default memo(ServiceCard)
