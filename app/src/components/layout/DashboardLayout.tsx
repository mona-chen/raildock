import { Outlet } from 'react-router-dom'
import IconRail from './IconRail'

export default function DashboardLayout() {
  return (
    <div className="h-screen flex bg-[#0B0B0D] text-[#F0F1F3]">
      {/* Icon Rail — always visible in dashboard */}
      <IconRail />

      {/* Main Content */}
      <main className="flex-1 overflow-hidden">
        <Outlet />
      </main>
    </div>
  )
}
