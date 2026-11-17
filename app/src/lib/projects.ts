import type { Project } from '@/types'

/**
 * A background deletion blocks a project until the server reports it stalled.
 * Older backends only send `deletionStatus`, so fall back to the status there.
 */
export function deletionInFlight(project: Pick<Project, 'deletionStatus' | 'deletionPending'>): boolean {
  if (project.deletionPending != null) return project.deletionPending
  return project.deletionStatus === 'queued' || project.deletionStatus === 'running'
}
