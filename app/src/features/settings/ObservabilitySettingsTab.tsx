import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { adminSettingsApi } from '@/lib/api'
import { useAuthStore } from '@/stores/useAuthStore'
import { Button } from '@/components/ui/button'
import { toast } from 'sonner'

const defaults: Record<string, string> = { metrics_services_enabled: 'true', metrics_hosts_enabled: 'true', metrics_retention_days: '30' }

export default function ObservabilitySettingsTab() {
  const isAdmin = useAuthStore(s => s.user?.admin === true)
  const queryClient = useQueryClient()
  const settings = useQuery({ queryKey: ['admin-settings'], queryFn: adminSettingsApi.list, enabled: isAdmin })
  const [draft, setDraft] = useState<Record<string, string>>({})
  const saved = { ...defaults, ...Object.fromEntries((settings.data ?? []).filter(s => s.key in defaults).map(s => [s.key, s.value])) }
  const form = { ...saved, ...draft }
  const mutation = useMutation({
    mutationFn: () => adminSettingsApi.update(form),
    onSuccess: async () => { await queryClient.invalidateQueries({ queryKey: ['admin-settings'] }); setDraft({}); toast.success('Observability settings saved') },
    onError: (error: Error) => toast.error(error.message),
  })
  if (!isAdmin) return <p className="text-sm text-[#a0a0b0]">An instance administrator manages observability settings.</p>
  if (settings.isLoading) return <p role="status">Loading settings…</p>
  if (settings.isError) return <div role="alert">Could not load settings. <Button onClick={() => settings.refetch()}>Retry</Button></div>
  return <form className="max-w-2xl space-y-6 text-sm" onSubmit={e => { e.preventDefault(); mutation.mutate() }}>
    <div><h2 className="font-medium text-white">Observability</h2><p className="mt-2 text-[#a0a0b0]">Control resource collection across this RailDock instance. Changes apply to all organizations.</p></div>
    <fieldset disabled={mutation.isPending} className="space-y-5">
      {(['services', 'hosts'] as const).map(scope => <label key={scope} className="flex items-start gap-3">
        <input type="checkbox" className="mt-1 accent-[#8b5cf6]" checked={form[`metrics_${scope}_enabled`] === 'true'} onChange={e => setDraft(d => ({ ...d, [`metrics_${scope}_enabled`]: String(e.target.checked) }))} />
        <span><span className="text-white">{scope === 'services' ? 'Application resource metrics' : 'Host server metrics'}</span><span className="block mt-1 text-xs text-[#a0a0b0]">{scope === 'services' ? 'CPU, memory, network and disk I/O for deployed services.' : 'Whole-server CPU, memory, root disk usage, load and network counters.'}</span></span>
      </label>)}
      <label htmlFor="metric-retention" className="block"><span className="text-white">Metric history retention</span><select id="metric-retention" aria-label="Metric history retention" className="block mt-2 bg-[#18181b] border border-white/15 rounded-md p-2" value={form.metrics_retention_days} onChange={e => setDraft(d => ({ ...d, metrics_retention_days: e.target.value }))}>{[1, 7, 14, 30, 60, 90].map(days => <option key={days} value={days}>{days} {days === 1 ? 'day' : 'days'}</option>)}</select></label>
      <p className="text-xs text-[#a0a0b0]">Disabling collection stops live and background sampling. Existing history remains until it expires. Shortening retention permanently removes older samples during the next cleanup.</p>
      <p className="text-xs text-[#a0a0b0]">Host live views refresh every 10 seconds while open. Background history is collected every minute. This is resource monitoring; request analytics and attack detection require separate collection.</p>
      <div className="flex items-center gap-3"><Button type="submit" disabled={!Object.keys(draft).length || mutation.isPending}>{mutation.isPending ? 'Saving…' : 'Save changes'}</Button><Button type="button" variant="ghost" disabled={!Object.keys(draft).length} onClick={() => setDraft({})}>Reset</Button><Link className="text-[#c4b5fd]" to="/servers">View servers</Link></div>
    </fieldset>
  </form>
}
