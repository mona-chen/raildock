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
  return createPortal(<section aria-label="Connection activity" style={{fontFamily:'Charter, "Bitstream Charter", "Sitka Text", Cambria, Georgia, serif',boxShadow:'0 12px 36px #0005, 0 2px 5px #0003',backgroundImage:'repeating-linear-gradient(0deg, transparent, transparent 31px, #82765006 31px, #82765006 32px)'}} className="fixed bottom-5 right-5 z-50 w-[324px] max-w-[calc(100vw-2.5rem)] max-h-[calc(100dvh-2.5rem)] overflow-y-auto rounded-[3px] border border-[#d8d0bb] bg-[#f1eddf] text-[#393d33]" onMouseDownCapture={e=>e.stopPropagation()}>
    <div className="flex items-center justify-between gap-3 px-5 pt-3"><p className="text-[13px] text-[#6b6c5e]">Connection activity</p><IconButton title="Close connection activity" onClick={onClose} className="text-[#6b6c5e] hover:bg-[#393d330a] hover:text-[#393d33]"><X size={16}/></IconButton></div>
    <div className="px-5 pb-5">
      <h3 className="mt-1 break-words text-[20px] leading-7 tracking-[-0.02em]">{label||'Service connection'}</h3>
      <p className="mt-2 flex items-center gap-2 text-[13px] text-[#626958]"><span className={`h-1.5 w-1.5 rounded-full ${active?'bg-[#397a59]':'bg-[#aaa895]'}`}/>{status}</p>
      {measured&&<><dl className="mt-5 grid grid-cols-2 gap-5 border-y border-[#88816b]/20 py-4"><div><dt className="text-[12px] text-[#6b6c5e]">Sent</dt><dd className="mt-1 text-[27px] leading-8 tabular-nums tracking-[-0.03em] text-[#326247]">{flowBytes(flow.sentBytes)}</dd></div><div><dt className="text-[12px] text-[#6b6c5e]">Received</dt><dd className="mt-1 text-[27px] leading-8 tabular-nums tracking-[-0.03em] text-[#496978]">{flowBytes(flow.receivedBytes)}</dd></div></dl><p className="mt-3 text-[13px] text-[#6b6c5e]">{flow.connections||0} open {flow.connections===1?'connection':'connections'}<span className="mx-2 text-[#b3ad98]">·</span>{Math.round(flow.windowSeconds||0)} s sample</p></>}
      <p className="mt-2 text-[12px] text-[#6b6c5e]">{flow?.lastActivityAt?`Last traffic ${new Date(flow.lastActivityAt).toLocaleTimeString()}`:at?`Updated ${new Date(at).toLocaleTimeString()}`:'Waiting for a measurement'}</p>
      <details className="mt-5 border-t border-[#88816b]/20 pt-3"><summary className="flex cursor-pointer list-none items-center justify-between gap-3 text-[13px] [&::-webkit-details-marker]:hidden"><span className="underline decoration-[#aaa38d] underline-offset-4">Recent history</span><span className="text-[11px] text-[#6b6c5e]">{history.isLoading?'Loading':rows.length?`${rows.length} samples`:'No samples'}</span></summary>
        {history.isError?<p role="alert" className="mt-3 text-[12px]">History could not be loaded.</p>:rows.length?<div className="mt-3 space-y-2 text-[12px] tabular-nums">{rows.map(row=><div key={row.sampledAt} className="flex justify-between gap-3 border-b border-[#88816b]/10 pb-2"><span className="text-[#6b6c5e]">{new Date(row.sampledAt).toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'})}</span><span>{flowBytes(row.sentBytes)} sent · {flowBytes(row.receivedBytes)} received</span></div>)}</div>:<p className="mt-3 text-[12px] leading-5 text-[#6b6c5e]">No retained samples yet. History is optional in the server’s connection settings.</p>}
      </details>
      <details className="mt-3 text-[12px] text-[#6b6c5e]"><summary className="cursor-pointer list-none underline decoration-[#b9b29e] underline-offset-4 [&::-webkit-details-marker]:hidden">About this measurement</summary><p className="mt-2 leading-5">Sampled TCP bytes, not individual packets. Sent is source to target; received is the return direction. Quiet does not mean unused or broken. Short connections and indirect routes can be missed.</p></details>
    </div>
  </section>,document.body)
}
