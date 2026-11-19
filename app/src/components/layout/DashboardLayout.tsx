import { Outlet } from 'react-router-dom'
import IconRail from './IconRail'

export default function DashboardLayout() {
  return (
    <div className="h-dvh flex bg-[#0B0B0D] text-[#F0F1F3]">
      {/* Icon Rail — always visible in dashboard */}
      <IconRail />

      {/* Main Content */}
      <a href="#workspace" className="sr-only focus:not-sr-only focus:fixed focus:top-3 focus:left-20 focus:z-100 focus:rounded-lg focus:bg-violet-600 focus:px-4 focus:py-2">Skip to workspace</a>
      <main id="workspace" tabIndex={-1} className="min-w-0 flex-1 overflow-hidden">
        <Outlet />
      </main>
    </div>
  )
}
