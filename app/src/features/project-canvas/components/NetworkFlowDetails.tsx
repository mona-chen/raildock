import { useEffect } from 'react'
import { useQuery } from '@tanstack/react-query'
import { createPortal } from 'react-dom'
import { X } from 'lucide-react'
import { networkFlowsApi, flowBytes, type NetworkFlow } from '@/lib/networkFlows'
import { IconButton } from '@/components/ui/icon-button'

export default function NetworkFlowDetails({flow,at,label,projectId,onClose}:{flow?:NetworkFlow;at?:string;label?:string;projectId:string;onClose:()=>void}) {
  const history=useQuery({queryKey:['flow-history',projectId,flow?.id],queryFn:()=>networkFlowsApi.history(projectId,flow!.id),enabled:!!flow?.id&&!!projectId,refetchInterval:30000})
  useEffect(()=>{const close=(event:KeyboardEvent)=>{if(event.key==='Escape'){event.stopPropagation();onClose()}};document.addEventListener('keydown',close);return()=>document.removeEventListener('keydown',close)},[onClose])
  const measured=flow?.state==='sampled'
  const active=measured&&((flow.sentBytes||0)>0||(flow.receivedBytes||0)>0)
  const status=measured?(active?'Traffic observed':'Quiet this sample'):flow?.state==='warming'?'Taking a baseline…':flow?.state==='disabled'?'Collection is off':'Telemetry unavailable'
  const rows=history.data?.slice(-5)||[]
  return createPortal(<section aria-label="Connection activity" style={{fontFamily:'Charter, "Bitstream Charter", "Sitka Text", Cambria, Georgia, serif',filter:'drop-shadow(0 14px 22px #0006) drop-shadow(0 2px 2px #0005)'}} className="fixed bottom-4 right-4 z-50 w-[380px] max-w-[calc(100vw-2rem)] text-[#3d382e]" onMouseDownCapture={e=>e.stopPropagation()}>
    <div aria-hidden="true" className="pointer-events-none absolute inset-0" style={{backgroundImage:'url(/textures/connection-paper.svg)',backgroundSize:'100% 100%'}}/>
    <div className="relative max-h-[calc(100dvh-2rem)] overflow-y-auto rounded-[15px]">

    <div className="flex items-center justify-between gap-3 px-7 pt-5"><p className="text-[15px] text-[#716552]">Connection activity</p><IconButton title="Close connection activity" onClick={onClose} className="text-[#6b6c5e] hover:bg-[#393d330a] hover:text-[#393d33]"><X size={16}/></IconButton></div>
    <div className="px-7 pb-7">
      <h3 className="mt-2 break-words text-[25px] leading-8 tracking-[-0.02em]">{label||'Service connection'}</h3>
      <p className="mt-3 flex items-center gap-2 text-[16px] text-[#626958]"><span className={`h-1.5 w-1.5 rounded-full ${active?'bg-[#397a59]':'bg-[#aaa895]'}`}/>{status}</p>
      {measured&&<><dl className="mt-5 grid grid-cols-2 gap-5 border-y border-[#aa9169]/35 py-5"><div><dt className="text-[15px] text-[#716552]">Sent</dt><dd className="mt-2 text-[clamp(28px,3.2vw,36px)] leading-none tabular-nums tracking-[-0.03em] text-[#326247]">{flowBytes(flow.sentBytes)}</dd></div><div><dt className="text-[15px] text-[#716552]">Received</dt><dd className="mt-2 text-[clamp(28px,3.2vw,36px)] leading-none tabular-nums tracking-[-0.03em] text-[#496978]">{flowBytes(flow.receivedBytes)}</dd></div></dl><p className="mt-3 text-[15px] text-[#716552]">{flow.connections||0} open {flow.connections===1?'connection':'connections'}<span className="mx-2 text-[#b3ad98]">·</span>{Math.round(flow.windowSeconds||0)} s sample</p></>}
      <p className="mt-2 text-[14px] text-[#716552]">{flow?.lastActivityAt?`Last traffic ${new Date(flow.lastActivityAt).toLocaleTimeString()}`:at?`Updated ${new Date(at).toLocaleTimeString()}`:'Waiting for a measurement'}</p>
      <details open={rows.length>0} className="mt-5 border-t border-[#aa9169]/35 pt-4"><summary className="flex cursor-pointer list-none items-center justify-between gap-3 text-[15px] [&::-webkit-details-marker]:hidden"><span className="underline decoration-[#aaa38d] underline-offset-4">Recent history</span><span className="text-[13px] text-[#716552]">{history.isLoading?'Loading':rows.length?`${rows.length} samples`:'No samples'}</span></summary>
        {history.isError?<p role="alert" className="mt-3 text-[12px]">History could not be loaded.</p>:rows.length?<div className="mt-3 space-y-2 text-[14px] tabular-nums">{rows.map(row=><div key={row.sampledAt} className="flex justify-between gap-3 border-b border-[#aa9169]/20 pb-2"><span className="text-[#6b6c5e]">{new Date(row.sampledAt).toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'})}</span><span>{flowBytes(row.sentBytes)} sent · {flowBytes(row.receivedBytes)} received</span></div>)}</div>:<p className="mt-3 text-[12px] leading-5 text-[#6b6c5e]">No retained samples yet. History is optional in the server’s connection settings.</p>}
      </details>
      <details className="mt-5 text-[14px] text-[#716552]"><summary className="cursor-pointer list-none underline decoration-[#b9b29e] underline-offset-4 [&::-webkit-details-marker]:hidden">About this measurement</summary><p className="mt-2 leading-5">Sampled TCP bytes, not individual packets. Sent is source to target; received is the return direction. Quiet does not mean unused or broken. Short connections and indirect routes can be missed.</p></details>
    </div>
    </div>
  </section>,document.body)
}
