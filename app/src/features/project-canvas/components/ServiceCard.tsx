import { formatDistanceToNowStrict } from 'date-fns'
import { memo, useState, useRef, useEffect, useCallback } from 'react'
import { Box, HardDrive, Link2, Unlink, X, Lock, Wrench } from 'lucide-react'
import { ServiceIcon, getServiceColor } from '@/components/icons/ServiceIcons'
import { statusMeta } from '@/lib/status'
import type { Service } from '@/types'

interface ServiceCardProps {
  service: Service
  position: { x: number; y: number }
  isSelected: boolean
  onMouseDown: (e: React.MouseEvent) => void
  onActivate?: () => void
  otherServices?: Service[]
  onLink?: (targetId: string) => void
  onUnlink?: (targetId: string) => void
}

function ServiceCard({ service, position, isSelected, onMouseDown, onActivate, otherServices, onLink, onUnlink }: ServiceCardProps) {
  const color = getServiceColor(service.subtype, service.framework, service.dockerImage)
  const status = statusMeta(service.status)
  const deployedAt = service.lastDeployed ? new Date(service.lastDeployed) : null
  const deploymentAge = deployedAt && Number.isFinite(deployedAt.getTime()) ? formatDistanceToNowStrict(deployedAt, { addSuffix: true }) : null
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
        if (e.target !== e.currentTarget) return
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault()
          onActivate?.()
        }
      }}
    >
      <div
        className={`bg-[#19191f] border rounded-xl overflow-hidden transition-all hover:border-violet-400/40 shadow-lg shadow-black/10 ${
          isSelected ? 'border-[#8b5cf6]/50 shadow-xl shadow-[#8b5cf6]/5' : 'border-white/[0.1]'
        }`}
      >
        <div className="p-4">
          <div className="flex items-center gap-3">
            <div
              className="w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0"
              style={{ backgroundColor: `${color}15` }}
            >
              <ServiceIcon subtype={service.subtype} framework={service.framework} dockerImage={service.dockerImage} size={18} />
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
                  className="p-1 rounded hover:bg-white/[0.08] text-white/50 hover:text-white/60 transition-colors"
                  title="Link services"
                  aria-label={`Manage links for ${service.name}`}
                  aria-expanded={showLinkMenu}
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
                        <div className="px-3 py-1 text-[10px] text-white/50 uppercase tracking-wider">Linked</div>
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
                        <div className="px-3 py-1 text-[10px] text-white/50 uppercase tracking-wider">Link to</div>
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
                      <div className="px-3 py-2 text-[12px] text-white/50">No other services</div>
                    )}
                  </div>
                )}
              </div>
            )}
          </div>
          <div className="flex items-center gap-2 mt-3">
            <div
              className="w-2 h-2 rounded-full"
              style={{ backgroundColor: status.color }}
            />
            <span className="text-[12px] text-white/60">
              {service.status === 'running' ? 'Running' : status.label}
              {deploymentAge && <span className="ml-2 truncate text-[10px] text-[#9393a5]" title={deployedAt?.toISOString()}>Deployed {deploymentAge}</span>}
            </span>
            {(service as Service & { locked?: boolean }).locked && (
              <span title="App locked"><Lock size={11} className="text-amber-400/60" /></span>
            )}
          </div>
        </div>
      </div>
      {service.storageMounts?.length > 0 && (
        <div className="mt-1.5 ml-3 mr-3">
          <div className="flex items-center gap-2 px-3 py-2 bg-[#16161a]/70 border border-white/[0.04] rounded-lg">
            <HardDrive size={11} className="text-[#9393a5]" />
            <span className="text-[11px] text-[#9393a5] font-mono">{service.storageMounts.length === 1 ? service.storageMounts[0].containerPath : `${service.storageMounts.length} volumes`}</span>
          </div>
        </div>
      )}
    </div>
  )
}

export default memo(ServiceCard)
