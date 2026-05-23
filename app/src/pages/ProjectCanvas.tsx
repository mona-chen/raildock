import { useState, useEffect, useCallback, useRef, useMemo } from 'react'
import { Keyboard } from 'lucide-react'
import { useParams, useNavigate, useLocation } from 'react-router-dom'
import {
  Box, Activity, Settings, Rocket, Plus, Search, FileCode,
} from 'lucide-react'
import { useServices, useUpdateService, useLinkService, useUnlinkService } from '@/hooks/useServices'
import { useProject } from '@/hooks/useProjects'
import { useCanvasStore } from '@/stores/useCanvasStore'
import { toast } from 'sonner'
import type { Service } from '@/types'

import CanvasGrid from '@/features/project-canvas/components/CanvasGrid'
import ServiceCard from '@/features/project-canvas/components/ServiceCard'
import ConnectionLines from '@/features/project-canvas/components/ConnectionLines'
import CanvasControls from '@/features/project-canvas/components/CanvasControls'
import CanvasToolbar from '@/features/project-canvas/components/CanvasToolbar'
import CanvasFilterBar from '@/features/project-canvas/components/CanvasFilterBar'

// ── Sub-views ────────────────────────────────
import { ProjectSettingsView } from './ProjectSubViews'
import ActivityPage from './ActivityPage'

// ── Service Panel (will be extracted in next step) ─
import ServicePanel from './ServicePanel'

// ── Add Service Modal ─────────────────────────
import AddServiceModal from './AddServiceModal'

// ── Manifest Editor ────────────────────────────
import ManifestEditorPage from './ManifestEditorPage'

// ── Helpers ───────────────────────────────────

function autoLayout(services: Service[]) {
  const pos: Record<string, { x: number; y: number }> = {}
  services.forEach((s, i) => {
    pos[s.id] = { x: 100 + (i % 3) * 300, y: 80 + Math.floor(i / 3) * 180 }
  })
  return pos
}

const CLICK_THRESHOLD = 5 // pixels — max movement to count as a click

// ── Main Project Canvas ───────────────────────

export default function ProjectCanvas() {
  const { projectId } = useParams<{ projectId: string }>()
  const navigate = useNavigate()
  const location = useLocation()

  const { data: services = [], isLoading } = useServices(projectId || '')
  const { data: project } = useProject(projectId || '')

  const zoom = useCanvasStore((s) => s.zoom)
  const pan = useCanvasStore((s) => s.pan)
  const activeServiceId = useCanvasStore((s) => s.activeServiceId)
  const filter = useCanvasStore((s) => s.filter)
  const searchQuery = useCanvasStore((s) => s.searchQuery)
  const setZoom = useCanvasStore((s) => s.setZoom)
  const setPan = useCanvasStore((s) => s.setPan)
  const setActiveService = useCanvasStore((s) => s.setActiveService)
  const resetView = useCanvasStore((s) => s.resetView)
  const updateService = useUpdateService()
  const linkService = useLinkService()
  const unlinkService = useUnlinkService()

  const [positions, setPositions] = useState<Record<string, { x: number; y: number }>>(() =>
    autoLayout(services)
  )
  const [dragId, setDragId] = useState<string | null>(null)
  const [isPanning, setIsPanning] = useState(false)
  const [showAdd, setShowAdd] = useState(false)
  const [showHelp, setShowHelp] = useState(false)

  const dragRef = useRef({
    sx: 0, sy: 0,
    ox: 0, oy: 0,
    px: 0, py: 0,
  })

  // Track mouse for drag-vs-click detection
  const lastMouseRef = useRef({ x: 0, y: 0 })
  const clickStartRef = useRef<{ x: number; y: number; id: string | null } | null>(null)

  // Update positions when services change
  useEffect(() => {
    setPositions((prev) => {
      const next: typeof prev = {}
      services.forEach((s) => {
        next[s.id] = prev[s.id] || autoLayout(services)[s.id]
      })
      return next
    })
  }, [services.length])

  // Filtered services
  const visibleServices = useMemo(() => {
    let result = services
    if (filter !== 'all') {
      result = result.filter((s) => s.type === filter)
    }
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase()
      result = result.filter((s) => s.name.toLowerCase().includes(q))
    }
    return result
  }, [services, filter, searchQuery])

  // Connection lines — only between visible services
  const connections = useMemo(() => {
    const visibleIds = new Set(visibleServices.map((s) => s.id))
    return services.flatMap((s) =>
      s.linkedServiceIds
        .map((tid) => {
          if (!visibleIds.has(s.id) || !visibleIds.has(tid)) return null
          const from = positions[s.id]
          const to = positions[tid]
          if (!from || !to) return null
          return { from, to, fromId: s.id, toId: tid }
        })
        .filter(Boolean)
    ) as { from: { x: number; y: number }; to: { x: number; y: number }; fromId: string; toId: string }[]
  }, [services, positions, visibleServices])

  // Drag / click handlers
  const handleNodeMouseDown = useCallback(
    (e: React.MouseEvent, id: string) => {
      e.stopPropagation()
      setDragId(id)
      // Don't open panel yet — wait for mouseup to decide if click or drag
      const p = positions[id]
      dragRef.current = {
        sx: e.clientX,
        sy: e.clientY,
        ox: p.x,
        oy: p.y,
        px: pan.x,
        py: pan.y,
      }
      lastMouseRef.current = { x: e.clientX, y: e.clientY }
      clickStartRef.current = { x: e.clientX, y: e.clientY, id }
    },
    [positions, pan]
  )

  const handleCanvasMouseDown = useCallback(
    (e: React.MouseEvent) => {
      // Middle-click or left-click starts panning
      if (e.button !== 0 && e.button !== 1) return
      if (e.button === 1) e.preventDefault() // Prevent default middle-click scroll
      setIsPanning(true)
      dragRef.current = {
        sx: e.clientX,
        sy: e.clientY,
        ox: 0,
        oy: 0,
        px: pan.x,
        py: pan.y,
      }
      lastMouseRef.current = { x: e.clientX, y: e.clientY }
      clickStartRef.current = { x: e.clientX, y: e.clientY, id: null }
    },
    [pan]
  )

  // Wheel zoom — attached natively with { passive: false } to allow preventDefault
  const canvasRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const el = canvasRef.current
    if (!el) return
    const handleWheel = (e: WheelEvent) => {
      // Don't zoom when scrolling inside the service panel or modals
      const target = e.target as HTMLElement
      const panel = el.querySelector('[data-service-panel]')
      const modal = document.querySelector('[data-modal]')
      if (panel?.contains(target) || modal?.contains(target)) return
      e.preventDefault()
      const rect = el.getBoundingClientRect()
      const delta = e.deltaY > 0 ? -0.1 : 0.1
      setZoom((prev) => {
        const next = Math.max(0.2, Math.min(prev + delta, 3))
        // Cursor-relative zoom: keep the point under cursor fixed
        const mx = (e.clientX - rect.left - pan.x) / prev
        const my = (e.clientY - rect.top - pan.y) / prev
        setPan({
          x: e.clientX - rect.left - mx * next,
          y: e.clientY - rect.top - my * next,
        })
        return next
      })
    }
    el.addEventListener('wheel', handleWheel, { passive: false })
    return () => el.removeEventListener('wheel', handleWheel)
  }, [setZoom, isLoading])

  useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      lastMouseRef.current = { x: e.clientX, y: e.clientY }
      if (dragId) {
        const dx = (e.clientX - dragRef.current.sx) / zoom
        const dy = (e.clientY - dragRef.current.sy) / zoom
        setPositions((prev) => ({
          ...prev,
          [dragId]: {
            x: dragRef.current.ox + dx,
            y: dragRef.current.oy + dy,
          },
        }))
      } else if (isPanning) {
        setPan({
          x: dragRef.current.px + e.clientX - dragRef.current.sx,
          y: dragRef.current.py + e.clientY - dragRef.current.sy,
        })
      }
    }
    const handleMouseUp = () => {
      // Drag-vs-click detection
      if (clickStartRef.current) {
        const dx = lastMouseRef.current.x - clickStartRef.current.x
        const dy = lastMouseRef.current.y - clickStartRef.current.y
        const dist = Math.sqrt(dx * dx + dy * dy)

        if (dist < CLICK_THRESHOLD) {
          if (dragId) {
            // Click on a service card → open panel
            setActiveService(dragId)
          } else if (isPanning) {
            // Click on canvas background → deselect
            setActiveService(null)
          }
        }
      }

      setDragId(null)
      setIsPanning(false)
      clickStartRef.current = null
    }
    window.addEventListener('mousemove', handleMouseMove)
    window.addEventListener('mouseup', handleMouseUp)
    return () => {
      window.removeEventListener('mousemove', handleMouseMove)
      window.removeEventListener('mouseup', handleMouseUp)
    }
  }, [dragId, isPanning, zoom, setPan, setActiveService])

  const handleLayout = useCallback(() => {
    setPositions(autoLayout(services))
    resetView()
  }, [services, resetView])

  const handleFit = useCallback(() => {
    if (visibleServices.length === 0 || !canvasRef.current) {
      resetView()
      return
    }
    // Compute bounding box of all visible cards
    const padding = 80
    const cardW = 240
    const cardH = 120
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
    visibleServices.forEach((s) => {
      const pos = positions[s.id] || { x: 0, y: 0 }
      minX = Math.min(minX, pos.x)
      minY = Math.min(minY, pos.y)
      maxX = Math.max(maxX, pos.x + cardW)
      maxY = Math.max(maxY, pos.y + cardH)
    })
    const contentW = maxX - minX + padding * 2
    const contentH = maxY - minY + padding * 2
    const containerW = canvasRef.current.clientWidth
    const containerH = canvasRef.current.clientHeight
    const nextZoom = Math.min(containerW / contentW, containerH / contentH, 1.5)
    const nextPanX = (containerW - (maxX - minX) * nextZoom) / 2 - minX * nextZoom
    const nextPanY = (containerH - (maxY - minY) * nextZoom) / 2 - minY * nextZoom
    setZoom(nextZoom)
    setPan({ x: nextPanX, y: nextPanY })
  }, [visibleServices, positions, setZoom, setPan, resetView])

  // Keyboard shortcuts
  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return
      if (e.key === 'Escape') {
        setActiveService(null)
        setShowAdd(false)
        setShowHelp(false)
      }
      if (e.key === '?' || (e.key === '/' && e.shiftKey)) {
        e.preventDefault()
        setShowHelp((v) => !v)
      }
      if (e.key === 'd' || e.key === 'D') {
        if (activeServiceId) {
          setShowAdd(false)
          setShowHelp(false)
          // Trigger deploy via programmatic click on the active service's deploy button in the panel
          toast.info('Press D again to deploy — or use the Deploy tab')
        }
      }
      if (e.key === 'n' || e.key === 'N' || e.key === '+') {
        setShowAdd(true)
      }
      if (e.key === 'Delete' || e.key === 'Backspace') {
        if (activeServiceId) {
          setActiveService(null)
        }
      }
      if (e.key === 'ArrowUp') { e.preventDefault(); setPan({ x: pan.x, y: pan.y + 50 }) }
      if (e.key === 'ArrowDown') { e.preventDefault(); setPan({ x: pan.x, y: pan.y - 50 }) }
      if (e.key === 'ArrowLeft') { e.preventDefault(); setPan({ x: pan.x + 50, y: pan.y }) }
      if (e.key === 'ArrowRight') { e.preventDefault(); setPan({ x: pan.x - 50, y: pan.y }) }
      if ((e.metaKey || e.ctrlKey) && (e.key === '=' || e.key === '+')) {
        e.preventDefault()
        setZoom((z) => Math.min(z + 0.2, 3))
      }
      if ((e.metaKey || e.ctrlKey) && e.key === '-') {
        e.preventDefault()
        setZoom((z) => Math.max(z - 0.2, 0.2))
      }
      if ((e.metaKey || e.ctrlKey) && e.key === '0') {
        e.preventDefault()
        resetView()
      }
    }
    window.addEventListener('keydown', handleKey)
    return () => window.removeEventListener('keydown', handleKey)
  }, [activeServiceId, setActiveService, setPan, pan])

  // View routing
  const pathParts = location.pathname.split('/')
  const view = pathParts[4] || 'services'

  const sidebarItems = [
    { key: 'services', label: 'Services', icon: Box },
    { key: 'activity', label: 'Activity', icon: Activity },
    { key: 'manifest', label: 'Manifest', icon: FileCode },
    { key: 'settings', label: 'Settings', icon: Settings },
  ]

  const navTo = (key: string) => {
    setActiveService(null)
    navigate(`/dashboard/project/${projectId}/${key}`)
  }

  if (isLoading) {
    return (
      <div className="h-full flex flex-col bg-[#0f0f13]">
        <div className="h-11 border-b border-white/[0.06] flex-shrink-0" />
        <div className="flex-1 flex items-center justify-center">
          <div className="text-white/30 text-sm">Loading project...</div>
        </div>
      </div>
    )
  }

  return (
    <div className="h-full flex flex-col bg-[#0f0f13]">
      <CanvasToolbar projectName={project?.name || 'Project'} projectEnvironment={project?.environment || 'production'} />

      {/* Top tab bar for project views */}
      <div className="h-9 border-b border-white/[0.06] flex items-center px-2 gap-1 flex-shrink-0 bg-[#0f0f13] overflow-x-auto">
        {sidebarItems.map((item) => (
          <button
            key={item.key}
            onClick={() => navTo(item.key)}
            className={`px-3 py-1 rounded-md text-[12px] flex items-center gap-1.5 transition-all whitespace-nowrap ${
              view === item.key
                ? 'bg-white/[0.08] text-white/70'
                : 'text-white/30 hover:text-white/50 hover:bg-white/[0.04]'
            }`}
          >
            <item.icon size={13} />
            {item.label}
          </button>
        ))}
      </div>

      {/* Main content */}
      <div className="flex-1 relative overflow-hidden">
        {view === 'services' && (
          <div
            ref={canvasRef}
            className="absolute inset-0"
            onMouseDown={handleCanvasMouseDown}
            style={{
              cursor: isPanning ? 'grabbing' : dragId ? 'grabbing' : 'default',
            }}
            data-cv="1"
          >
            <CanvasGrid zoom={zoom} pan={pan} />

            <div
              className="absolute inset-0 pointer-events-none"
              style={{
                transform: `translate(${pan.x}px, ${pan.y}px) scale(${zoom})`,
                transformOrigin: '0 0',
              }}
            >
              <ConnectionLines connections={connections} />

              {visibleServices.map((s) => (
                <ServiceCard
                  key={s.id}
                  service={s}
                  position={positions[s.id] || { x: 100, y: 100 }}
                  isSelected={activeServiceId === s.id}
                  onMouseDown={(e) => handleNodeMouseDown(e, s.id)}
                  otherServices={services}
                  onLink={(targetId) => {
                    // Always store links as app -> database so unlink and linked-by work consistently
                    const target = services.find((sv) => sv.id === targetId)
                    const isAppToDb = s.type === 'app' && (target?.type === 'database' || target?.type === 'cache')
                    const isDbToApp = (s.type === 'database' || s.type === 'cache') && target?.type === 'app'
                    if (isDbToApp) {
                      linkService.mutate({ id: targetId, targetId: s.id })
                    } else {
                      linkService.mutate({ id: s.id, targetId })
                    }
                  }}
                  onUnlink={(targetId) => {
                    const target = services.find((sv) => sv.id === targetId)
                    const isAppToDb = s.type === 'app' && (target?.type === 'database' || target?.type === 'cache')
                    const isDbToApp = (s.type === 'database' || s.type === 'cache') && target?.type === 'app'
                    if (isDbToApp) {
                      unlinkService.mutate({ id: targetId, targetId: s.id })
                    } else {
                      unlinkService.mutate({ id: s.id, targetId })
                    }
                  }}
                />
              ))}
            </div>

            {services.length > 0 && visibleServices.length === 0 && !isLoading && (
              <div className="absolute inset-0 flex items-center justify-center z-10">
                <div className="text-center p-8">
                  <div className="w-16 h-16 rounded-2xl bg-white/[0.03] border border-white/[0.06] flex items-center justify-center mx-auto mb-4">
                    <Search size={28} className="text-white/20" />
                  </div>
                  <h3 className="text-base font-semibold text-white/70 mb-1">No services match</h3>
                  <p className="text-xs text-[#4A4A55] max-w-xs mx-auto mb-5">
                    Try adjusting your filter or search query.
                  </p>
                  <button
                    type="button"
                    onClick={() => { useCanvasStore.getState().setFilter('all'); useCanvasStore.getState().setSearchQuery(''); }}
                    className="inline-flex items-center gap-2 px-4 py-2 bg-white/[0.06] text-white/70 text-sm font-medium rounded-xl hover:bg-white/[0.1] transition-all"
                  >
                    Clear filters
                  </button>
                </div>
              </div>
            )}

            {services.length === 0 && !isLoading && (
              <div className="absolute inset-0 flex items-center justify-center z-10">
                <div className="text-center p-8">
                  <div className="w-16 h-16 rounded-2xl bg-[rgba(139,92,246,0.08)] border border-[rgba(139,92,246,0.12)] flex items-center justify-center mx-auto mb-4">
                    <Rocket size={28} className="text-rail-purple" />
                  </div>
                  <h3 className="text-base font-semibold text-white mb-1">This project is empty</h3>
                  <p className="text-xs text-[#4A4A55] max-w-xs mx-auto mb-5">
                    Projects contain apps, databases, and services. Add your first service to start deploying.
                  </p>
                  <button
                    onClick={() => setShowAdd(true)}
                    className="inline-flex items-center gap-2 px-4 py-2 bg-rail-purple text-white text-sm font-medium rounded-xl hover:bg-rail-purple-dark transition-all"
                  >
                    <Plus size={16} /> Add Service
                  </button>
                </div>
              </div>
            )}

            <CanvasFilterBar onAddService={() => setShowAdd(true)} />

            <CanvasControls
              onZoomIn={() => setZoom(zoom + 0.15)}
              onZoomOut={() => setZoom(zoom - 0.15)}
              onLayout={handleLayout}
              onFit={handleFit}
            />

            {/* Service Panel */}
            {activeServiceId && (
              <ServicePanel
                serviceId={activeServiceId}
                onClose={() => setActiveService(null)}
              />
            )}
          </div>
        )}

        {view === 'activity' && <ActivityPage />}
        {view === 'manifest' && <ManifestEditorPage />}
        {view === 'settings' && <ProjectSettingsView />}
      </div>

      {showAdd && (
        <AddServiceModal
          projectId={projectId!}
          onClose={() => setShowAdd(false)}
        />
      )}

      {showHelp && (
        <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-center justify-center" onClick={() => setShowHelp(false)}>
          <div className="bg-[#18181B] border border-[rgba(255,255,255,0.08)] rounded-2xl p-6 w-[380px]" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-base font-semibold text-white flex items-center gap-2">
                <Keyboard size={16} className="text-rail-purple" /> Keyboard Shortcuts
              </h3>
              <button type="button" onClick={() => setShowHelp(false)} className="text-white/30 hover:text-white/60" aria-label="Close help">
                <span className="text-lg">×</span>
              </button>
            </div>
            <div className="space-y-2">
              {[
                { key: 'N / +', desc: 'Add new service' },
                { key: 'Esc', desc: 'Close panel / modal' },
                { key: '↑ ↓ ← →', desc: 'Pan canvas' },
                { key: 'Scroll', desc: 'Zoom in/out' },
                { key: 'Drag', desc: 'Move service card' },
                { key: 'Click', desc: 'Open service panel' },
                { key: 'Middle-click drag', desc: 'Pan canvas' },
              ].map((item) => (
                <div key={item.key} className="flex items-center justify-between py-1.5 border-b border-white/[0.04] last:border-0">
                  <span className="text-[13px] text-white/60">{item.desc}</span>
                  <kbd className="px-2 py-0.5 bg-white/[0.06] rounded text-[11px] text-white/50 font-mono">{item.key}</kbd>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
