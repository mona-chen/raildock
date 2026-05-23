import { memo, useState, useRef, useEffect, useCallback } from 'react'
import { Box, HardDrive, Link2, Unlink, X, Lock, Wrench } from 'lucide-react'
import { ServiceIcon, getServiceColor } from '@/components/icons/ServiceIcons'
import type { Service } from '@/types'

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
  const color = getServiceColor(service.subtype)
  const isDb = service.type === 'database'
  const [showLinkMenu, setShowLinkMenu] = useState(false)
  const menuRef = useRef<HTMLDivElement>(null)
  const buttonRef = useRef<HTMLButtonElement>(null)
  const [menuPos, setMenuPos] = useState<{ top: number; left: number } | null>(null)

  const openMenu = useCallback(() => {
    const btn = buttonRef.current
    if (!btn) return
    const rect = btn.getBoundingClientRect()
    const menuWidth = 180
    // Position menu to the left of the button if near right edge
    const left = Math.min(rect.left, window.innerWidth - menuWidth - 8)
    const top = rect.bottom + 4
    setMenuPos({ top, left })
    setShowLinkMenu(true)
  }, [])

  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node) &&
          buttonRef.current && !buttonRef.current.contains(e.target as Node)) {
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
          // Programmatically create a mouse event at the card center to open the panel
          const rect = (e.currentTarget as HTMLElement).getBoundingClientRect()
          const syntheticEvent = new MouseEvent('mousedown', {
            bubbles: true,
            clientX: rect.left + rect.width / 2,
            clientY: rect.top + rect.height / 2,
          })
          e.currentTarget.dispatchEvent(syntheticEvent)
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
              <ServiceIcon subtype={service.subtype} size={18} />
            </div>
            <div className="min-w-0 flex-1">
              <div className="text-[15px] font-semibold text-white truncate">{service.name}</div>
            </div>
            {otherServices && (linkable.length > 0 || linked.length > 0) && (
              <div className="relative">
                <button
                  ref={buttonRef}
                  onMouseDown={(e) => e.stopPropagation()}
                  onClick={(e) => { e.stopPropagation(); showLinkMenu ? setShowLinkMenu(false) : openMenu() }}
                  className="p-1 rounded hover:bg-white/[0.08] text-white/30 hover:text-white/60 transition-colors"
                  title="Link services"
                  type="button"
                >
                  <Link2 size={14} />
                </button>
                {showLinkMenu && menuPos && (
                  <div
                    className="fixed w-44 bg-[#1a1a1e] border border-white/[0.08] rounded-xl shadow-xl shadow-black/40 py-1.5 z-50"
                    style={{ top: menuPos.top, left: menuPos.left }}
                    ref={menuRef}
                  >
                    {linked.length > 0 && (
                      <>
                        <div className="px-3 py-1 text-[10px] text-white/30 uppercase tracking-wider">Linked</div>
                        {linked.map((s) => (
                          <button
                            key={s.id}
                            onMouseDown={(e) => e.stopPropagation()}
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
                            onMouseDown={(e) => e.stopPropagation()}
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
                backgroundColor:
                  service.status === 'running' ? '#22c55e' :
                  service.status === 'error' ? '#ef4444' :
                  service.status === 'building' ? '#eab308' :
                  service.status === 'deploying' ? '#8b5cf6' :
                  service.status === 'stopped' ? '#f97316' :
                  '#4A4A55',
              }}
            />
            <span className="text-[12px] text-white/60">
              {service.status === 'running' ? 'Online' :
               service.status === 'error' ? 'Error' :
               service.status === 'building' ? 'Building' :
               service.status === 'deploying' ? 'Deploying' :
               service.status === 'stopped' ? 'Stopped' :
               service.status}
            </span>
            {(service as Service & { locked?: boolean }).locked && (
              <span title="App locked"><Lock size={11} className="text-amber-400/60" /></span>
            )}
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
