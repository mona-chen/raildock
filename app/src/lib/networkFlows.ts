import { fetchJson } from './api'
export interface NetworkFlow {
  id: string; fromId: string; toId: string; state: 'sampled'|'warming'|'unavailable'|'disabled'
  sentBytes?: number; receivedBytes?: number; connections?: number; windowSeconds?: number; lastActivityAt?: string
}
export interface NetworkFlows {enabled: boolean; sampledAt?: string; error?: string; coverage?: string; links: NetworkFlow[]}
export interface FlowSettings {enabled: boolean; retentionDays: number}
export const networkFlowsApi = {
  project: (id: string, env?: string): Promise<NetworkFlows> => fetchJson(`/api/projects/${id}/network_flows${env?`?environment_id=${encodeURIComponent(env)}`:''}`),
  settings: (id: string): Promise<{settings: FlowSettings; error?: string}> => fetchJson(`/api/servers/${id}/network_flow_settings`),
  save: (id: string, settings: FlowSettings): Promise<{settings: FlowSettings}> => fetchJson(`/api/servers/${id}/network_flow_settings`, {method:'PATCH',body: JSON.stringify({settings:{enabled:settings.enabled,retention_days:settings.retentionDays}})}),
  history: (projectId: string, linkId: string): Promise<{sampledAt: string; sentBytes: number; receivedBytes: number; connections: number}[]> => fetchJson(`/api/projects/${projectId}/network_flows/${linkId}/history`),
}
export function flowActive(flow?: NetworkFlow, at?: string, now = Date.now()) {
  return Boolean(flow?.state==='sampled' && at && now-new Date(at).getTime()>=0 && now-new Date(at).getTime()<25000 && ((flow.sentBytes||0)>0||(flow.receivedBytes||0)>0))
}
export function flowBytes(value = 0) { return value>=1048576?`${(value/1048576).toFixed(1)} MB`:value>=1024?`${(value/1024).toFixed(1)} KB`:`${value} B` }
