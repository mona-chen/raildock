import { Link } from 'react-router-dom'
import { Activity } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { IconButton } from '@/components/ui/icon-button'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { Switch } from '@/components/ui/switch'
import { type NetworkFlows } from '@/lib/networkFlows'

export default function NetworkFlowControl({data,error,serverId,animate,setAnimate}:{data?:NetworkFlows;error:boolean;serverId?:string;animate:boolean;setAnimate:(value:boolean)=>void}) {
  const status=error?'unavailable':!data?'loading':!data.enabled?'off':data.error?'unavailable':'sampling TCP'
  return <div className="absolute right-4 bottom-16 sm:bottom-5 z-30" onMouseDownCapture={e=>e.stopPropagation()}>
    <Popover><PopoverTrigger asChild><IconButton title={`Network flow: ${status}`} className={`h-9 w-9 rounded-lg border border-white/10 bg-[#18181e]/95 shadow-lg ${data?.enabled&&!error&&!data.error?'text-[#a7d7c3]':''}`}><Activity aria-hidden="true"/></IconButton></PopoverTrigger>
      <PopoverContent side="top" align="end" sideOffset={8} className="w-72 space-y-4 border-white/10 bg-[#18181e] p-4 text-xs text-[#b0b0bd]">
        <p className="font-medium text-white">Network flow · {status}</p>
        <p className="leading-5">Pulses show measured byte increases, not individual packets. Select a connection for its latest counters and history.</p>
        <label htmlFor="animate-measured-flow" className="flex items-center justify-between gap-4">Animate observed traffic<Switch id="animate-measured-flow" aria-label="Animate observed traffic" checked={animate} onCheckedChange={setAnimate}/></label>
        <p className="text-[11px] leading-5 text-[#9292a3]">Animation is separate from collection. Reduced-motion preferences always suppress movement. Missing or stale telemetry stays still. Motion is capped at 40 connections.</p>
        {serverId&&<Button variant="outline" size="sm" asChild><Link to={`/dashboard/servers/${serverId}?tab=flows`}>Collection and retention</Link></Button>}
      </PopoverContent>
    </Popover>
  </div>
}
