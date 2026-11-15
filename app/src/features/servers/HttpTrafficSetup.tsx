import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Button } from '@/components/ui/button'
import { observabilityApi, type TrafficSettings, type TrafficSource } from '@/lib/api'

export default function HttpTrafficSetup({ serverId, settings, onAdvanced }: {serverId: string; settings: TrafficSettings; onAdvanced: () => void}) {
  const [sources, setSources] = useState<TrafficSource[] | null>(null)
  const [review, setReview] = useState<TrafficSource | null>(null)
  const client = useQueryClient()
  const invalidate = () => client.invalidateQueries({queryKey: ['http-traffic', serverId]})
  const detection = useMutation({mutationFn: () => observabilityApi.discoverTraffic(serverId), onSuccess: data => { setSources(data.candidates); setReview(null) }})
  const setup = useMutation({mutationFn: (source: TrafficSource) => observabilityApi.setupTraffic(serverId, source.reviewToken!), onSuccess: async () => { setReview(null); await invalidate() }})
  const connect = useMutation({mutationFn: (source: TrafficSource) => observabilityApi.saveTraffic(serverId, {enabled: true, path: source.path, format: 'traefik', retentionDays: settings.retentionDays || 7, capturePaths: false}), onSuccess: invalidate})
  const running = settings.setupState === 'running'
  const error = detection.error || setup.error || connect.error
  return <section className="rounded-lg border border-white/10 bg-white/[0.02] p-5 sm:p-6" aria-label="HTTP analytics setup">
    <div className="flex flex-wrap items-start justify-between gap-4">
      <div className="max-w-xl space-y-2"><h3 className="font-medium text-white">{running ? 'Setting up HTTP analytics' : 'HTTP analytics is not collecting'}</h3>
        <p className="text-sm leading-relaxed text-[#a0a0b0]">{running ? 'The host is configuring access logging and checking the proxy. This page will update when setup finishes.' : 'Connect your proxy to measure requests, response times and errors. RailDock can find the source and configure logging for you.'}</p>
      </div>
      {!running && <Button onClick={() => detection.mutate()} disabled={detection.isPending}>{detection.isPending ? 'Detecting proxy…' : sources ? 'Detect again' : 'Set up HTTP analytics'}</Button>}
    </div>
    {settings.setupState === 'failed' && <p role="alert" className="mt-4 text-sm text-red-300">{settings.setupError || 'Setup failed. Detect the proxy again to review the current configuration.'}</p>}
    {error && <p role="alert" className="mt-4 text-sm text-red-300">{error.message}</p>}
    {!running && sources && <div className="mt-5 divide-y divide-white/10 border-t border-white/10">
      {!sources.length && <p className="py-4 text-sm text-[#a0a0b0]">No supported Traefik container was found. You can connect an existing Traefik or Caddy JSON log using advanced configuration.</p>}
      {sources.map(source => <div key={source.container} className="flex flex-wrap items-center justify-between gap-4 py-4">
        <div><p className="text-sm font-medium text-white">{source.container}</p><p className="mt-1 text-xs text-[#9292a3]">{source.image} · {source.path ? 'JSON access log found' : source.canManage ? 'Logging setup available' : source.reason}</p></div>
        {source.path ? <Button variant="secondary" disabled={connect.isPending} onClick={() => connect.mutate(source)}>Connect existing log</Button> : source.canManage && <Button variant="secondary" onClick={() => setReview(source)}>Review setup</Button>}
      </div>)}
    </div>}
    {!running && review && <div className="mt-3 space-y-4 border-t border-white/10 pt-5">
      <h4 className="text-sm font-medium text-white">Configure logging for {review.container}</h4>
      <ul className="list-disc space-y-2 pl-5 text-sm leading-relaxed text-[#b0b0bd]">
        <li>Enable buffered JSON logging for requests, latency and errors. Client IPs, headers and paths are excluded.</li>
        <li>Back up the configuration and preserve routing and certificates.</li>
        <li>Restart this proxy once. Connections may briefly drop for every application it serves. Restore the previous configuration if startup checks fail.</li>
      </ul>
      <details className="text-xs leading-relaxed text-[#9292a3]"><summary className="cursor-pointer text-[#c0c0cc]">Storage and proxy ownership</summary><p className="mt-2">Log size is checked hourly and rotated at 25 MB, keeping two rotated files. Files can exceed 25 MB between checks. Aggregate history defaults to {settings.retentionDays || 7} days. Disabling collection leaves proxy logging active. Another platform can overwrite these logging settings when it updates the proxy.</p></details>
      <div className="flex flex-wrap gap-2"><Button disabled={setup.isPending} onClick={() => setup.mutate(review)}>{setup.isPending ? 'Scheduling…' : 'Enable logging and restart proxy'}</Button><Button variant="ghost" disabled={setup.isPending} onClick={() => setReview(null)}>Cancel</Button></div>
    </div>}
    {!running && <div className="mt-5 border-t border-white/10 pt-4"><Button variant="outline" onClick={onAdvanced}>Advanced: connect a log manually</Button></div>}
  </section>
}
