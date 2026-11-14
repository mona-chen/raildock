import ErrorState from '@/features/shared/ErrorState'
import { useCallback, useMemo, useState, useEffect } from 'react'
import {
  Area,
  AreaChart,
  CartesianGrid,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { useServiceDeployments, useServiceMetrics, useServiceMetricsHistory } from '@/hooks/useServices'
import type { Service } from '@/types'

const WINDOWS = [
  { label: '1h', hours: 1 },
  { label: '6h', hours: 6 },
  { label: '24h', hours: 24 },
  { label: '7d', hours: 168 },
]

interface MetricPoint {
  ts: number
  cpu: number | null
  memory: number | null
  netIn: number | null
  netOut: number | null
  diskRead: number | null
  diskWrite: number | null
}

interface Series {
  key: keyof MetricPoint
  name: string
  color: string
}

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

function formatRate(bytesPerSecond: number | null): string {
  if (bytesPerSecond == null) return '—'
  if (bytesPerSecond < 1024) return `${Math.round(bytesPerSecond)} B/s`
  if (bytesPerSecond < 1024 ** 2) return `${(bytesPerSecond / 1024).toFixed(1)} KB/s`
  if (bytesPerSecond < 1024 ** 3) return `${(bytesPerSecond / 1024 ** 2).toFixed(1)} MB/s`
  return `${(bytesPerSecond / 1024 ** 3).toFixed(1)} GB/s`
}

// A container's counters reset when it restarts, so a negative delta means the
// sample straddles a restart and the rate is unknown rather than negative.
function rate(cur: number | null | undefined, prev: number | null | undefined, dtSeconds: number): number | null {
  if (cur == null || prev == null || dtSeconds <= 0 || dtSeconds > 600) return null
  const delta = cur - prev
  return delta < 0 ? null : delta / dtSeconds
}

function MetricChart({
  title,
  data,
  hours,
  deployMarkers,
  series,
  yDomain,
  yTickFormatter,
  valueFormatter,
}: {
  title: string
  data: MetricPoint[]
  hours: number
  deployMarkers: number[]
  series: Series[]
  yDomain?: [number | 'auto', number | 'auto']
  yTickFormatter?: (value: number) => string
  valueFormatter?: (value: number) => string
}) {
  return (
    <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4">
      <div className="text-[11px] text-white/50 mb-2">{title}</div>
      <div className="h-40">
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={data} margin={{ top: 4, right: 8, left: -18, bottom: 0 }}>
            <defs>
              {series.map((s) => (
                <linearGradient key={s.key} id={`metric-grad-${s.key}`} x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor={s.color} stopOpacity={0.3} />
                  <stop offset="100%" stopColor={s.color} stopOpacity={0.02} />
                </linearGradient>
              ))}
            </defs>
            <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.06)" />
            <XAxis
              dataKey="ts"
              type="number"
              domain={['dataMin', 'dataMax']}
              tick={{ fill: 'rgba(255,255,255,0.45)', fontSize: 10 }}
              tickFormatter={(value: number) => formatAt(new Date(value).toISOString(), hours)}
              minTickGap={40}
              axisLine={false}
              tickLine={false}
            />
            <YAxis
              domain={yDomain}
              tick={{ fill: 'rgba(255,255,255,0.45)', fontSize: 10 }}
              tickFormatter={yTickFormatter}
              width={44}
            />
            <Tooltip
              contentStyle={{ background: '#151518', border: '1px solid rgba(255,255,255,0.1)', borderRadius: 8, fontSize: 12 }}
              labelStyle={{ color: 'rgba(255,255,255,0.6)' }}
              labelFormatter={(value) => formatAt(new Date(Number(value)).toISOString(), hours)}
              formatter={(value, name) => [
                valueFormatter ? valueFormatter(Number(value)) : String(value),
                String(name),
              ]}
            />
            {deployMarkers.map((ts) => (
              <ReferenceLine key={ts} x={ts} stroke="rgba(139,92,246,0.5)" strokeDasharray="3 3" />
            ))}
            {series.map((s) => (
              <Area
                key={s.key}
                type="monotone"
                dataKey={s.key}
                stroke={s.color}
                strokeWidth={2}
                fill={`url(#metric-grad-${s.key})`}
                name={s.name}
                dot={false}
              />
            ))}
          </AreaChart>
        </ResponsiveContainer>
      </div>
    </div>
  )
}

export default function MetricsTab({ svc }: { svc: Service }) {
  const [now, setNow] = useState(Date.now)
  useEffect(() => { const timer = window.setInterval(() => setNow(Date.now()), 60000); return () => window.clearInterval(timer) }, [])
  const [hours, setHours] = useState(1)
  const liveQuery = useServiceMetrics(svc.id)
  const { data: live } = liveQuery
  const historyQuery = useServiceMetricsHistory(svc.id, hours)
  const { data: history } = historyQuery
  const { data: deployments } = useServiceDeployments(svc.id)

  // Docker reports CPU as % of one core; a container capped at N cores can
  // read up to N*100%. Normalize against the configured core limit so the
  // chart tops out at 100% = the limit, never misleadingly above it.
  const cpuCores = live?.cpuCores || history?.samples[0]?.cpu_cores || 1
  const cpuNorm = useCallback(
    (v: number | null | undefined) =>
      v == null ? null : Math.round((v / (cpuCores || 1)) * 10) / 10,
    [cpuCores],
  )

  const points: MetricPoint[] = useMemo(() => {
    const raw = history?.samples ?? []
    return raw.map((s, index) => {
      const previous = index > 0 ? raw[index - 1] : null
      const ts = new Date(s.at).getTime()
      const dtSeconds = previous ? (ts - new Date(previous.at).getTime()) / 1000 : 0
      return {
        ts,
        cpu: s.cpu == null ? null : s.cpu / (s.cpu_cores && s.cpu_cores > 0 ? s.cpu_cores : cpuCores),
        memory: s.memory,
        netIn: rate(s.network_in, previous?.network_in, dtSeconds),
        netOut: rate(s.network_out, previous?.network_out, dtSeconds),
        diskRead: rate(s.block_read, previous?.block_read, dtSeconds),
        diskWrite: rate(s.block_write, previous?.block_write, dtSeconds),
      }
    })
  }, [history, cpuCores])

  const deployMarkers = useMemo(() => {
    if (points.length < 2) return []
    const first = points[0].ts
    const last = points[points.length - 1].ts
    return (deployments ?? [])
      .filter((d) => d.status === 'succeeded' && d.createdAt)
      .map((d) => new Date(d.createdAt as string).getTime())
      .filter((ts) => ts >= first && ts <= last)
      .sort((a, b) => a - b)
  }, [deployments, points])

  const hasTraffic = points.some((p) => p.netIn != null || p.netOut != null)
  const hasDisk = points.some((p) => p.diskRead != null || p.diskWrite != null)

  return (
    <div className="p-5">
      <div className="flex items-center justify-between mb-4">
        <div className="text-[14px] font-medium text-white/70">Metrics</div>
        <div className="flex gap-1">
          {WINDOWS.map((w) => (
            <button
              key={w.hours}
              aria-pressed={hours === w.hours}
              onClick={() => setHours(w.hours)}
              className={`px-2.5 py-1 text-[11px] rounded-md transition-colors ${
                hours === w.hours
                  ? 'bg-violet-500/20 text-violet-300'
                  : 'bg-white/[0.04] text-white/50 hover:text-white/70'
              }`}
            >
              {w.label}
            </button>
          ))}
        </div>
      </div>

      <p className="mb-3 text-xs text-[#a0a0b0]">Usage from the primary app container or datastore container. History is sampled every 5 minutes; replicas and worker processes are not aggregated.</p>
      {liveQuery.isError && <p role="status" className="mb-3 text-xs text-amber-200">Current usage is unavailable. Historical samples are retained.</p>}
      {history?.samples.length ? <p className="mb-4 text-xs text-[#a0a0b0]">Last sample: {new Date(history.samples[history.samples.length - 1].at).toLocaleString()}{now - new Date(history.samples[history.samples.length - 1].at).getTime() > 15 * 60 * 1000 ? ' · Data is stale; sampling may be delayed.' : ''}</p> : null}
      {historyQuery.isError && <ErrorState title="Could not load metric history" message="Retry to fetch samples for the selected window." onRetry={() => historyQuery.refetch()} />}
      {history && history.samples.length > 0 ? (
        <div className="space-y-4">
          <MetricChart
            title="CPU (% of limit)"
            data={points}
            hours={hours}
            deployMarkers={deployMarkers}
            yDomain={[0, 100]}
            yTickFormatter={(v) => `${v}%`}
            valueFormatter={(v) => `${v.toFixed(1)}%`}
            series={[{ key: 'cpu', name: 'CPU', color: '#8b5cf6' }]}
          />

          <MetricChart
            title="Memory (%)"
            data={points}
            hours={hours}
            deployMarkers={deployMarkers}
            yDomain={[0, 100]}
            yTickFormatter={(v) => `${v}%`}
            valueFormatter={(v) => `${v.toFixed(1)}%`}
            series={[{ key: 'memory', name: 'Memory', color: '#22c55e' }]}
          />

          {hasTraffic && (
            <MetricChart
              title="Network"
              data={points}
              hours={hours}
              deployMarkers={deployMarkers}
              yTickFormatter={(v) => formatRate(v)}
              valueFormatter={(v) => formatRate(v)}
              series={[
                { key: 'netIn', name: 'In', color: '#3b82f6' },
                { key: 'netOut', name: 'Out', color: '#14b8a6' },
              ]}
            />
          )}

          {hasDisk && (
            <MetricChart
              title="Disk I/O"
              data={points}
              hours={hours}
              deployMarkers={deployMarkers}
              yTickFormatter={(v) => formatRate(v)}
              valueFormatter={(v) => formatRate(v)}
              series={[
                { key: 'diskRead', name: 'Read', color: '#f97316' },
                { key: 'diskWrite', name: 'Write', color: '#eab308' },
              ]}
            />
          )}

          <div className="flex flex-wrap items-center gap-6 px-1 pt-1 text-[11px] text-white/50">
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
            {deployMarkers.length > 0 && (
              <span className="flex items-center gap-1.5">
                <span className="w-4 border-t border-dashed border-[#8b5cf6]" /> Deploys ({deployMarkers.length})
              </span>
            )}
          </div>
        </div>
      ) : !historyQuery.isError ? (
        <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-8 flex flex-col items-center justify-center text-center">
          <div className="text-white/50 text-[13px] mb-2">{historyQuery.isLoading ? 'Loading metric history…' : 'No samples in this time range'}</div>
          <div className="text-white/50 text-[11px] max-w-xs">
            Metrics are sampled every 5 minutes. Check back shortly to see CPU, memory, network and disk graphs for this service.
          </div>
          {live && (
            <div className="mt-4 text-[12px] text-white/60">
              Live: CPU {cpuNorm(live.cpu)?.toFixed(1)}% of {cpuCores} core{cpuCores > 1 ? 's' : ''} · Memory{' '}
              {live.memory?.toFixed(1)}%
            </div>
          )}
        </div>
      ) : null}
    </div>
  )
}
