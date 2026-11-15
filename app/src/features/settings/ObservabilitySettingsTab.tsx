import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { adminSettingsApi } from '@/lib/api'
import { useAuthStore } from '@/stores/useAuthStore'
import { Button } from '@/components/ui/button'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { SettingsSection, SettingsRow, SettingsToggle, SettingsSaveBar } from './SettingsSection'
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
  const dirty = Object.entries(draft).some(([key, value]) => value !== saved[key])
  return <form className="max-w-[840px] space-y-6" onSubmit={e => { e.preventDefault(); mutation.mutate() }}>
    <div className="pb-1"><h2 className="text-base font-medium text-white">Observability</h2><p className="mt-1.5 text-[13px] leading-5 text-[#9292a3]">Resource collection and history for this instance.</p></div>
    <fieldset disabled={mutation.isPending} className="space-y-5">
      <SettingsSection title="Resource collection" description="Applies to all organizations. Turning collection off keeps existing history until it expires.">
        <SettingsToggle id="metrics-applications" title="Application resource metrics" description="CPU, memory, network and disk I/O for deployed services." checked={form.metrics_services_enabled === 'true'} onChange={checked => setDraft(d => ({ ...d, metrics_services_enabled: String(checked) }))} />
        <SettingsToggle id="metrics-hosts" title="Host server metrics" description="Whole-server CPU, memory, disk usage, load and network." checked={form.metrics_hosts_enabled === 'true'} onChange={checked => setDraft(d => ({ ...d, metrics_hosts_enabled: String(checked) }))} />
      </SettingsSection>
      <SettingsSection title="History">
        <SettingsRow id="metric-retention" title="Metric history retention" description="Older samples are permanently removed during cleanup. A shorter period uses less storage.">
          <Select value={form.metrics_retention_days} onValueChange={value => setDraft(d => ({ ...d, metrics_retention_days: value }))}><SelectTrigger id="metric-retention" aria-label="Metric history retention" className="w-[160px] border-white/10 bg-[#1a1a20] text-xs"><SelectValue /></SelectTrigger><SelectContent className="border-white/10 bg-[#1a1a20] text-white">{[1,7,14,30,60,90].map(days => <SelectItem key={days} value={String(days)}>{days} {days === 1 ? 'day' : 'days'}</SelectItem>)}</SelectContent></Select>
        </SettingsRow>
      </SettingsSection>
    </fieldset>
    <div className="flex flex-wrap items-center justify-between gap-3 px-1 text-xs text-[#9292a3]"><span>Live refresh · 10 seconds <span className="mx-2 text-white/15">/</span> Background history · 1 minute</span><Link className="text-[#bca5f5] hover:text-white" to="/dashboard/servers">View servers</Link></div>
    <SettingsSaveBar dirty={dirty} saving={mutation.isPending} onReset={() => setDraft({})} />
  </form>
}
