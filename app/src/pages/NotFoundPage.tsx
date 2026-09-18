import { Link, useLocation, useNavigate } from 'react-router-dom'
import { Compass } from 'lucide-react'

export default function NotFoundPage() {
  const location = useLocation()
  const navigate = useNavigate()

  return (
    <div className="min-h-screen bg-[#0B0B0D] text-[#F0F1F3] flex items-center justify-center p-8">
      <div className="text-center max-w-md">
        <div className="w-14 h-14 mx-auto rounded-2xl bg-white/[0.04] border border-white/[0.06] flex items-center justify-center mb-5">
          <Compass size={26} className="text-rail-purple" />
        </div>
        <h1 className="text-[20px] font-semibold text-white/90 mb-2">Page not found</h1>
        <p className="text-[13px] text-white/50 mb-6">
          Nothing lives at <span className="font-mono text-white/60">{location.pathname}</span>. It may have been moved or deleted.
        </p>
        <div className="flex items-center justify-center gap-2">
          <Link
            to="/dashboard/projects"
            className="px-4 py-2 bg-rail-purple text-white text-[13px] font-medium rounded-lg hover:bg-rail-purple-dark transition-colors"
          >
            Back to projects
          </Link>
          <button
            onClick={() => navigate(-1)}
            className="px-4 py-2 bg-white/[0.06] text-white/70 text-[13px] rounded-lg hover:bg-white/[0.1] transition-colors"
          >
            Go back
          </button>
        </div>
      </div>
    </div>
  )
}
