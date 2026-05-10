import { LayoutDashboard, Folder, Server, Settings, Boxes, LogOut, User, Activity } from 'lucide-react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { useAuthStore } from '@/stores/useAuthStore'

const NAV_ITEMS = [
  { icon: LayoutDashboard, label: 'Dashboard', path: '/dashboard' },
  { icon: Folder, label: 'Projects', path: '/dashboard/projects' },
  { icon: Server, label: 'Servers', path: '/dashboard/servers' },
  { icon: Activity, label: 'Activity', path: '/dashboard/activity' },
  { icon: Settings, label: 'Settings', path: '/dashboard/settings' },
]

export default function IconRail() {
  const location = useLocation()
  const navigate = useNavigate()
  const { user, logout } = useAuthStore()

  const handleLogout = () => {
    logout()
    navigate('/login')
  }

  return (
    <div className="w-14 bg-[#0B0B0D] border-r border-[rgba(255,255,255,0.06)] flex flex-col items-center py-3 flex-shrink-0 z-30">
      {/* Logo */}
      <Link to="/" className="mb-6">
        <div className="w-8 h-8 rounded-lg bg-rail-purple flex items-center justify-center">
          <Boxes size={18} className="text-white" />
        </div>
      </Link>

      {/* Nav Items */}
      <nav className="flex flex-col gap-1 flex-1">
        {NAV_ITEMS.map(item => {
          const isActive = location.pathname.startsWith(item.path)
          return (
            <Link key={item.path} to={item.path} title={item.label} className={`relative w-10 h-10 rounded-xl flex items-center justify-center transition-all ${isActive ? 'bg-[rgba(139,92,246,0.12)] text-rail-purple' : 'text-[#4A4A55] hover:text-[#A0A0B0] hover:bg-[rgba(255,255,255,0.04)]'}`}>
              <item.icon size={18} />
              {isActive && <div className="absolute left-0 top-1/2 -translate-y-1/2 w-0.5 h-5 bg-rail-purple rounded-r-full" />}
            </Link>
          )
        })}
      </nav>

      {/* User + Logout */}
      <div className="flex flex-col items-center gap-2 mt-auto pt-3 border-t border-[rgba(255,255,255,0.06)] w-10">
        <div className="w-8 h-8 rounded-full bg-[rgba(139,92,246,0.15)] border border-[rgba(139,92,246,0.25)] flex items-center justify-center" title={user?.name || 'User'}>
          <User size={14} className="text-rail-purple" />
        </div>
        <button
          onClick={handleLogout}
          className="w-8 h-8 rounded-lg flex items-center justify-center text-[#4A4A55] hover:text-red-400 hover:bg-red-500/10 transition-all"
          title="Sign out"
        >
          <LogOut size={15} />
        </button>
      </div>
    </div>
  )
}
