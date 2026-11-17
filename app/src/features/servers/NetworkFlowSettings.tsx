import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { networkFlowsApi, type FlowSettings } from '@/lib/networkFlows'
import { SettingsSection, SettingsToggle, SettingsRow, SettingsSaveBar } from '@/features/settings/SettingsSection'
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from '@/components/ui/select'
import { Button } from '@/components/ui/button'
export default function NetworkFlowSettings({serverId}:{serverId:string}) {
  const query=useQuery({queryKey:['network-flow-settings',serverId],queryFn:()=>networkFlowsApi.settings(serverId)})
  const client=useQueryClient()
  const [draft,setDraft]=useState<Partial<FlowSettings>>({})
  const mutation=useMutation({mutationFn:(value:FlowSettings)=>networkFlowsApi.save(serverId,value),onSuccess:async()=>{await client.invalidateQueries({queryKey:['network-flow-settings',serverId]});await client.invalidateQueries({queryKey:['network-flows']});setDraft({})}})
  if(query.isLoading)return <p role="status">Loading network activity settings…</p>
  if(!query.data)return <p role="alert">Could not load settings. <Button onClick={()=>query.refetch()}>Retry</Button></p>
  const settings={...query.data.settings,...draft}
  return <form className="max-w-3xl space-y-5" onSubmit={e=>{e.preventDefault();mutation.mutate(settings)}}>
    <div><h2 className="text-base font-medium text-white">Service network activity</h2><p className="mt-2 text-sm leading-6 text-[#9292a3]">Measure direct TCP traffic between linked services on this host. Canvas connections move only when byte counters increase.</p></div>
    <SettingsSection title="Collection" description="Enabled by default with live-only retention. No agent, packet capture, firewall changes or application instrumentation.">
      <SettingsToggle id="flow-enabled" title="Measure service connections" description="Reads Linux TCP counters across app replicas and workers. Samples every minute in the background and about every 10 seconds while a canvas is open. Disabling stops sampling." checked={settings.enabled} onChange={enabled=>setDraft(d=>({...d,enabled}))}/>
      <SettingsRow id="flow-retention" title="Traffic history" description="Live only keeps the latest aggregate snapshot. Optional minute history uses storage proportional to the number of links. Shortening retention removes older history."><Select value={String(settings.retentionDays)} onValueChange={value=>setDraft(d=>({...d,retentionDays:Number(value)}))}><SelectTrigger id="flow-retention"><SelectValue/></SelectTrigger><SelectContent>{[0,1,7,30].map(days=><SelectItem key={days} value={String(days)}>{days?`${days} days`:'Live only'}</SelectItem>)}</SelectContent></Select></SettingsRow>
    </SettingsSection>
    <p className="text-xs leading-5 text-[#9292a3]">Requires Linux 5+, root SSH, Python 3, nsenter and ss on the host. Sampling can miss connections that close between scans. UDP, Unix sockets, host networking and connections through proxy/NAT aliases are not covered. No observed traffic does not mean an unused or unhealthy service.</p>
    {query.data.error&&<p role="status" className="text-sm text-amber-300">{query.data.error}</p>}
    {mutation.error&&<p role="alert" className="text-sm text-red-300">{mutation.error.message}</p>}
    <SettingsSaveBar dirty={Object.keys(draft).length>0} saving={mutation.isPending} onReset={()=>setDraft({})}/>
  </form>
}
