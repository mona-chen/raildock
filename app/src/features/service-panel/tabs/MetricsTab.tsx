import { useRef, useEffect } from 'react'
import { useServiceMetrics } from '@/hooks/useServices'
import type { Service } from '@/types'

function useMetricHistory(serviceId: string, maxPoints = 30) {
  const { data: metrics } = useServiceMetrics(serviceId)
  const historyRef = useRef<{
    cpu: number[]
    memory: number[]
    networkIn: number[]
    networkOut: number[]
  }>({
    cpu: [],
    memory: [],
    networkIn: [],
    networkOut: [],
  })

  useEffect(() => {
    if (!metrics) return
    const h = historyRef.current
    h.cpu.push(metrics.cpu || 0)
    h.memory.push(metrics.memory || 0)
    h.networkIn.push(metrics.networkIn || 0)
    h.networkOut.push(metrics.networkOut || 0)
    if (h.cpu.length > maxPoints) h.cpu.shift()
    if (h.memory.length > maxPoints) h.memory.shift()
    if (h.networkIn.length > maxPoints) h.networkIn.shift()
    if (h.networkOut.length > maxPoints) h.networkOut.shift()
  }, [metrics, maxPoints])

  return {
    current: metrics || { cpu: 0, memory: 0, networkIn: 0, networkOut: 0 },
    history: historyRef.current,
  }
}

function Sparkline({ data, color, maxVal = 100 }: { data: number[]; color: string; maxVal?: number }) {
  if (data.length === 0) {
    return (
      <div className="h-16 bg-black/20 rounded-lg flex items-center justify-center">
        <span className="text-[10px] text-white/20">Collecting data...</span>
      </div>
    )
  }
  const padded = data.length < 2 ? [...Array(Math.max(0, 2 - data.length)).fill(0), ...data] : data
  const h = 64
  const w = 280
  const step = w / (padded.length - 1)
  const points = padded
    .map((v, i) => {
      const x = i * step
      const y = h - (Math.min(v, maxVal) / maxVal) * (h - 4) - 2
      return `${x},${y}`
    })
    .join(' ')

  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="h-16 w-full bg-black/20 rounded-lg" preserveAspectRatio="none">
      <polyline
        fill="none"
        stroke={color}
        strokeWidth={2}
        strokeLinecap="round"
        strokeLinejoin="round"
        points={points}
        opacity={0.8}
      />
      {padded.map((v, i) => (
        <circle
          key={i}
          cx={i * step}
          cy={h - (Math.min(v, maxVal) / maxVal) * (h - 4) - 2}
          r={1.5}
          fill={color}
          opacity={0.6}
        />
      ))}
    </svg>
  )
}

export default function MetricsTab({ svc }: { svc: Service }) {
  const { current: m, history } = useMetricHistory(svc.id)

  const items = [
    { label: 'CPU', value: `${(m.cpu ?? 0).toFixed(1)}%`, color: '#8b5cf6', data: history.cpu, max: 100 },
    { label: 'Memory', value: `${(m.memory ?? 0).toFixed(1)}%`, color: '#22c55e', data: history.memory, max: 100 },
    {
      label: 'Network In',
      value: `${(m.networkIn ?? 0).toFixed(1)} MB/s`,
      color: '#3b82f6',
      data: history.networkIn,
      max: 50,
    },
    {
      label: 'Network Out',
      value: `${(m.networkOut ?? 0).toFixed(1)} MB/s`,
      color: '#f59e0b',
      data: history.networkOut,
      max: 50,
    },
  ]

  return (
    <div className="p-5">
      <div className="text-[14px] font-medium text-white/70 mb-4">Metrics</div>
      <div className="grid grid-cols-2 gap-3">
        {items.map((item) => (
          <div key={item.label} className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4">
            <div className="text-[11px] text-white/40 mb-2">{item.label}</div>
            <div className="text-[20px] font-semibold" style={{ color: item.color }}>
              {item.value}
            </div>
            <div className="mt-3">
              <Sparkline data={item.data} color={item.color} maxVal={item.max} />
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
