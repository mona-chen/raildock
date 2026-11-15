import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { Switch } from '@/components/ui/switch'
import { Input } from '@/components/ui/input'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { SettingsSection, SettingsRow, SettingsToggle, SettingsSaveBar } from '@/features/settings/SettingsSection'
import { Button } from '@/components/ui/button'
import { observabilityApi, type TrafficSettings } from '@/lib/api'
import { toast } from 'sonner'
import HttpTrafficSetup from './HttpTrafficSetup'

const latencyBounds=[1,5,10,25,50,100,250,500,1000,2500,5000,10000,30000,60000]
export function latencyP95(histogram:number[]=[]):string {
  const total=histogram.reduce((a,b)=>a+b,0)
  if(!total)return '—'
  let count=0
  const index=histogram.findIndex(value=>{count+=value;return count>=Math.ceil(total*.95)})
  return index>=latencyBounds.length?'>60 s':`≤ ${latencyBounds[index]} ms`
}
const formatBytes=(value:number)=>value>=1048576?`${(value/1048576).toFixed(1)} MB`:`${(value/1024).toFixed(1)} KB`

export default function HttpTrafficPanel({serverId}:{serverId:string}) {
  const [serviceId,setServiceId]=useState('')
  const [hours,setHours]=useState(1)
  const [live,setLive]=useState(true)
  const [configure,setConfigure]=useState(false)
  const [draft,setDraft]=useState<Partial<TrafficSettings>>({})
  const client=useQueryClient()
  const query=useQuery({queryKey:['http-traffic',serverId,hours,serviceId],queryFn:()=>observabilityApi.traffic(serverId,hours,live,serviceId),refetchInterval:query => query.state.data?.settings.setupState === 'running' ? 3000 : live ? 10000 : false,retry:false})
  const mutation=useMutation({mutationFn:(settings:TrafficSettings)=>observabilityApi.saveTraffic(serverId,settings),onSuccess:async()=>{await client.invalidateQueries({queryKey:['http-traffic',serverId]});setDraft({});setConfigure(false);toast.success('HTTP collection settings saved')},onError:(error:Error)=>toast.error(error.message)})
  if(query.isLoading)return <p role="status">Loading HTTP analytics…</p>
  if(query.isError||!query.data)return <p role="alert">Could not load HTTP analytics. <Button onClick={()=>query.refetch()}>Retry</Button></p>
  const data=query.data
  const settings={...data.settings,...draft,enabled:draft.enabled??data.settings.enabled??false,format:draft.format??data.settings.format??'traefik',retentionDays:draft.retentionDays??data.settings.retentionDays??7}
  const summary=data.summary
  const requests=summary.requests||0
  const errors=summary.statuses?.['5xx']||0
  const configured=Boolean(data.settings.enabled)
  const hasHistory=data.samples.length>0
  const hasCollection=Boolean(configured && data.collection.checkedAt && !data.collection.error)
  return <div className="space-y-5 text-sm">
    <div className="flex flex-wrap justify-between gap-3"><div className={configured||hasHistory?"flex flex-wrap items-center gap-3":"hidden"}><Select value={serviceId||'all'} onValueChange={value=>setServiceId(value==='all'?'':value)}><SelectTrigger aria-label="Application traffic filter" className="h-8 w-[170px] border-white/10 bg-transparent text-xs"><SelectValue placeholder="All traffic"/></SelectTrigger><SelectContent className="border-white/10 bg-[#1a1a20] text-white"><SelectItem value="all">All traffic</SelectItem>{data.applications?.map(app=><SelectItem key={app.id} value={app.id}>{app.name}</SelectItem>)}</SelectContent></Select><div className="flex gap-1">{[1,6,24,168].map(h=><Button key={h} size="sm" variant={h===hours?'secondary':'ghost'} aria-pressed={h===hours} onClick={()=>setHours(h)}>{h===168?'7d':`${h}h`}</Button>)}</div></div><div className="flex items-center gap-2"><label className={configured||hasHistory?"flex items-center gap-2 text-xs text-[#a0a0b0]":"hidden"} htmlFor="http-live">Live<Switch id="http-live" aria-label="Live HTTP refresh" checked={configured&&live} disabled={!configured} onCheckedChange={setLive} className="data-[state=checked]:bg-[#8b5cf6] [&_[data-slot=switch-thumb]]:bg-white"/></label><span className="mx-2 h-4 w-px bg-white/10"/><Button variant="outline" size="sm" onClick={()=>setConfigure(v=>!v)}>{configure?'Close settings':'Collection settings'}</Button></div></div>
    {(!configured || Boolean(data.collection.error) || data.settings.setupState==='running' || data.settings.setupState==='failed')&&<HttpTrafficSetup serverId={serverId} settings={settings} onAdvanced={()=>setConfigure(true)}/>}
    {configure&&<form className="space-y-4" onSubmit={e=>{e.preventDefault();mutation.mutate({...settings,path:settings.path?.trim()})}}><fieldset disabled={mutation.isPending} className="space-y-4">
      <SettingsSection title="HTTP collection" description="Collection preferences and advanced log source. Disabling collection stops ingestion; proxy logging and rotation remain active.">
        <SettingsToggle id="traffic-enabled" title="Collect HTTP traffic" description="Requires Python 3 on the host. First enable starts from the end of the log." checked={settings.enabled} onChange={enabled=>setDraft(d=>({...d,enabled}))}/>
        <SettingsRow id="traffic-path" title="Host log path" description="Advanced: an existing JSON access log on this host. The example below is not a configured file."><Input id="traffic-path" required={settings.enabled} value={settings.path||''} placeholder="/var/log/traefik/access.log" onChange={e=>setDraft(d=>({...d,path:e.target.value}))} className="border-white/10 bg-[#1a1a20] text-xs"/></SettingsRow>
        <SettingsRow id="traffic-format" title="Log format"><Select value={settings.format} onValueChange={format=>setDraft(d=>({...d,format}))}><SelectTrigger id="traffic-format" className="w-full border-white/10 bg-[#1a1a20] text-xs"><SelectValue/></SelectTrigger><SelectContent className="border-white/10 bg-[#1a1a20] text-white"><SelectItem value="traefik">Traefik JSON</SelectItem><SelectItem value="caddy">Caddy JSON</SelectItem></SelectContent></Select></SettingsRow>
        <SettingsRow id="traffic-retention" title="History retention" description="Hourly aggregates are retained for 1–30 days; minute detail for up to 2 days. Shortening retention expires older buckets."><div className="flex items-center gap-2"><Input id="traffic-retention" type="number" min={1} max={30} required value={settings.retentionDays} onChange={e=>setDraft(d=>({...d,retentionDays:Number(e.target.value)}))} className="w-20 border-white/10 bg-[#1a1a20] text-xs text-right"/><span className="text-xs text-[#9292a3]">days</span></div></SettingsRow>
        {data.settings.managedLogging?<SettingsRow id="traffic-paths" title="Request paths" description="Automatic setup excludes paths at the proxy, alongside client IPs and headers. Advanced sources can opt into normalized path retention."><span className="text-xs text-[#9292a3]">Not collected</span></SettingsRow>:<SettingsToggle id="traffic-paths" title="Retain normalized paths" description="Off by default. Paths may contain sensitive identifiers. Query strings, IPs, headers and bodies are never retained." checked={settings.capturePaths||false} onChange={capturePaths=>setDraft(d=>({...d,capturePaths}))}/>}

      </SettingsSection></fieldset><SettingsSaveBar dirty={Object.keys(draft).length>0} saving={mutation.isPending} onReset={()=>setDraft({})}/>
    </form>}

    <p role="status" className="text-xs text-[#a0a0b0]">{!configured?'Not collecting · existing history remains available until it expires.':data.collection.error?data.collection.error:!data.collection.checkedAt?'Waiting for the first collection.':`${live?'Live refresh · every 10 seconds':'Refresh paused'} · Last collection ${new Date(data.collection.checkedAt).toLocaleTimeString()}`}</p>
    {(data.collection.backlogBytes||0)>0&&<p role="status" className="text-xs text-amber-200">Collector is catching up: {formatBytes(data.collection.backlogBytes!)} unread. Totals are incomplete; traffic alerts are paused.</p>}
    {Boolean(data.collection.invalidLines)&&<p className="text-xs text-amber-200">{data.collection.invalidLines} invalid or oversized lines skipped in the last scan. Check the selected JSON format.</p>}
    {Boolean(data.collection.rotations)&&<p className="text-xs text-[#a0a0b0]">{data.collection.rotations} log rotations detected. Unread records in a rotated file may not be included.</p>}
    {(configured||hasHistory)&&<>
    <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">{[['Requests',hasCollection||hasHistory?requests.toLocaleString():'—'],['Response bandwidth',hasCollection||hasHistory?formatBytes(summary.bandwidth||0):'—'],['5xx error rate',requests?`${(errors*100/requests).toFixed(1)}%`:'—'],['p95 latency',latencyP95(summary.histogram)]].map(([label,value])=><div key={label} className="rounded-lg border border-white/10 p-4"><p className="text-xs text-[#a0a0b0]">{label}</p><p className="mt-2 text-xl tabular-nums text-white">{value}</p></div>)}</div>
    <p className="text-xs text-[#a0a0b0]">Latency is an upper bound from merged histogram buckets. {data.coverage}</p>
    <div className="flex items-baseline justify-between"><h3 className="text-[13px] font-medium text-white">Requests</h3><span className="text-xs text-[#9292a3]">{data.bucketSeconds===3600?'Per hour':'Per minute'}</span></div>
    {data.samples.length?<div className="h-52 min-w-0"><ResponsiveContainer width="100%" height="100%"><AreaChart data={data.samples}><CartesianGrid stroke="#ffffff0a" vertical={false}/><XAxis dataKey="at" tickFormatter={s=>new Date(s).toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'})} minTickGap={50} tick={{fill:'#9292a3',fontSize:10}}/><YAxis width={50} tick={{fill:'#9292a3',fontSize:10}}/><Tooltip contentStyle={{background:'#18181b',border:'1px solid #ffffff20'}} labelFormatter={s=>new Date(String(s)).toLocaleString()}/><Area name="Requests per bucket" dataKey="requests" type="linear" stroke="#a78bfa" fill="#a78bfa" fillOpacity={.08} isAnimationActive={false}/></AreaChart></ResponsiveContainer></div>:<div className="py-10 text-center text-[#a0a0b0]">{data.collection.error?'Collection is unavailable. Check the source in collection settings.':configured&&!data.collection.checkedAt?'Waiting for the first collection.':configured?'No requests recorded in this range.':'Set up HTTP analytics to start recording traffic.'}</div>}
    <div className="grid sm:grid-cols-2 gap-6"><section><h3 className="text-white mb-3">Status codes</h3>{['2xx','3xx','4xx','5xx'].map(status=><div key={status} className="flex justify-between py-2 border-b border-white/5 text-xs"><span>{status}</span><span>{hasCollection||hasHistory?summary.statuses?.[status]||0:'—'}</span></div>)}</section><section><h3 className="text-white mb-3">Retained paths</h3>{(summary.paths||[]).length?[...summary.paths!].sort((a,b)=>b.count-a.count).map(({path,count})=><div key={path} className="flex justify-between gap-3 py-2 border-b border-white/5 text-xs"><span className="truncate font-mono" title={path}>{path}</span><span>{count}</span></div>):<p className="text-xs text-[#a0a0b0]">Path collection is off by default. When enabled, up to 25 categories per bucket are retained; other paths are grouped.</p>}</section></div>
    <section><h3 className="mb-3 text-[13px] font-medium text-white">Traffic by application</h3>{data.byApplication?.length?<div className="divide-y divide-white/[0.06]">{data.byApplication.map(app=><div key={app.id} className="flex items-center justify-between py-2 text-xs text-[#b0b0bd]"><span>{app.name}</span><span className="tabular-nums">{app.requests.toLocaleString()} requests</span></div>)}</div>:<p className="text-xs text-[#9292a3]">Application totals appear when requests match a configured service domain.</p>}</section>
    </>}
  </div>
}
