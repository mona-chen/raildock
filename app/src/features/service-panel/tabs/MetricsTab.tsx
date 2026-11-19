import { Switch } from '@/components/ui/switch'
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
  memoryUsed: number | null
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
    <div className="bg-[#141417] border border-white/6 rounded-lg p-4">
      <div className="mb-3 flex flex-wrap items-center justify-between gap-2"><h3 className="text-xs text-[#a0a0b0]">{title}</h3><span className="text-xs tabular-nums text-[#dedee7]">{series.map(s=>{const value=data.at(-1)?.[s.key];return value==null?'—':`${series.length>1?s.name+' ':''}${valueFormatter?valueFormatter(value):value}`}).join(' · ')}</span></div>
      <div className="h-40">
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={data} margin={{ top: 4, right: 8, left: 0, bottom: 0 }}>
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
              width={64}
              tickCount={4}
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
                type="linear"
                dataKey={s.key}
                stroke={s.color}
                strokeWidth={2}
                fill={`url(#metric-grad-${s.key})`}
                name={s.name}
                dot={data.length === 1 ? { r: 3 } : false}
                isAnimationActive={false}
                connectNulls={false}
              />
            ))}
          </AreaChart>
        </ResponsiveContainer>
      </div>
    </div>
  )
}

type MetricSample = NonNullable<ReturnType<typeof useServiceMetricsHistory>['data']>['samples'][number]

export default function MetricsTab({ svc }: { svc: Service }) {
  const [now, setNow] = useState(Date.now)
  useEffect(() => { const timer = window.setInterval(() => setNow(Date.now()), 60000); return () => window.clearInterval(timer) }, [])
  const [hours, setHours] = useState(1)
  const [liveEnabled, setLiveEnabled] = useState(true)
  const [liveSamples, setLiveSamples] = useState<MetricSample[]>([])
  const liveQuery = useServiceMetrics(svc.id, liveEnabled)
  const { data: live } = liveQuery
  const historyQuery = useServiceMetricsHistory(svc.id, hours)
  const { data: history } = historyQuery
  const { data: deployments } = useServiceDeployments(svc.id)

  useEffect(() => {
    if (!liveEnabled || !live || live.cpu == null || live.collectionEnabled === false) return
    const sample: MetricSample = { at: new Date(liveQuery.dataUpdatedAt).toISOString(), cpu: live.cpu, cpuCores: live.cpuCores, memory: live.memory, memoryUsed: live.memoryUsed ?? null, memoryLimit: live.memoryLimit ?? null, networkIn: live.networkIn, networkOut: live.networkOut, blockRead: live.blockRead, blockWrite: live.blockWrite }
    setLiveSamples(previous => [...previous.filter(point => point.at !== sample.at), sample].slice(-360))
  }, [live, liveQuery.dataUpdatedAt, liveEnabled])

  // CPU is plotted in Docker's native units (100% = one core), including
  // unlimited containers and limit changes. The live summary also shows limits.
  const cpuCores = live?.cpuCores || history?.samples[0]?.cpuCores || 1
  const cpuNorm = useCallback(
    (v: number | null | undefined) =>
      v == null ? null : v / (cpuCores || 1),
    [cpuCores],
  )

  const points: MetricPoint[] = useMemo(() => {
    const raw = [...new Map([...(history?.samples ?? []), ...liveSamples].filter(s => new Date(s.at).getTime() >= now - hours * 3600_000).map(s => [s.at, s])).values()].sort((a, b) => new Date(a.at).getTime() - new Date(b.at).getTime())
    return raw.map((s, index) => {
      const previous = index > 0 ? raw[index - 1] : null
      const ts = new Date(s.at).getTime()
      const dtSeconds = previous ? (ts - new Date(previous.at).getTime()) / 1000 : 0
      return {
        ts,
        cpu: s.cpu,
        memory: s.memory,
        memoryUsed: s.memoryUsed,
        netIn: rate(s.networkIn, previous?.networkIn, dtSeconds),
        netOut: rate(s.networkOut, previous?.networkOut, dtSeconds),
        diskRead: rate(s.blockRead, previous?.blockRead, dtSeconds),
        diskWrite: rate(s.blockWrite, previous?.blockWrite, dtSeconds),
      }
    })
  }, [history, liveSamples, now, hours])

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

  const memoryBytes = (value:number|null|undefined) => value==null?'—':value>=1073741824?`${(value/1073741824).toFixed(2)} GiB`:`${(value/1048576).toFixed(1)} MiB`
  const last = history?.samples.at(-1)
  const currentMemoryUsed = live?.memoryUsed ?? last?.memoryUsed
  const currentMemoryLimit = live?.memoryLimit ?? last?.memoryLimit
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
                  : 'bg-white/4 text-white/50 hover:text-white/70'
              }`}
            >
              {w.label}
            </button>
          ))}
        </div>
      </div>

      {history?.collectionEnabled === false && <p role="status" className="mb-3 text-xs text-amber-200">Application metric collection is disabled in Settings. Retained history is still available.</p>}
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3 text-xs"><span className="text-[#9292a3]">Primary container · Workers and replicas excluded</span><label htmlFor="application-metrics-live" className="flex items-center gap-2 text-xs text-[#a0a0b0]">Live<Switch id="application-metrics-live" aria-label="Live application refresh" checked={liveEnabled} onCheckedChange={setLiveEnabled} className="data-[state=checked]:bg-rail-purple **:data-[slot=switch-thumb]:bg-white"/></label></div>
      <div className="mb-5 grid gap-3" style={{gridTemplateColumns:'repeat(auto-fit,minmax(150px,1fr))'}}>{[['CPU',live?.cpu!=null?`${live.cpu.toFixed(2)}%`:'—',live?.cpuCores?`Limit: ${live.cpuCores} ${live.cpuCores===1?'core':'cores'}`:'100% = one core'],['Memory used',memoryBytes(currentMemoryUsed),`Reported ceiling: ${memoryBytes(currentMemoryLimit)}`],['Network',points.at(-1)?.netIn!=null?formatRate(points.at(-1)!.netIn):'—','Incoming bytes / second']].map(([label,value,help])=><div key={label} className="rounded-lg border border-white/8 bg-[#141417] p-4"><p className="text-xs text-[#9292a3]">{label}</p><p className="mt-2 text-lg font-medium tabular-nums text-white">{value}</p><p className="mt-1 text-[11px] text-[#9292a3]">{help}</p></div>)}</div>
      {(liveQuery.isError || (live && live.cpu == null && live.collectionEnabled !== false)) && <p role="status" className="mb-3 text-xs text-amber-200">Current usage is unavailable. Historical samples are retained.</p>}
      {history?.samples.length ? <p className="mb-4 text-xs text-[#a0a0b0]">Last sample: {new Date(history.samples[history.samples.length - 1].at).toLocaleString()}{now - new Date(history.samples[history.samples.length - 1].at).getTime() > 3 * 60 * 1000 ? ' · Data is stale; sampling may be delayed.' : ''}</p> : null}
      {historyQuery.isError && <ErrorState title="Could not load metric history" message="Retry to fetch samples for the selected window." onRetry={() => historyQuery.refetch()} />}
      {history?.samples.length === 1 && <p role="status" className="mb-4 text-xs text-[#a0a0b0]">Only one sample is available in this time range. Choose a longer range or wait for another sample. History is normally sampled every minute.</p>}
      {points.length > 0 ? (
        <div className="grid gap-4" style={{gridTemplateColumns:'repeat(auto-fit,minmax(min(100%,320px),1fr))'}}>
          <MetricChart
            title="CPU · 100% = one core"
            data={points}
            hours={hours}
            deployMarkers={deployMarkers}
            yDomain={[0, 'auto']}
            yTickFormatter={(v) => `${v}%`}
            valueFormatter={(v) => `${v.toFixed(2)}%`}
            series={[{ key: 'cpu', name: 'CPU', color: '#8b5cf6' }]}
          />

          <MetricChart
            title="Memory used"
            data={points}
            hours={hours}
            deployMarkers={deployMarkers}
            yDomain={[0, 'auto']}
            yTickFormatter={v => memoryBytes(v).replace(' ', '')}
            valueFormatter={memoryBytes}
            series={[{ key: 'memoryUsed', name: 'Memory', color: '#22c55e' }]}
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

          <p className="text-[11px] leading-5 text-[#9292a3] sm:col-span-full">Live refresh · 10 seconds. Retained history · 1 minute. Memory ceiling is reported by Docker and may equal host capacity when no limit is set.</p>
        </div>
      ) : !historyQuery.isError ? (
        <div className="bg-[#141417] border border-white/6 rounded-xl p-8 flex flex-col items-center justify-center text-center">
          <div className="text-white/50 text-[13px] mb-2">{historyQuery.isLoading ? 'Loading metric history…' : 'No samples in this time range'}</div>
          <div className="text-white/50 text-[11px] max-w-xs">
            Metrics are sampled every minute. Check back shortly to see CPU, memory, network and disk graphs for this service.
          </div>
          {live && (
            <div className="mt-4 text-[12px] text-white/60">
              Live: CPU {cpuNorm(live.cpu)?.toFixed(2)}% of {cpuCores} core{cpuCores > 1 ? 's' : ''} · Memory{' '}
              {live.memory?.toFixed(1)}%
            </div>
          )}
        </div>
      ) : null}
    </div>
  )
}
