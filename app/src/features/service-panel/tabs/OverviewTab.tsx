import { GitBranch, Settings2 } from 'lucide-react'
import { ServiceIcon } from '@/components/icons/ServiceIcons'
import {
  useScaleProcess,
  useContainerStatus,
} from '@/hooks/useServices'
import type { Service } from '@/types'
import ConnectionsCard from './ConnectionsCard'

export default function OverviewTab({
  svc,
  serviceId,
  lastUpdate,
  isConnected,
}: {
  svc: Service
  serviceId: string
  lastUpdate: { message: string; status: string } | null
  isConnected: boolean
}) {
  const scaleProcess = useScaleProcess()
  const { data: containerStatus } = useContainerStatus(serviceId)

  return (
    <div className="p-5 space-y-5">
      {/* Status Card */}
      <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4">
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-3">
            <div
              className="w-10 h-10 rounded-xl flex items-center justify-center"
              style={{ backgroundColor: svc.status === 'running' ? '#22c55e15' : '#4A4A5515' }}
            >
              <ServiceIcon subtype={svc.subtype} framework={svc.framework} dockerImage={svc.dockerImage} size={20} />
            </div>
            <div>
              <div className="text-[14px] font-medium text-white/80">{svc.name}</div>
              <div className="text-[12px] text-white/40">
                {svc.subtype} · {svc.status}
              </div>
            </div>
          </div>
          <span
            className="text-[11px] px-2.5 py-1 rounded-full font-medium"
            style={{
              backgroundColor: svc.status === 'running' ? '#22c55e15' : '#4A4A5515',
              color: svc.status === 'running' ? '#22c55e' : '#8A8A95',
            }}
          >
            {svc.status === 'running' ? 'Online' : svc.status}
          </span>
        </div>

      </div>

      {/* Service Details */}
      <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4">
        <div className="text-[13px] font-medium text-white/70 mb-3">Service Details</div>
        <div className="grid grid-cols-2 gap-2">
          {[
            { l: 'Type', v: svc.subtype },
            { l: 'Version', v: svc.version || 'latest' },
            { l: 'Name', v: svc.name },
            { l: 'Status', v: svc.status },
            { l: 'Internal Hostname', v: svc.internalHostname },
            { l: 'Dokku Name', v: svc.name?.replace(/[^a-z0-9]/gi, '-').toLowerCase() },
          ]
            .filter((f) => f.v)
            .map((f) => (
              <div key={f.l} className="bg-black/20 rounded-lg p-2.5">
                <div className="text-[11px] text-white/40">{f.l}</div>
                <div className="text-[12px] text-white/70 font-mono mt-0.5 break-all">{f.v}</div>
              </div>
            ))}
        </div>
      </div>

      {/* Source Info */}
      {(svc.gitRepo || svc.dockerImage || svc.builder) && (
        <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4 space-y-2">
          <div className="text-[13px] font-medium text-white/70 mb-2">Source</div>
          {svc.gitRepo && (
            <div className="flex items-center gap-2 text-[12px]">
              <GitBranch size={13} className="text-white/30" />
              <span className="text-white/50">{svc.gitRepo}</span>
              <span className="text-white/20">on</span>
              <span className="text-white/50 font-mono">{svc.branch || 'main'}</span>
            </div>
          )}
          {svc.dockerImage && (
            <div className="flex items-center gap-2 text-[12px]">
              <ServiceIcon subtype="docker" size={13} />
              <span className="text-white/40">Image:</span>
              <span className="text-white/60 font-mono">{svc.dockerImage}</span>
            </div>
          )}
          {svc.builder && (
            <div className="flex items-center gap-2 text-[12px]">
              <Settings2 size={13} className="text-white/30" />
              <span className="text-white/40">Builder:</span>
              <span className="text-white/60 capitalize">{svc.builder}</span>
            </div>
          )}
        </div>
      )}

      {/* Processes */}
      {svc.processTypes && svc.processTypes.length > 0 && (
        <div>
          <h4 className="text-[14px] font-medium text-white/70 mb-3">Processes</h4>
          <div className="space-y-2">
            {svc.processTypes.map((pt) => (
              <div
                key={pt.name}
                className="flex items-center justify-between bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3"
              >
                <div>
                  <div className="text-[13px] font-medium text-white/80">{pt.name}</div>
                  <div className="text-[11px] text-white/40 font-mono mt-0.5">
                    {pt.command || 'No command'}
                  </div>
                </div>
                <div className="flex items-center gap-3">
                  <span className="text-[12px] text-white/40">
                    {pt.running}/{pt.quantity} running
                  </span>
                  <div className="flex items-center border border-white/[0.1] rounded-lg overflow-hidden">
                    <button
                      onClick={() =>
                        scaleProcess.mutate({
                          id: svc.id,
                          processName: pt.name,
                          quantity: Math.max(0, pt.quantity - 1),
                        })
                      }
                      className="px-2.5 py-1.5 text-white/40 hover:text-white/70 hover:bg-white/[0.06]"
                    >
                      −
                    </button>
                    <span className="px-3 py-1.5 text-[13px] text-white/70 min-w-[40px] text-center border-x border-white/[0.06]">
                      {pt.quantity}
                    </span>
                    <button
                      onClick={() =>
                        scaleProcess.mutate({
                          id: svc.id,
                          processName: pt.name,
                          quantity: pt.quantity + 1,
                        })
                      }
                      className="px-2.5 py-1.5 text-white/40 hover:text-white/70 hover:bg-white/[0.06]"
                    >
                      +
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Container Status */}
      {containerStatus && (
        <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-lg p-3">
          <div className="flex items-center justify-between">
            <div className="text-[12px] text-white/60">Container Status</div>
            <span
              className={`text-[10px] px-2 py-0.5 rounded-full ${
                containerStatus.status === 'running'
                  ? 'bg-[#22c55e]/10 text-[#22c55e]'
                  : 'bg-white/5 text-white/40'
              }`}
            >
              {containerStatus.status}
            </span>
          </div>
        </div>
      )}

      {/* Last Deployment */}
      {lastUpdate && (
        <div className="bg-[#8b5cf6]/5 border border-[#8b5cf6]/20 rounded-lg p-3 flex items-center gap-2">
          <span
            className={`w-2 h-2 rounded-full ${isConnected ? 'bg-[#22c55e]' : 'bg-white/20'} animate-pulse`}
          />
          <span className="text-[12px] text-white/60">{lastUpdate.message}</span>
          <span
            className={`text-[10px] px-1.5 py-0.5 rounded-full ml-auto ${
              lastUpdate.status === 'succeeded'
                ? 'bg-[#22c55e]/10 text-[#22c55e]'
                : lastUpdate.status === 'failed'
                  ? 'bg-red-500/10 text-red-400'
                  : 'bg-[#8b5cf6]/10 text-[#8b5cf6]'
            }`}
          >
            {lastUpdate.status}
          </span>
        </div>
      )}
      <ConnectionsCard svc={svc} serviceId={serviceId} />
    </div>
  )
}
