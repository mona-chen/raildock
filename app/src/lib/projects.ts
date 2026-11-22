import type { Project, Server } from '@/types'

/**
 * A background deletion blocks a project until the server reports it stalled.
 * Older backends only send `deletionStatus`, so fall back to the status there.
 */
export function deletionInFlight(project: Pick<Project, 'deletionStatus' | 'deletionPending'>): boolean {
  if (project.deletionPending != null) return project.deletionPending
  return project.deletionStatus === 'queued' || project.deletionStatus === 'running'
}

/**
 * The server a new project lands on when the user does not pick one. Mirrors
 * `Server.preferred_for_new_project`: a connected server first, then the
 * oldest, so the default matches what the API would choose.
 */
export function preferredServerId(servers: Pick<Server, 'id' | 'status'>[]): string | undefined {
  const rank = (status: Server['status']) => (status === 'connected' ? 0 : status === 'disconnected' ? 1 : 2)
  const byId = (a: string, b: string) => (Number(a) - Number(b)) || a.localeCompare(b)
  return [...servers].sort((a, b) => rank(a.status) - rank(b.status) || byId(a.id, b.id))[0]?.id
}
