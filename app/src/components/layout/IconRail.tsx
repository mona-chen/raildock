import { useCallback, useEffect, useState } from 'react'
import {
  Folder, Server, Settings, LogOut, User, Activity, ChevronDown, Building2,
  PanelLeftClose, PanelLeftOpen,
} from 'lucide-react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { useAuthStore } from '@/stores/useAuthStore'
import Logo from '@/components/Logo'
import { useOrganizations } from '@/hooks/useOrganizations'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'

const NAV_ITEMS = [
  { icon: Folder, label: 'Projects', path: '/dashboard/projects' },
  { icon: Server, label: 'Servers', path: '/dashboard/servers' },
  { icon: Activity, label: 'Activity', path: '/dashboard/activity' },
  { icon: Settings, label: 'Settings', path: '/dashboard/settings' },
]

const COLLAPSE_KEY = 'raildock:sidebar-collapsed'

/**
 * Primary navigation. Collapsible so the canvas/panel gets the room when you
 * need it, and expanded when you are moving between sections. The collapsed
 * state persists per browser, and below `md` the rail is always icon-only.
 *
 * The project canvas is the one place that needs every pixel, so the rail
 * enters it icon-only. A manual toggle still wins for as long as you stay on the
 * canvas, and the stored preference is left alone — it is what the rail falls
 * back to everywhere else.
 */
export default function IconRail() {
  const location = useLocation()
  const navigate = useNavigate()
  const { user, logout, currentOrganizationId, setCurrentOrganizationId } = useAuthStore()
  const { data: organizations = [] } = useOrganizations()

  const [preferenceCollapsed, setPreferenceCollapsed] = useState(() => {
    try {
      return localStorage.getItem(COLLAPSE_KEY) === '1'
    } catch {
      return false
    }
  })
  // A toggle made on one project's canvas is keyed to that path so it neither
  // leaks into another project nor overwrites the stored preference: opening a
  // canvas always starts icon-only, and everywhere else falls back to what the
  // user chose.
  const [canvasState, setCanvasState] = useState<{ path: string; collapsed: boolean } | null>(null)

  const onCanvas = location.pathname.startsWith('/dashboard/project/')
  const canvasCollapsed = canvasState?.path === location.pathname ? canvasState.collapsed : null
  const collapsed = onCanvas ? canvasCollapsed ?? true : preferenceCollapsed

  const toggle = useCallback(() => {
    if (onCanvas) {
      setCanvasState({ path: location.pathname, collapsed: !(canvasCollapsed ?? true) })
      return
    }

    setPreferenceCollapsed((prev) => {
      const next = !prev
      try {
        localStorage.setItem(COLLAPSE_KEY, next ? '1' : '0')
      } catch {
        /* localStorage can be unavailable (private mode) — not fatal */
      }
      return next
    })
  }, [onCanvas, canvasCollapsed, location.pathname])

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'b') {
        event.preventDefault()
        toggle()
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [toggle])

  const currentOrg = organizations.find((o) => o.id === currentOrganizationId)
  const orgInitial = currentOrg
    ? currentOrg.name.slice(0, 2).toUpperCase()
    : user?.name?.slice(0, 2).toUpperCase() || 'ME'

  const handleLogout = () => {
    logout()
    navigate('/login')
  }

  const width = collapsed ? 'w-16' : 'w-16 md:w-[224px]'
  const label = collapsed ? 'hidden' : 'hidden md:inline'
  const row = collapsed ? 'justify-center px-0' : 'justify-center px-0 md:justify-start md:px-3'

  return (
    <div className={`${width} bg-[#0B0B0D] border-r border-[rgba(255,255,255,0.06)] flex flex-col py-3 px-2 flex-shrink-0 z-30`}>
      <Link to="/" className={`mb-1 flex h-9 items-center gap-2.5 rounded-lg ${row}`} title="RailDock">
        <Logo className="h-7 w-7 flex-shrink-0" />
        <span className={`${label} text-[13px] font-semibold text-white/80`}>RailDock</span>
      </Link>

      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            className={`mb-3 flex items-center gap-2.5 rounded-lg py-1.5 hover:bg-[rgba(255,255,255,0.04)] transition-colors ${row}`}
            title={currentOrg ? currentOrg.name : 'Personal'}
          >
            <span className="relative w-8 h-8 rounded-full bg-[rgba(139,92,246,0.12)] border border-[rgba(139,92,246,0.25)] flex items-center justify-center text-[10px] font-bold text-rail-purple flex-shrink-0">
              {orgInitial}
              <ChevronDown size={10} className="absolute -bottom-0.5 -right-0.5 text-[#6b6b7b] bg-[#0B0B0D] rounded-full" />
            </span>
            <span className={`${collapsed ? 'hidden' : 'hidden md:flex'} flex-col items-start leading-tight min-w-0`}>
              <span className="text-[12px] font-medium text-white/80 truncate max-w-[128px]">
                {currentOrg ? currentOrg.name : 'Personal'}
              </span>
              <span className="text-[10px] text-white/50">{currentOrg ? 'Organization' : 'Personal workspace'}</span>
            </span>
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent side="right" align="start" className="w-56 bg-[#161618] border-[rgba(255,255,255,0.06)] text-[#F0F1F3]">
          <DropdownMenuLabel className="text-[#6b6b7b] text-[10px] uppercase tracking-wider">Workspace</DropdownMenuLabel>
          <DropdownMenuItem
            className={`cursor-pointer text-sm ${!currentOrganizationId ? 'bg-[rgba(139,92,246,0.12)] text-rail-purple' : 'text-[#A0A0B0] hover:text-white hover:bg-[rgba(255,255,255,0.04)]'}`}
            onClick={() => setCurrentOrganizationId(null)}
          >
            <User size={14} className="mr-2" />
            Personal
            {!currentOrganizationId && <span className="ml-auto text-rail-purple">●</span>}
          </DropdownMenuItem>
          {organizations.map((org) => (
            <DropdownMenuItem
              key={org.id}
              className={`cursor-pointer text-sm ${currentOrganizationId === org.id ? 'bg-[rgba(139,92,246,0.12)] text-rail-purple' : 'text-[#A0A0B0] hover:text-white hover:bg-[rgba(255,255,255,0.04)]'}`}
              onClick={() => setCurrentOrganizationId(org.id)}
            >
              <Building2 size={14} className="mr-2" />
              {org.name}
              {currentOrganizationId === org.id && <span className="ml-auto text-rail-purple">●</span>}
            </DropdownMenuItem>
          ))}
          <DropdownMenuSeparator className="bg-[rgba(255,255,255,0.06)]" />
          <DropdownMenuItem
            className="cursor-pointer text-sm text-[#A0A0B0] hover:text-white hover:bg-[rgba(255,255,255,0.04)]"
            onClick={() => navigate('/dashboard/settings?tab=organizations')}
          >
            <Settings size={14} className="mr-2" />
            Manage organizations
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <nav className="flex-1 flex flex-col gap-0.5">
        {NAV_ITEMS.map((item) => {
          const isActive = location.pathname.startsWith(item.path)
          return (
            <Link
              key={item.path}
              to={item.path}
              title={item.label}
              aria-label={item.label}
              aria-current={isActive ? 'page' : undefined}
              className={`relative h-9 rounded-lg flex items-center gap-3 transition-all ${row} ${isActive ? 'bg-[rgba(139,92,246,0.12)] text-rail-purple' : 'text-[#6b6b7b] hover:text-[#A0A0B0] hover:bg-[rgba(255,255,255,0.04)]'}`}
            >
              <item.icon size={17} className="flex-shrink-0" />
              <span className={`${label} text-[12.5px] font-medium`}>{item.label}</span>
              {isActive && <div className="absolute -left-2 top-1/2 -translate-y-1/2 w-0.5 h-5 bg-rail-purple rounded-r-full" />}
            </Link>
          )
        })}
      </nav>

      <div className="mt-2 flex flex-col gap-0.5 border-t border-[rgba(255,255,255,0.06)] pt-2">
        <button
          type="button"
          onClick={toggle}
          title={collapsed ? 'Expand sidebar (⌘B)' : 'Collapse sidebar (⌘B)'}
          aria-label={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
          aria-pressed={collapsed}
          className={`h-9 rounded-lg flex items-center gap-3 text-[#6b6b7b] hover:text-[#A0A0B0] hover:bg-[rgba(255,255,255,0.04)] transition-all ${row}`}
        >
          {collapsed ? <PanelLeftOpen size={16} className="flex-shrink-0" /> : <PanelLeftClose size={16} className="flex-shrink-0" />}
          <span className={`${label} text-[12.5px] font-medium`}>Collapse</span>
        </button>

        <div className={`flex items-center gap-2.5 py-1.5 ${row}`} title={user?.name || 'User'}>
          <span className="w-8 h-8 rounded-full bg-[rgba(139,92,246,0.15)] border border-[rgba(139,92,246,0.25)] flex items-center justify-center flex-shrink-0">
            <User size={14} className="text-rail-purple" />
          </span>
          <span className={`${collapsed ? 'hidden' : 'hidden md:block'} text-[12px] text-white/60 truncate max-w-[128px]`}>{user?.name || 'User'}</span>
        </div>

        <button
          onClick={handleLogout}
          title="Sign out"
          aria-label="Sign out"
          className={`h-9 rounded-lg flex items-center gap-3 text-[#6b6b7b] hover:text-red-400 hover:bg-red-500/10 transition-all ${row}`}
        >
          <LogOut size={15} className="flex-shrink-0" />
          <span className={`${label} text-[12.5px] font-medium`}>Sign out</span>
        </button>
      </div>
    </div>
  )
}
