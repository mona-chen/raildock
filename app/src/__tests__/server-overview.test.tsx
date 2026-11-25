import { describe, expect, it, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import ServerOverview from '@/features/servers/ServerOverview'
import { operatingSystem } from '@/features/servers/OperatingSystem'
import type { Server } from '@/types'

const server={id:'1',name:'Production',host:'10.0.0.1',os:'Ubuntu 24.04.1 LTS',status:'connected',projectIds:['1'],dockerVersion:'28.0.1',dokkuVersion:'0.38.1',proxyMode:'external',resourceSummary:{available:true,cpu:17.59,cpuCores:8,memory:50,memoryUsed:4*1024**3,memoryTotal:8*1024**3,memoryAvailable:4*1024**3,disk:20,diskUsed:20*1024**3,diskTotal:100*1024**3,sampledAt:new Date().toISOString()}} as Server
const callbacks={onResources:vi.fn(),onHttp:vi.fn(),onUpdates:vi.fn(),onSettings:vi.fn(),onImport:vi.fn(),onAdopt:vi.fn(),onRemove:vi.fn(),onValidate:vi.fn(),validating:false,canRemove:true}

describe('server overview',()=>{
  it('shows OS version, CPU capacity and used/total bytes with a maintenance entry point',async()=>{
    render(<ServerOverview server={{...server,packageUpdates:{count:3,checkedAt:new Date().toISOString()}}} {...callbacks}/>)
    expect(screen.getByText('Ubuntu 24.04.1 LTS')).toBeInTheDocument()
    expect(screen.getByText('8 CPU cores')).toBeInTheDocument()
    expect(screen.getByText('4.0 GiB / 8.0 GiB used')).toBeInTheDocument()
    expect(screen.getByText('20.0 GiB / 100.0 GiB used')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button',{name:'3 package updates'}))
    expect(callbacks.onUpdates).toHaveBeenCalled()
  })
  it('does not display disabled metrics as current usage',()=>{
    render(<ServerOverview server={{...server,resourceSummary:{...server.resourceSummary!,collectionEnabled:false}}} {...callbacks}/>)
    expect(screen.getByText('Collection disabled')).toBeInTheDocument()
    expect(screen.queryByRole('meter')).not.toBeInTheDocument()
    expect(screen.queryByText('4.0 GiB / 8.0 GiB used')).not.toBeInTheDocument()
  })
  it('does not invent a version for legacy OS labels',()=>{
    expect(operatingSystem('Ubuntu (detected)')).toMatchObject({name:'Ubuntu',verifiedVersion:false})
    expect(operatingSystem('Unknown')).toMatchObject({name:'Operating system unknown',verifiedVersion:false})
    expect(operatingSystem('Debian GNU/Linux 13')).toMatchObject({verifiedVersion:true})
  })
})
