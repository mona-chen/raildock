import { Folder, Server, Settings, LogOut, User, Activity, ChevronDown, Building2 } from 'lucide-react'
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

export default function IconRail() {
  const location = useLocation()
  const navigate = useNavigate()
  const { user, logout, currentOrganizationId, setCurrentOrganizationId } = useAuthStore()
  const { data: organizations = [] } = useOrganizations()

  const currentOrg = organizations.find((o) => o.id === currentOrganizationId)
  const orgInitial = currentOrg
    ? currentOrg.name.slice(0, 2).toUpperCase()
    : user?.name?.slice(0, 2).toUpperCase() || 'ME'

  const handleLogout = () => {
    logout()
    navigate('/login')
  }

  return (
    <div className="w-14 md:w-[188px] bg-[#0B0B0D] border-r border-[rgba(255,255,255,0.06)] flex flex-col py-3 px-2 flex-shrink-0 z-30">
      {/* Logo */}
      <Link to="/" className="mb-2 flex items-center justify-center md:justify-start gap-2.5 px-0 md:px-2" title="RailDock">
        <Logo className="h-8 w-8 flex-shrink-0" />
        <span className="hidden md:inline text-[13px] font-semibold text-white/80">RailDock</span>
      </Link>

      {/* Org Switcher */}
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            className="mb-4 flex items-center justify-center md:justify-start gap-2.5 rounded-lg px-0 md:px-2 py-1.5 hover:bg-[rgba(255,255,255,0.04)] transition-colors"
            title={currentOrg ? currentOrg.name : 'Personal'}
          >
            <span className="relative w-8 h-8 rounded-full bg-[rgba(139,92,246,0.12)] border border-[rgba(139,92,246,0.25)] flex items-center justify-center text-[10px] font-bold text-rail-purple flex-shrink-0">
              {orgInitial}
              <ChevronDown size={10} className="absolute -bottom-0.5 -right-0.5 text-[#6b6b7b] bg-[#0B0B0D] rounded-full" />
            </span>
            <span className="hidden md:flex flex-col items-start leading-tight min-w-0">
              <span className="text-[12px] font-medium text-white/80 truncate max-w-[104px]">
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

      {/* Nav Items */}
      <nav className="flex flex-col gap-1 flex-1">
        {NAV_ITEMS.map(item => {
          const isActive = location.pathname.startsWith(item.path)
          return (
            <Link
              key={item.path}
              to={item.path}
              title={item.label}
              aria-label={item.label}
              aria-current={isActive ? 'page' : undefined}
              className={`relative h-10 rounded-xl flex items-center justify-center md:justify-start gap-3 px-0 md:px-3 transition-all ${isActive ? 'bg-[rgba(139,92,246,0.12)] text-rail-purple' : 'text-[#6b6b7b] hover:text-[#A0A0B0] hover:bg-[rgba(255,255,255,0.04)]'}`}
            >
              <item.icon size={18} className="flex-shrink-0" />
              <span className="hidden md:inline text-[12.5px] font-medium">{item.label}</span>
              {isActive && <div className="absolute -left-2 top-1/2 -translate-y-1/2 w-0.5 h-5 bg-rail-purple rounded-r-full" />}
            </Link>
          )
        })}
      </nav>

      {/* User + Logout */}
      <div className="flex flex-col gap-1 mt-2 pt-3 border-t border-[rgba(255,255,255,0.06)]">
        <div className="flex items-center justify-center md:justify-start gap-2.5 px-0 md:px-2 py-1.5" title={user?.name || 'User'}>
          <span className="w-8 h-8 rounded-full bg-[rgba(139,92,246,0.15)] border border-[rgba(139,92,246,0.25)] flex items-center justify-center flex-shrink-0">
            <User size={14} className="text-rail-purple" />
          </span>
          <span className="hidden md:block text-[12px] text-white/60 truncate max-w-[104px]">{user?.name || 'User'}</span>
        </div>
        <button
          onClick={handleLogout}
          title="Sign out"
          aria-label="Sign out"
          className="h-9 rounded-lg flex items-center justify-center md:justify-start gap-3 px-0 md:px-3 text-[#6b6b7b] hover:text-red-400 hover:bg-red-500/10 transition-all"
        >
          <LogOut size={15} className="flex-shrink-0" />
          <span className="hidden md:inline text-[12.5px] font-medium">Sign out</span>
        </button>
      </div>
    </div>
  )
}
