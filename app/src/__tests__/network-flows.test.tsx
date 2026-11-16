import { beforeEach, expect, it, vi } from 'vitest'
import { fireEvent, render, screen } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { flowActive, networkFlowsApi } from '@/lib/networkFlows'
import ConnectionLines from '@/features/project-canvas/components/ConnectionLines'
vi.mock('framer-motion',()=>({useReducedMotion:()=>false}))
const now=Date.now()
const flow={id:'1',fromId:'a',toId:'b',state:'sampled' as const,sentBytes:100,receivedBytes:0,connections:1,windowSeconds:10}
beforeEach(()=>vi.useRealTimers())
it('only marks fresh measured byte increases as active',()=>{
  expect(flowActive(flow,new Date(now).toISOString(),now)).toBe(true)
  expect(flowActive({...flow,sentBytes:0},new Date(now).toISOString(),now)).toBe(false)
  expect(flowActive({...flow,state:'unavailable'},new Date(now).toISOString(),now)).toBe(false)
  expect(flowActive(flow,new Date(now-30000).toISOString(),now)).toBe(false)
})
it('animates measured direction and stops when visual animation is disabled',()=>{
  const connections=[{from:{x:10,y:10},to:{x:400,y:10},fromId:'a',toId:'b'}]
  const props={connections,flows:{enabled:true,sampledAt:new Date(now).toISOString(),links:[flow]}}
  const {container,rerender}=render(<ConnectionLines {...props} animate/>)
  expect(container.querySelectorAll('animateMotion')).toHaveLength(1)
  expect(screen.getByRole('button',{name:/100 B source to target/})).toBeInTheDocument()
  rerender(<ConnectionLines {...props} animate={false}/>)
  expect(container.querySelectorAll('animateMotion')).toHaveLength(0)
})

it('opens the note only on selection and closes it with Escape',()=>{
  vi.spyOn(networkFlowsApi,'history').mockResolvedValue([])
  const client=new QueryClient()
  render(<QueryClientProvider client={client}><ConnectionLines projectId="1" connections={[{from:{x:10,y:10},to:{x:400,y:10},fromId:'a',toId:'b'}]} flows={{enabled:true,sampledAt:new Date().toISOString(),links:[flow]}}/></QueryClientProvider>)
  expect(screen.queryByRole('region',{name:'Connection activity'})).not.toBeInTheDocument()
  fireEvent.keyDown(screen.getByRole('button',{name:/Connection activity:/}),{key:'Enter'})
  expect(screen.getByRole('region',{name:'Connection activity'})).toBeInTheDocument()
  fireEvent.keyDown(document,{key:'Escape'})
  expect(screen.queryByRole('region',{name:'Connection activity'})).not.toBeInTheDocument()
  client.clear()
})
