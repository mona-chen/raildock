import { useEffect, useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { serversApi, type HostMetricSample } from '@/lib/api'
import { Button } from '@/components/ui/button'

const timestamp = (sample: HostMetricSample) => new Date(sample.at || sample.sampledAt || '').getTime()
const bytes = (n: number) => n >= 1048576 ? `${(n / 1048576).toFixed(1)} MB/s` : n >= 1024 ? `${(n / 1024).toFixed(1)} KB/s` : `${n.toFixed(0)} B/s`

export default function HostMetricsPanel({ serverId }: { serverId: string }) {
  const [now, setNow] = useState(Date.now)
  useEffect(() => { const timer = window.setInterval(() => setNow(Date.now()), 10_000); return () => window.clearInterval(timer) }, [])
  const [hours, setHours] = useState(1)
  const [live, setLive] = useState(true)
  const [buffer, setBuffer] = useState<HostMetricSample[]>([])
  const history = useQuery({ queryKey: ['server-metrics-history', serverId, hours], queryFn: () => serversApi.metricsHistory(serverId, hours), refetchInterval: live ? 60_000 : false })
  const current = useQuery({ queryKey: ['server-metrics', serverId], queryFn: () => serversApi.metrics(serverId), enabled: live, refetchInterval: live ? 10_000 : false, retry: false })
  useEffect(() => {
    if (current.data?.sampledAt) setBuffer(previous => [...previous.filter(s => s.sampledAt !== current.data!.sampledAt), current.data!].slice(-360))
  }, [current.data])
  const points = useMemo(() => {
    const merged = [...(history.data?.samples ?? []), ...buffer].filter(s => timestamp(s) >= now - hours * 3600_000)
    const ordered = [...new Map(merged.map(s => [timestamp(s), s])).values()].sort((a, b) => timestamp(a) - timestamp(b))
    return ordered.map((s, index) => {
      const previous = ordered[index - 1]
      const elapsed = previous ? (timestamp(s) - timestamp(previous)) / 1000 : 0
      const rate = (key: 'networkRx' | 'networkTx') => s.available && previous?.available && elapsed > 0 && elapsed <= 180 && s[key] != null && previous[key] != null && s[key]! >= previous[key]! ? (s[key]! - previous[key]!) / elapsed : null
      return { ts: timestamp(s), cpu: s.available ? s.cpu : null, memory: s.available ? s.memory : null, disk: s.available ? s.disk : null, rx: rate('networkRx'), tx: rate('networkTx') }
    })
  }, [history.data, buffer, hours, now])
  const latest = current.data || history.data?.samples.at(-1)
  const disabled = history.data?.collectionEnabled === false || current.data?.collectionEnabled === false
  const stale = latest && now - timestamp(latest) > 90_000
  const unavailable = current.isError || latest?.available === false
  return <div className="space-y-5">
    <div className="flex flex-wrap items-center justify-between gap-3">
      <div className="flex gap-1" aria-label="Time range">{[1, 6, 24, 168].map(h => <Button key={h} size="sm" variant={hours === h ? 'secondary' : 'ghost'} aria-pressed={hours === h} onClick={() => setHours(h)}>{h === 168 ? '7d' : `${h}h`}</Button>)}</div>
      <Button variant="outline" size="sm" onClick={() => setLive(value => !value)}>{live ? 'Pause live' : 'Resume live'}</Button>
    </div>
    <p role="status" className={`text-xs ${unavailable ? 'text-amber-200' : 'text-[#a0a0b0]'}`}>{disabled ? 'Host collection is disabled in Settings.' : stale ? 'Host data is stale; collection may be delayed.' : unavailable ? 'Current host metrics are unavailable. Previous samples remain visible.' : live ? 'Live · refreshes every 10 seconds while open' : 'Live refresh paused'}{latest && timestamp(latest) ? ` · Last sample ${new Date(timestamp(latest)).toLocaleTimeString()}` : ''}</p>
    <p className="text-xs text-[#a0a0b0]">Whole-server usage, including applications and other host processes. Background history is collected every minute; memory uses Linux available memory. Network totals include non-loopback interfaces and may include bridge traffic.</p>
    {history.isError && <p role="alert" className="text-sm text-amber-200">History could not be loaded. <button className="underline" onClick={() => history.refetch()}>Retry</button></p>}
    {!points.length ? <div className="py-12 text-sm text-[#a0a0b0]">{history.isLoading ? 'Loading host history…' : disabled ? 'Collection is off. Retained samples will expire according to your retention policy.' : 'No samples yet. The first reading will appear after collection succeeds.'}</div> : <div className="grid gap-4 sm:grid-cols-2">
      {([{ title: 'CPU usage', series: [['cpu', '#a78bfa']], percentage: true }, { title: 'Memory usage', series: [['memory', '#2dd4bf']], percentage: true }, { title: 'Root disk usage', series: [['disk', '#60a5fa']], percentage: true }, { title: 'Network throughput', series: [['rx', '#2dd4bf'], ['tx', '#fbbf24']], percentage: false }] as const).map(chart => <section key={chart.title} className="min-w-0 rounded-lg border border-white/10 p-4">
        <div className="mb-4 flex items-center justify-between gap-3"><h3 className="text-xs text-[#c4c4ce]">{chart.title}</h3><span className="text-xs tabular-nums text-white">{chart.series.map(([key]) => { const value = points.at(-1)?.[key]; return value == null ? '—' : chart.percentage ? `${value.toFixed(2)}%` : `${key === 'rx' ? 'In' : 'Out'} ${bytes(value)}` }).join(' · ')}</span></div>
        <div className="h-44"><ResponsiveContainer width="100%" height="100%"><AreaChart data={points} margin={{ top: 5, right: 8, left: 0, bottom: 0 }}>
          <CartesianGrid stroke="#ffffff0a" vertical={false} /><XAxis dataKey="ts" type="number" domain={['dataMin', 'dataMax']} tickFormatter={n => new Date(n).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })} tick={{ fill: '#9292a3', fontSize: 10 }} minTickGap={45} />
          <YAxis width={58} domain={chart.percentage ? [0, 100] : [0, 'auto']} tickFormatter={n => chart.percentage ? `${n}%` : bytes(n)} tick={{ fill: '#9292a3', fontSize: 10 }} />
          <Tooltip contentStyle={{ background: '#18181b', border: '1px solid #ffffff20', borderRadius: 8, fontSize: 12 }} labelFormatter={n => new Date(Number(n)).toLocaleString()} formatter={(value, name) => [value == null ? 'Unavailable' : chart.percentage ? `${Number(value).toFixed(2)}%` : bytes(Number(value)), name === 'rx' ? 'Received' : name === 'tx' ? 'Sent' : chart.title]} />
          {chart.series.map(([key, color]) => <Area key={key} dataKey={key} type="linear" stroke={color} fill={color} fillOpacity={0.07} connectNulls={false} isAnimationActive={false} dot={points.length === 1 ? { r: 3 } : false} />)}
        </AreaChart></ResponsiveContainer></div>
      </section>)}
    </div>}
    <div className="flex flex-wrap gap-5 text-xs text-[#a0a0b0]"><span>Load (1 min): {latest?.available ? latest.load?.toFixed(2) ?? '—' : '—'}</span><span>Uptime: {latest?.available && latest.uptimeSeconds != null ? `${Math.floor(latest.uptimeSeconds / 86400)}d ${Math.floor(latest.uptimeSeconds % 86400 / 3600)}h` : '—'}</span><Link to="/settings?tab=observability" className="text-[#c4b5fd]">Collection and retention settings</Link></div>
  </div>
}
