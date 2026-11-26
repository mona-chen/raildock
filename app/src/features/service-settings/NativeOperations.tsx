import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { RefreshCw, Server, Clock, KeyRound, ScrollText } from 'lucide-react'
import { toast } from 'sonner'
import { fetchJson } from '@/lib/api'
import { Button } from '@/components/ui/button'

type Task = { id:string;command:string;schedule:string;maintenance:boolean }
type Build = { id:string;status:string;displayStatus?:string;startedAt:string;duration?:string }
type NativeState = {capabilities:{version:string;namespaces:string[];features:Record<string,boolean>};cron?:Task[]|{error:string};builds?:Build[]|{error:string}}
const field = 'h-9 min-w-0 rounded-md border border-white/10 bg-black/20 px-3 text-xs text-white/80 outline-none focus:border-rail-purple/60'

export default function NativeOperations({serviceId}:{serviceId:string}) {
  const client = useQueryClient()
  const key = ['service-native', serviceId]
  const state = useQuery({queryKey:key,queryFn:()=>fetchJson<NativeState>(`/api/services/${serviceId}/native`),staleTime:60_000,retry:false})
  const [registry,setRegistry] = useState('ghcr.io')
  const [username,setUsername] = useState('')
  const [password,setPassword] = useState('')
  const [size,setSize] = useState('10')
  const operation = useMutation({
    mutationFn:(body:Record<string,unknown>)=>fetchJson<{requiresDeploy?:boolean}>(`/api/services/${serviceId}/native`,{method:'POST',body:JSON.stringify(body)}),
    onSuccess:result=>{toast.success(result.requiresDeploy?'Saved. Deploy to apply log rotation.':'Host operation completed');void client.invalidateQueries({queryKey:key})},
    onError:(error:Error)=>toast.error(error.message),
    onSettled:()=>setPassword(''),
  })
  const features = state.data?.capabilities.features ?? {}
  const tasks = Array.isArray(state.data?.cron)?state.data.cron:[]
  const builds = Array.isArray(state.data?.builds)?state.data.builds:[]
  return <div className="space-y-5">
    <div className="flex items-start justify-between gap-4"><div><h3 className="text-sm font-medium text-white/90">On this host</h3><p className="mt-1 text-xs leading-5 text-white/45">Live Dokku state, separate from settings waiting for your next deployment.</p></div><Button size="sm" variant="ghost" onClick={()=>void state.refetch()} disabled={state.isFetching}><RefreshCw size={13} className={state.isFetching?'animate-spin':''}/><span>Refresh</span></Button></div>
    {state.isPending?<p className="text-xs text-white/45">Reading host capabilities…</p>:state.error?<p role="alert" className="rounded-lg border border-red-400/20 bg-red-400/5 p-4 text-xs text-red-300">{state.error.message}</p>:<>
      <section className="overflow-hidden rounded-lg border border-white/8 bg-[#17171b]"><div className="flex items-center gap-2 border-b border-white/6 px-4 py-3"><Server size={14} className="text-rail-purple"/><h4 className="text-xs font-medium text-white/85">Dokku {state.data?.capabilities.version}</h4></div><div className="flex flex-wrap gap-2 p-4">{Object.entries(features).map(([name,available])=><span key={name} className={`rounded-md px-2 py-1 text-[11px] ${available?'bg-emerald-400/8 text-emerald-300/80':'bg-white/4 text-white/35'}`}>{name} · {available?'available':'not installed'}</span>)}</div></section>
      {features.cron&&<section className="overflow-hidden rounded-lg border border-white/8 bg-[#17171b]"><div className="flex items-center gap-2 border-b border-white/6 px-4 py-3"><Clock size={14} className="text-white/45"/><h4 className="text-xs font-medium text-white/85">Active schedules</h4></div>{!tasks.length?<p className="p-4 text-xs leading-5 text-white/45">No tasks are installed. Add schedules in Advanced, then deploy to activate them.</p>:tasks.map(task=><div key={task.id} className="border-b border-white/5 px-4 py-3 last:border-0"><div className="flex items-start justify-between gap-3"><div className="min-w-0"><p className="break-all font-mono text-xs text-white/75">{task.command}</p><p className="mt-1 text-[11px] text-white/40">{task.schedule} · {task.maintenance?'Paused':'Scheduled'} · host timezone</p></div><div className="flex shrink-0 gap-1"><Button size="sm" variant="ghost" disabled={operation.isPending||task.maintenance} onClick={()=>operation.mutate({operation:'cron_run',task_id:task.id})}>Run now</Button><Button size="sm" variant="ghost" disabled={operation.isPending} onClick={()=>operation.mutate({operation:task.maintenance?'cron_resume':'cron_suspend',task_id:task.id})}>{task.maintenance?'Resume':'Pause'}</Button></div></div></div>)}</section>}
      {features.builds&&<section className="overflow-hidden rounded-lg border border-white/8 bg-[#17171b]"><div className="flex items-center gap-2 border-b border-white/6 px-4 py-3"><ScrollText size={14} className="text-white/45"/><h4 className="text-xs font-medium text-white/85">Host deployment history</h4></div>{!builds.length?<p className="p-4 text-xs text-white/45">No native build records yet.</p>:builds.slice(0,8).map(build=><div key={build.id} className="flex items-center justify-between gap-3 border-b border-white/5 px-4 py-3 text-xs last:border-0"><div><p className="font-mono text-white/65">{build.id}</p><p className="mt-1 text-[11px] text-white/35">{new Date(build.startedAt).toLocaleString()}</p></div><span className={build.status==='succeeded'?'text-emerald-300/80':build.status==='failed'?'text-red-300':'text-white/55'}>{build.displayStatus??build.status} {build.duration&&`· ${build.duration}`}</span></div>)}</section>}
      {features.registry&&<section className="rounded-lg border border-white/8 bg-[#17171b] p-4"><div className="flex items-center gap-2"><KeyRound size={14} className="text-white/45"/><h4 className="text-xs font-medium text-white/85">Private image registry</h4></div><p className="mt-2 text-xs leading-5 text-white/45">Credentials are scoped to this app and stored by Dokku on its host. The password is sent through stdin and cleared from this form.</p><form className="mt-3 grid gap-2 sm:grid-cols-2" onSubmit={event=>{event.preventDefault();operation.mutate({operation:'registry_login',registry,username,password})}}><input className={field} aria-label="Registry hostname" value={registry} onChange={event=>setRegistry(event.target.value)} required/><input className={field} aria-label="Registry username" placeholder="Username" autoComplete="off" value={username} onChange={event=>setUsername(event.target.value)} required/><input className={field} aria-label="Registry password" placeholder="Access token or password" type="password" autoComplete="new-password" value={password} onChange={event=>setPassword(event.target.value)} required/><div className="flex gap-2"><Button type="submit" size="sm" disabled={operation.isPending||!password}>Connect registry</Button><Button type="button" size="sm" variant="ghost" disabled={operation.isPending||!registry} onClick={()=>operation.mutate({operation:'registry_logout',registry})}>Disconnect</Button></div></form></section>}
      {features.logs&&<section className="rounded-lg border border-white/8 bg-[#17171b] p-4"><h4 className="text-xs font-medium text-white/85">Container log rotation</h4><p className="mt-2 text-xs leading-5 text-white/45">Bound local log storage per container. New limits apply on the next deployment.</p><form className="mt-3 flex flex-wrap items-end gap-3" onSubmit={event=>{event.preventDefault();operation.mutate({operation:'logs_rotation',size_mb:Number(size)})}}><label className="grid gap-1 text-[11px] text-white/45">Maximum file size (MB)<input type="number" min="1" max="100" className={`${field} w-36`} value={size} onChange={event=>setSize(event.target.value)} required/></label><Button size="sm" type="submit" variant="secondary" disabled={operation.isPending}>Save rotation</Button></form></section>}
    </>}
  </div>
}
