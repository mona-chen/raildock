import { useEffect, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { networkFlowsApi } from '@/lib/networkFlows'
export function useNetworkFlows(projectId: string, environmentId?: string) {
  const [visible,setVisible] = useState(!document.hidden)
  useEffect(()=>{const update=()=>setVisible(!document.hidden);document.addEventListener('visibilitychange',update);return()=>document.removeEventListener('visibilitychange',update)},[])
  return useQuery({queryKey:['network-flows',projectId,environmentId],queryFn:()=>networkFlowsApi.project(projectId,environmentId),enabled:!!projectId&&visible,refetchInterval:visible?10000:false,retry:false})
}
