import { useState } from 'react'
import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { useServiceMetrics, useServiceMetricsHistory } from '@/hooks/useServices'
import type { Service } from '@/types'

const WINDOWS = [
  { label: '1h', hours: 1 },
  { label: '6h', hours: 6 },
  { label: '24h', hours: 24 },
  { label: '7d', hours: 168 },
]

function formatAt(iso: string, hours: number): string {
  const d = new Date(iso)
  const opts: Intl.DateTimeFormatOptions =
    hours <= 1
      ? { hour: '2-digit', minute: '2-digit', second: '2-digit' }
      : hours <= 24
        ? { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }
        : { month: 'short', day: 'numeric' }
  return d.toLocaleString(undefined, opts)
}

export default function MetricsTab({ svc }: { svc: Service }) {
  const [hours, setHours] = useState(1)
  const { data: live } = useServiceMetrics(svc.id)
  const { data: history } = useServiceMetricsHistory(svc.id, hours)

  // Docker reports CPU as % of one core; a container capped at N cores can
  // read up to N*100%. Normalize against the configured core limit so the
  // chart tops out at 100% = the limit, never misleadingly above it.
  const cpuCores = live?.cpuCores || history?.samples[0]?.cpu_cores || 1
  const cpuNorm = (v: number | null | undefined) =>
    v == null ? null : Math.min(Math.round((v / (cpuCores || 1)) * 10) / 10, 100)

  const samples = (history?.samples ?? []).map((s) => ({
    time: formatAt(s.at, hours),
    cpu: cpuNorm(s.cpu),
    memory: s.memory,
  }))

  return (
    <div className="p-5">
      <div className="flex items-center justify-between mb-4">
        <div className="text-[14px] font-medium text-white/70">Metrics</div>
        <div className="flex gap-1">
          {WINDOWS.map((w) => (
            <button
              key={w.hours}
              onClick={() => setHours(w.hours)}
              className={`px-2.5 py-1 text-[11px] rounded-md transition-colors ${
                hours === w.hours
                  ? 'bg-violet-500/20 text-violet-300'
                  : 'bg-white/[0.04] text-white/40 hover:text-white/70'
              }`}
            >
              {w.label}
            </button>
          ))}
        </div>
      </div>

      {history && history.samples.length > 0 ? (
        <div className="space-y-4">
          <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4">
            <div className="text-[11px] text-white/40 mb-2">CPU (%)</div>
            <div className="h-44">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={samples} margin={{ top: 4, right: 8, left: -18, bottom: 0 }}>
                  <defs>
                    <linearGradient id="cpuGrad" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="#8b5cf6" stopOpacity={0.35} />
                      <stop offset="100%" stopColor="#8b5cf6" stopOpacity={0.02} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" />
                  <XAxis dataKey="time" tick={{ fill: 'rgba(255,255,255,0.35)', fontSize: 10 }} minTickGap={30} />
                  <YAxis domain={[0, 100]} tick={{ fill: 'rgba(255,255,255,0.35)', fontSize: 10 }} />
                  <Tooltip
                    contentStyle={{ background: '#151518', border: '1px solid rgba(255,255,255,0.1)', borderRadius: 8, fontSize: 12 }}
                    labelStyle={{ color: 'rgba(255,255,255,0.6)' }}
                  />
                  <Area type="monotone" dataKey="cpu" stroke="#8b5cf6" strokeWidth={2} fill="url(#cpuGrad)" name="CPU" />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </div>

          <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4">
            <div className="text-[11px] text-white/40 mb-2">Memory (%)</div>
            <div className="h-44">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={samples} margin={{ top: 4, right: 8, left: -18, bottom: 0 }}>
                  <defs>
                    <linearGradient id="memGrad" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="#22c55e" stopOpacity={0.35} />
                      <stop offset="100%" stopColor="#22c55e" stopOpacity={0.02} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" />
                  <XAxis dataKey="time" tick={{ fill: 'rgba(255,255,255,0.35)', fontSize: 10 }} minTickGap={30} />
                  <YAxis domain={[0, 100]} tick={{ fill: 'rgba(255,255,255,0.35)', fontSize: 10 }} />
                  <Tooltip
                    contentStyle={{ background: '#151518', border: '1px solid rgba(255,255,255,0.1)', borderRadius: 8, fontSize: 12 }}
                    labelStyle={{ color: 'rgba(255,255,255,0.6)' }}
                  />
                  <Area type="monotone" dataKey="memory" stroke="#22c55e" strokeWidth={2} fill="url(#memGrad)" name="Memory" />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </div>

          <div className="flex items-center gap-6 px-1 pt-1 text-[11px] text-white/40">
            <span className="flex items-center gap-1.5">
              <span className="w-2 h-2 rounded-full bg-violet-500" /> Live CPU
              <span className="text-white/70 ml-1">
                {live?.cpu != null && cpuNorm(live.cpu) != null
                  ? `${cpuNorm(live.cpu)!.toFixed(1)}% of ${cpuCores} core${cpuCores > 1 ? 's' : ''}`
                  : '—'}
              </span>
            </span>
            <span className="flex items-center gap-1.5">
              <span className="w-2 h-2 rounded-full bg-green-500" /> Live Memory
              <span className="text-white/70 ml-1">{live?.memory != null ? `${live.memory.toFixed(1)}%` : '—'}</span>
            </span>
          </div>
        </div>
      ) : (
        <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-8 flex flex-col items-center justify-center text-center">
          <div className="text-white/40 text-[13px] mb-2">No historical data yet</div>
          <div className="text-white/20 text-[11px] max-w-xs">
            Metrics are sampled every 5 minutes. Check back shortly to see CPU and memory graphs for this service.
          </div>
          {live && (
            <div className="mt-4 text-[12px] text-white/60">
              Live: CPU {cpuNorm(live.cpu)?.toFixed(1)}% of {cpuCores} core{cpuCores > 1 ? 's' : ''} · Memory{' '}
              {live.memory?.toFixed(1)}%
            </div>
          )}
        </div>
      )}
    </div>
  )
}
