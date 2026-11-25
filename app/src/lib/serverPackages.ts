import { fetchJson } from './api'
export interface PackageUpdates {
  status?: 'running'|'completed'|'failed'
  supported?: boolean
  count?: number
  checkedAt?: string
  rebootRequired?: boolean
  diskAvailable?: number
  packages?: {name:string;installed:string;candidate:string}[]
  heldPackages?: string[]
  truncated?: boolean
  error?: string
  message?: string
  logTail?: string
  release?: {supported:boolean;available:boolean;target?:string;checked?:boolean}
  operation?: {id:string;kind:string;status:string;phase?:string;startedAt?:string;updatedAt?:string}
}
export const serverPackagesApi = {
  get: (id:string):Promise<PackageUpdates> => fetchJson(`/api/servers/${id}/packages`),
  check: (id:string):Promise<PackageUpdates> => fetchJson(`/api/servers/${id}/packages`,{method:'POST',body:JSON.stringify({kind:'check'})}),
  install: (id:string,reviewedId:string,confirmation:string):Promise<PackageUpdates> => fetchJson(`/api/servers/${id}/packages`,{method:'POST',body:JSON.stringify({kind:'install',reviewed_id:reviewedId,confirmation,acknowledge_disruption:true})}),
}
