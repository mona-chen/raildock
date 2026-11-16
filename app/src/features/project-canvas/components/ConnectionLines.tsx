import { memo, useEffect, useState, useSyncExternalStore } from 'react'
import { flowActive, flowBytes, type NetworkFlows } from '@/lib/networkFlows'
import NetworkFlowDetails from './NetworkFlowDetails'

const reducedMotionQuery = '(prefers-reduced-motion: reduce)'
const reducedMotion = () => typeof window.matchMedia === 'function' && window.matchMedia(reducedMotionQuery).matches
const subscribeMotion = (update: () => void) => {
  if(typeof window.matchMedia !== 'function')return ()=>{}
  const media = window.matchMedia(reducedMotionQuery)
  media.addEventListener('change',update)
  return ()=>media.removeEventListener('change',update)
}

interface Connection {
  from: { x: number; y: number }
  to: { x: number; y: number }
  fromId: string
  toId: string
  fromName?: string
  toName?: string
}

interface ConnectionLinesProps {
  connections: Connection[]
  activeServiceId?: string | null
  flows?: NetworkFlows
  animate?: boolean
  projectId?: string
}

function ConnectionLines({ connections, activeServiceId, flows, animate = false, projectId = "" }: ConnectionLinesProps) {
  const [hovered, setHovered] = useState<string | null>(null)
  const [focused, setFocused] = useState<string | null>(null)
  const [selected, setSelected] = useState<string | null>(null)
  const [now,setNow] = useState(Date.now)
  const reduced = useSyncExternalStore(subscribeMotion,reducedMotion,()=>true)
  useEffect(()=>{
    if(!flows?.enabled)return
    let timer: ReturnType<typeof setInterval> | undefined
    const start = () => {if(!document.hidden)timer=setInterval(()=>setNow(Date.now()),2000)}
    const visibility = () => {clearInterval(timer);setNow(Date.now());start()}
    start()
    document.addEventListener('visibilitychange',visibility)
    return()=>{clearInterval(timer);document.removeEventListener('visibilitychange',visibility)}
  },[flows?.enabled])
  const measured = (from: string, to: string) => {
    const row = flows?.links.find(link=>link.fromId===from&&link.toId===to)
    if(row && (!flows?.sampledAt || now-new Date(flows.sampledAt).getTime()>25000))return {...row,state:'unavailable' as const}
    return row
  }
  const selectedConnection = connections.find(conn=>`${conn.fromId}-${conn.toId}`===selected)

  if (connections.length === 0) return null

  return (
    <>
    <svg
      className="absolute inset-0"
      style={{ width: '100%', height: '100%', pointerEvents: 'none' }}
    >
      {connections.map((conn,index) => {
        const key = `${conn.fromId}-${conn.toId}`
        const isHovered = hovered === key
        const emphasized = isHovered || focused === key || selected === key
        const flow = measured(conn.fromId,conn.toId)
        const active = flowActive(flow,flows?.sampledAt,now)
        const moving = index<40 && animate && !reduced && !document.hidden && active
        const description = flow?.state==='sampled'?`${flowBytes(flow.sentBytes)} source to target, ${flowBytes(flow.receivedBytes)} target to source over ${Math.round(flow.windowSeconds||0)} seconds; ${flow.connections||0} open TCP connections`:flow?.state==='warming'?'Waiting for a second TCP sample':flow?.state==='disabled'?'Traffic collection disabled':'Traffic telemetry unavailable'
        const related = !activeServiceId || conn.fromId === activeServiceId || conn.toId === activeServiceId
        const rightward = conn.to.x >= conn.from.x
        const startX = conn.from.x + (rightward ? 240 : 0)
        const endX = conn.to.x + (rightward ? 0 : 240)
        const startY = conn.from.y + 52
        const endY = conn.to.y + 52
        const bend = Math.max(60, Math.abs(endX - startX) * 0.5) * (rightward ? 1 : -1)
        const pathD = `M ${startX} ${startY} C ${startX + bend} ${startY}, ${endX - bend} ${endY}, ${endX} ${endY}`

        return (
          <g
            key={key}
            style={{ pointerEvents: 'auto' }}
            className="outline-none" onMouseDown={event=>event.stopPropagation()}
            onFocus={()=>setFocused(key)} onBlur={()=>setFocused(null)}
            role="button" tabIndex={0} aria-label={`Connection activity: ${description}`}
            onClick={event=>{event.stopPropagation();setSelected(key)}}
            onKeyDown={event=>{if(event.key==='Enter'||event.key===' '){event.preventDefault();event.stopPropagation();setSelected(key)}}}
            onMouseEnter={() => setHovered(key)}
            onMouseLeave={() => setHovered(null)}
          >
            <title>{description}</title>
            {/* Invisible wider path for easier hover */}
            <path
              d={pathD}
              fill="none"
              stroke="transparent"
              strokeWidth={12}
              style={{ cursor: 'pointer' }}
            />
            <path
              d={pathD}
              fill="none"
              stroke={emphasized ? '#bda9ed' : (activeServiceId && related) ? 'rgba(167,139,250,0.5)' : related ? 'rgba(167,139,250,0.3)' : 'rgba(255,255,255,0.08)'}
              strokeWidth={emphasized ? 2 : 1.25}
              strokeDasharray={related ? undefined : '4 5'}
              style={{ transition: 'stroke 0.2s, stroke-width 0.2s' }}
            />
            {moving&&(flow?.sentBytes||0)>0&&<circle r={2.1} fill="#a7c8bc" opacity={0.8} aria-hidden="true"><animateMotion begin={`${-(index%7)*0.31}s`} dur="3.2s" repeatCount="indefinite" path={pathD}/></circle>}
            {moving&&(flow?.receivedBytes||0)>0&&<circle r={2.1} fill="#afbdd7" opacity={0.8} aria-hidden="true"><animateMotion begin={`${-0.95-(index%7)*0.31}s`} dur="3.6s" repeatCount="indefinite" path={pathD} keyPoints="1;0" keyTimes="0;1" calcMode="linear"/></circle>}
            <circle
              cx={endX}
              cy={endY}
              r={emphasized ? 3.5 : 3}
              fill={emphasized ? 'rgba(167,139,250,0.55)' : 'rgba(255,255,255,0.25)'}
              style={{ transition: 'all 0.2s' }}
            />
          </g>
        )
      })}
    </svg>
    {selectedConnection&&<NetworkFlowDetails flow={measured(selectedConnection.fromId,selectedConnection.toId)} at={flows?.sampledAt} label={`${selectedConnection.fromName||"Source"} → ${selectedConnection.toName||"Target"}`} projectId={projectId} onClose={()=>setSelected(null)}/>}
    </>
  )
}

export default memo(ConnectionLines)
