import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Textarea } from '@/components/ui/textarea'
import { Input } from '@/components/ui/input'
import { SettingsSection, SettingsRow, SettingsToggle, SettingsSaveBar } from './SettingsSection'
import { Button } from '@/components/ui/button'
import { observabilityApi, type NotificationPolicy } from '@/lib/api'
import { toast } from 'sonner'
import { useAuthStore } from '@/stores/useAuthStore'

const fields: Array<[keyof NotificationPolicy, string, number]> = [['cpu','CPU threshold (%)',100],['memory','Memory threshold (%)',100],['disk','Host disk threshold (%)',100],['httpErrorPercent','HTTP 5xx rate (%) · minimum 20 requests/min',100],['requestsPerMinute','Requests per minute',1000000],['suspiciousPerMinute','Suspicious requests per minute',100000],['windowMinutes','Sustained duration (minutes)',15],['retentionDays','Resolved incident retention (days)',90]]
export default function NotificationsTab() {
  const organizationId = useAuthStore(s => s.currentOrganizationId)
  const client = useQueryClient()
  const query = useQuery({queryKey:['monitoring-notifications',organizationId],queryFn:observabilityApi.notifications,refetchInterval:15000})
  const [destinationsDraft,setDestinationsDraft]=useState<string|null>(null)
  const [draft,setDraft] = useState<Partial<NotificationPolicy>>({})
  const mutation = useMutation({mutationFn:(settings:NotificationPolicy)=>observabilityApi.saveNotifications({...settings,emailDestinations:destinationsDraft===null?settings.emailDestinations||[]:destinationsDraft.split(/[;,\n]/).map(value=>value.trim()).filter(Boolean)}),onSuccess:data=>{client.setQueryData(['monitoring-notifications',organizationId],data);setDraft({});setDestinationsDraft(null);toast.success('Notification settings saved')},onError:(error:Error)=>toast.error(error.message)})
  if(query.isLoading)return <p role="status">Loading notifications…</p>
  if(query.isError || !query.data)return <p role="alert">Could not load notifications. Organization owners and admins can configure alerts. <Button variant="ghost" onClick={()=>query.refetch()}>Retry</Button></p>
  const form={...query.data.settings,...draft}
  const dirty=destinationsDraft!==null || Object.entries(draft).some(([key,value])=>value!==query.data!.settings[key as keyof NotificationPolicy])
  const rules=(keys:Array<keyof NotificationPolicy>)=>fields.filter(([key])=>keys.includes(key)).map(([key,label,max])=><SettingsRow key={key} id={`alert-${key}`} title={label} description={key==='windowMinutes'?'A condition must remain above its threshold for this long.':key==='retentionDays'?'Resolved incidents expire after this period.':'Set to 0 to turn this rule off.'}><Input id={`alert-${key}`} type="number" min={key==='windowMinutes'||key==='retentionDays'?1:0} max={max} required step={1} value={Number(form[key])} onChange={e=>setDraft(d=>({...d,[key]:Number(e.target.value)}))} className="w-[112px] border-white/10 bg-[#1a1a20] text-right text-xs tabular-nums" /></SettingsRow>)
  return <div className="max-w-[840px] space-y-7">
    <div><h2 className="text-base font-medium text-white">Notifications</h2><p className="mt-1.5 text-[13px] leading-5 text-[#9292a3]">Monitoring rules and email delivery for this organization.</p></div>
    <form onSubmit={e=>{e.preventDefault();mutation.mutate(form)}} className="space-y-5">
      <fieldset disabled={mutation.isPending} className="space-y-5">
        <SettingsSection title="Delivery">
          <SettingsToggle id="alerts-enabled" title="Monitoring alerts" description="Record incidents when sustained conditions cross a threshold." checked={form.enabled} onChange={enabled=>setDraft(d=>({...d,enabled}))}/>
          <SettingsToggle id="alerts-email" title="Email notifications" description="Send alerts and recovery messages to organization owners and admins." checked={form.email} onChange={email=>setDraft(d=>({...d,email}))}/>
          <div className="px-5 py-4"><label htmlFor="notification-destinations" className="text-[13px] font-medium text-[#d8d8e0]">Additional email destinations</label><p id="notification-destinations-help" className="mt-1 text-xs leading-5 text-[#9292a3]">Shared inboxes and on-call addresses, in addition to organization admins. Up to 10 addresses, separated by commas or new lines.</p><Textarea id="notification-destinations" aria-describedby="notification-destinations-help" rows={3} value={destinationsDraft??(form.emailDestinations||[]).join('\n')} onChange={e=>setDestinationsDraft(e.target.value)} placeholder={'ops@example.com\noncall@example.com'} className="mt-3 resize-y border-white/10 bg-[#1a1a20] text-xs"/>{mutation.isError&&<p role="alert" className="mt-2 text-xs text-amber-200">{mutation.error.message}</p>}</div>
          {!query.data.smtpConfigured&&<p role="status" className="px-5 py-3 text-xs leading-5 text-amber-200/80">SMTP is not configured. Incidents are recorded here; an instance administrator must configure Email before messages can be sent.</p>}
        </SettingsSection>
        <SettingsSection title="Resource thresholds" description="CPU and memory apply to hosts and primary application containers. Disk usage applies to the host.">{rules(['cpu','memory','disk'])}</SettingsSection>
        <SettingsSection title="HTTP thresholds" description="Requires current proxy-log collection. Pattern-based alerts are optional and disabled by default.">{rules(['httpErrorPercent','requestsPerMinute','suspiciousPerMinute'])}</SettingsSection>
        <SettingsSection title="Timing and history">{rules(['windowMinutes','retentionDays'])}</SettingsSection>
      </fieldset>
      <SettingsSaveBar dirty={dirty} saving={mutation.isPending} onReset={()=>{setDraft({});setDestinationsDraft(null)}}/>
    </form>
    <section><h3 className="mb-3 text-[13px] font-medium text-white">Recent incidents</h3>{!query.data.incidents.length?<div className="rounded-lg border border-white/8 px-5 py-6"><p className="text-sm text-[#d8d8e0]">No incidents recorded</p><p className="mt-1.5 text-xs leading-5 text-[#9292a3]">Incidents appear after monitoring is enabled and a sustained threshold is reached.</p></div>:<div className="divide-y divide-white/[0.07] rounded-lg border border-white/8 bg-[#111114]">{query.data.incidents.map(incident=><article key={incident.id} className="space-y-2 px-5 py-4"><div className="flex justify-between gap-3"><span className="text-[13px] text-[#dedee7]">{incident.message}</span><span className={`shrink-0 text-xs ${incident.state==='resolved'?'text-emerald-300':'text-amber-200'}`}>{incident.state==='resolved'?'Recovered':'Active'}</span></div><p className="text-[11px] text-[#9292a3]">{incident.serverName} · {new Date(incident.startedAt).toLocaleString()} · Email: {incident.deliveryStatus.replaceAll('_',' ')}</p></article>)}</div>}</section>
  </div>
}
