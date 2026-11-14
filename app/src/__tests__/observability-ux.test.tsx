import { beforeEach, expect, it, vi } from 'vitest'
import { fireEvent, render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import VariablesTab from '@/features/service-panel/tabs/VariablesTab'
import LogsTab from '@/features/service-panel/tabs/LogsTab'
import MetricsTab from '@/features/service-panel/tabs/MetricsTab'
import ProcessScaling from '@/features/service-panel/tabs/ProcessScaling'
import { DeploymentLogPanel } from '@/features/service-panel/tabs/DeployTab'
import type { Service } from '@/types'
const state = vi.hoisted(() => ({ save: vi.fn(), scale: vi.fn(), retry: vi.fn(), remove: vi.fn(), logs: {} as Record<string, unknown>, history: {} as Record<string, unknown>, deployment: {} as Record<string, unknown> }))
vi.mock('@/hooks/useProjects', () => ({ useProject: () => ({data:{sharedVars:[]}}) }))
vi.mock('@/hooks/useServices', () => ({
 useSetEnvVar: () => ({mutate:state.save,isPending:false}), useSetEnvVars: () => ({mutate:vi.fn()}), useUnsetEnvVar: () => ({mutate:state.remove}),
 useScaleProcess: () => ({mutate:state.scale,isPending:false}), useServiceLogs: () => state.logs,
 useServiceMetrics: () => ({data:null}), useServiceMetricsHistory: () => state.history,
 useServiceDeployments: () => ({data:[]}), useDeployment: () => state.deployment,
}))
vi.mock('@/hooks/useWebSocketLogs', () => ({ useWebSocketLogs: () => ({lines:[],connectionState:'fallback',clear:vi.fn()}) }))
const svc = {id:'1',projectId:'1',name:'api',type:'app',envVars:[{key:'TOKEN',value:'original'}],domains:[],storageMounts:[]} as unknown as Service
beforeEach(() => { vi.clearAllMocks(); state.logs={data:[],isError:true,refetch:state.retry}; state.history={isError:true,refetch:state.retry}; state.deployment={data:{deployLog:'first line\nERROR failed\nthird line'}} })
it('retains a variable draft after a failed save and accepts an empty value', () => {
 state.save.mockImplementation((_data, callbacks) => callbacks.onError())
 render(<MemoryRouter><VariablesTab svc={svc} /></MemoryRouter>)
 fireEvent.click(screen.getByRole('button',{name:'Edit'}))
 fireEvent.change(screen.getByLabelText('Value for TOKEN'),{target:{value:''}})
 fireEvent.click(screen.getByRole('button',{name:'Save'}))
 expect(state.save).toHaveBeenCalledWith(expect.objectContaining({key:'TOKEN',value:''}),expect.anything())
 expect(screen.getByLabelText('Value for TOKEN')).toHaveValue('')
 expect(screen.getByRole('alert')).toHaveTextContent('Your edit is retained')
})
it('reviews variable deletion before sending the request', () => {
 render(<MemoryRouter><VariablesTab svc={svc} /></MemoryRouter>)
 fireEvent.click(screen.getByRole('button',{name:'Delete TOKEN'}))
 expect(state.remove).not.toHaveBeenCalled()
 fireEvent.click(screen.getByRole('button',{name:'Delete variable'}))
 expect(state.remove).toHaveBeenCalledWith({id:'1',key:'TOKEN'},expect.anything())
})
it('reports a failed log request and provides retry', () => {
 render(<LogsTab serviceId="1" />)
 expect(screen.getByText('Could not load logs')).toBeInTheDocument()
 fireEvent.click(screen.getByRole('button',{name:'Fetch logs'}))
 expect(state.retry).toHaveBeenCalledOnce()
})
it('does not report a failed metrics request as empty history', () => {
 render(<MetricsTab svc={svc} />)
 expect(screen.getByText('Could not load metric history')).toBeInTheDocument()
 expect(screen.queryByText('No samples in this time range')).not.toBeInTheDocument()
})
it('stages a scale target and reviews zero before applying', () => {
 render(<ProcessScaling serviceId="1" process={{name:'web',quantity:2,running:2,command:'server'}} />)
 fireEvent.change(screen.getByLabelText('web replicas'),{target:{value:'0'}})
 expect(state.scale).not.toHaveBeenCalled()
 fireEvent.click(screen.getByRole('button',{name:'Apply'}))
 expect(state.scale).not.toHaveBeenCalled()
 fireEvent.click(screen.getByRole('button',{name:'Set replicas to zero'}))
 expect(state.scale).toHaveBeenCalledWith({id:'1',processName:'web',quantity:0},expect.anything())
})
it('searches deployment output while retaining original line numbers', () => {
 render(<DeploymentLogPanel deploymentId="1" />)
 fireEvent.change(screen.getByLabelText('Search deployment logs'),{target:{value:'ERROR'}})
 expect(screen.getByText('ERROR failed')).toBeInTheDocument()
 expect(screen.queryByText('first line')).not.toBeInTheDocument()
 expect(screen.getByText('2')).toBeInTheDocument()
 expect(screen.getByRole('button',{name:'Wrap lines'})).toHaveAttribute('aria-pressed','true')
})
