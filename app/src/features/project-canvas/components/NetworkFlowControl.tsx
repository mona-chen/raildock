import { Link } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Switch } from '@/components/ui/switch'
import { type NetworkFlows } from '@/lib/networkFlows'
export default function NetworkFlowControl({data,error,serverId,animate,setAnimate}:{data?:NetworkFlows;error:boolean;serverId?:string;animate:boolean;setAnimate:(value:boolean)=>void}) {
  return <details className="absolute right-4 bottom-16 sm:bottom-5 z-30 max-w-[calc(100%-2rem)] rounded-lg border border-white/10 bg-[#18181e]/95 text-xs text-[#b0b0bd] shadow-lg" onMouseDownCapture={e=>e.stopPropagation()}>
    <summary className="list-none cursor-pointer px-3 py-2.5 [&::-webkit-details-marker]:hidden">Network flow · {error?'unavailable':!data?'loading':!data.enabled?'off':data.error?'unavailable':'sampling TCP'}</summary>
    <div className="w-72 max-w-full space-y-4 border-t border-white/10 p-4"><p className="leading-5">Pulses show measured byte increases, not individual packets. Select a connection for its latest counters and history.</p><label htmlFor="animate-measured-flow" className="flex items-center justify-between gap-4">Animate observed traffic<Switch id="animate-measured-flow" aria-label="Animate observed traffic" checked={animate} onCheckedChange={setAnimate}/></label><p className="text-[11px] leading-5 text-[#9292a3]">Animation is separate from collection. Reduced-motion preferences always suppress movement. Missing or stale telemetry stays still. Motion is capped at 40 connections.</p>{serverId&&<Button variant="outline" size="sm" asChild><Link to={`/dashboard/servers/${serverId}?tab=flows`}>Collection and retention</Link></Button>}</div>
  </details>
}
