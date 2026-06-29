/**
 * RailDock API Client
 *
 * Typed REST API client for the Rails backend.
 * All endpoints return Promises and are fully typed.
 */

import type {
  Project,
  Service,
  Server,
  GitSource,
  GitRepo,
  GitHubAppConfig,
  SystemSetting,
  Module,
  ActivityEvent,
  Template,
  Organization,
  OrganizationMembership,
  OrganizationInvitation,
  InvitationDetails,
  Domain,
  AppUpdateInfo,
  Deployment as ApiDeployment,
  DeploymentDetail as ApiDeploymentDetail,
  RecoveryOverview,
  BackupDestination,
  PostgresPitrConfig,
  RestoreDrill,
  Backup,
  RepositoryImportPreview,
} from '@/types'

import { useAuthStore } from '@/stores/useAuthStore'
import {
  camelizeKeys,
  wrapBody,
  normalizeService,
  normalizeProject,
  normalizeServer,
  normalizeActivityEvent,
  normalizeGitSource,
} from './apiTransforms'

// ── Config ───────────────────────────────────

const API_BASE = import.meta.env.VITE_API_BASE_URL || ''

// Request timeout in milliseconds
const REQUEST_TIMEOUT = 30000

// ── Abort Controller Helper ──────────────────────────────────────────────

function createAbortableFetch(url: string, options?: RequestInit): { controller: AbortController; fetchPromise: Promise<Response> } {
  const controller = new AbortController()
  const signal = controller.signal
  const fetchPromise = fetch(url, { ...options, signal })
  return { controller, fetchPromise }
}

// ── Fetch Wrapper ────────────────────────────

function getAuthHeaders(): Record<string, string> {
  const state = useAuthStore.getState()
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  }
  if (state.token) {
    headers['Authorization'] = `Bearer ${state.token}`
  }
  if (state.currentOrganizationId) {
    headers['X-Organization-ID'] = state.currentOrganizationId
  }
  return headers
}

async function fetchJson<T>(path: string, options?: RequestInit): Promise<T> {
  const { controller, fetchPromise } = createAbortableFetch(`${API_BASE}${path}`, {
    headers: getAuthHeaders(),
    ...options,
  })


  // Apply request timeout
  const timeoutId = setTimeout(() => controller.abort(), REQUEST_TIMEOUT)

  try {
    const res = await fetchPromise
    clearTimeout(timeoutId)

    if (!res.ok) {
      if (res.status === 401) {
        useAuthStore.getState().logout()
      }
      const err = await res.json().catch(() => ({}))
      throw new Error(err.error || `HTTP ${res.status}`)
    }
    // 204 No Content — nothing to parse
    if (res.status === 204) {
      return undefined as T
    }
    const data = await res.json()
    return camelizeKeys(data) as T
  } catch (error) {
    clearTimeout(timeoutId)
    if (error instanceof Error && error.name === 'AbortError') {
      throw new Error('Request timed out')
    }
    throw error
  }
}

// ── Projects API ─────────────────────────────

export const projectsApi = {
  list: async (): Promise<Project[]> => {
    const data = await fetchJson<unknown[]>('/api/projects')
    return data.map(normalizeProject)
  },

  get: async (id: string): Promise<Project> => {
    const data = await fetchJson<unknown>(`/api/projects/${id}`)
    return normalizeProject(data)
  },

  create: async (data: { name: string; description: string; environment?: string }): Promise<Project> => {
    const res = await fetchJson<unknown>('/api/projects', { method: 'POST', body: wrapBody('project', data) })
    return normalizeProject(res)
  },

  update: async (id: string, data: Partial<Project>): Promise<Project> => {
    const res = await fetchJson<unknown>(`/api/projects/${id}`, { method: 'PATCH', body: wrapBody('project', data) })
    return normalizeProject(res)
  },

  destroy: async (id: string): Promise<void> => {
    await fetchJson(`/api/projects/${id}`, { method: 'DELETE' })
  },

  updateSharedVars: async (id: string, vars: { key: string; value: string }[]): Promise<void> => {
    await fetchJson(`/api/projects/${id}/shared_vars`, { method: 'PATCH', body: wrapBody('project', { vars }) })
  },

  deployAll: async (id: string): Promise<{ queued: number; services: string[] }> => {
    return fetchJson(`/api/projects/${id}/deploy_all`, { method: 'POST' })
  },

  cancelDeployments: async (id: string): Promise<{ cancelled: number }> => {
    return fetchJson(`/api/projects/${id}/cancel_deployments`, { method: 'POST' })
  },

  restartAll: async (id: string): Promise<{ queued: number; services: string[] }> => {
    return fetchJson(`/api/projects/${id}/restart_all`, { method: 'POST' })
  },

  stopAll: async (id: string): Promise<{ success: string[]; failed: { name: string; error: string }[] }> => {
    return fetchJson(`/api/projects/${id}/stop_all`, { method: 'POST' })
  },
}

// ── Services API ─────────────────────────────

export const servicesApi = {
  list: async (projectId: string): Promise<Service[]> => {
    const data = await fetchJson<unknown[]>(`/api/projects/${projectId}/services`)
    return data.map(normalizeService)
  },

  get: async (id: string): Promise<Service> => {
    const data = await fetchJson<unknown>(`/api/services/${id}`)
    return normalizeService(data)
  },

  create: async (projectId: string, data: { name: string; subtype: string; category: string; builder?: string; git_repo?: string; branch?: string; docker_image?: string; version?: string; root_directory?: string }): Promise<Service> => {
    const body = { ...data, serviceType: data.category }
    const res = await fetchJson<unknown>(`/api/projects/${projectId}/services`, { method: 'POST', body: wrapBody('service', body) })
    return normalizeService(res)
  },

  destroy: async (id: string): Promise<void> => {
    await fetchJson(`/api/services/${id}`, { method: 'DELETE' })
  },

  update: async (id: string, data: Partial<Service>): Promise<Service> => {
    const res = await fetchJson<unknown>(`/api/services/${id}`, { method: 'PATCH', body: wrapBody('service', data) })
    return normalizeService(res)
  },

  deploy: async (id: string): Promise<void> => {
    await fetchJson(`/api/services/${id}/deploy`, { method: 'POST' })
  },

  start: async (id: string): Promise<void> => {
    await fetchJson(`/api/services/${id}/start`, { method: 'POST' })
  },

  stop: async (id: string): Promise<void> => {
    await fetchJson(`/api/services/${id}/stop`, { method: 'POST' })
  },

  restart: async (id: string): Promise<void> => {
    await fetchJson(`/api/services/${id}/restart`, { method: 'POST' })
  },

  rebuild: async (id: string): Promise<void> => {
    await fetchJson(`/api/services/${id}/rebuild`, { method: 'POST' })
  },

  scale: async (id: string, processName: string, quantity: number): Promise<void> => {
    await fetchJson(`/api/services/${id}/scale`, { method: 'POST', body: JSON.stringify({ processName, quantity }) })
  },

  setEnvVar: async (
    id: string,
    key: string,
    value: string,
    source?: string
  ): Promise<{ restart_deployment_id?: string }> => {
    return fetchJson(`/api/services/${id}/env-vars`, { method: 'POST', body: JSON.stringify({ key, value, source }) })
  },

  unsetEnvVar: async (
    id: string,
    key: string
  ): Promise<{ restart_deployment_id?: string }> => {
    return fetchJson(`/api/services/${id}/env-vars/${encodeURIComponent(key)}`, { method: 'DELETE' })
  },

  addDomain: async (id: string, hostname: string, port: number, targetPort?: number): Promise<void> => {
    await fetchJson(`/api/services/${id}/domains`, { method: 'POST', body: JSON.stringify({ hostname, port, target_port: targetPort }) })
  },

  removeDomain: async (id: string, hostname: string): Promise<void> => {
    await fetchJson(`/api/services/${id}/domains/${hostname}`, { method: 'DELETE' })
  },

  generateDomain: async (id: string): Promise<Domain> => {
    return fetchJson(`/api/services/${id}/generate_domain`, { method: 'POST' })
  },

  addStorageMount: async (id: string, hostPath: string, containerPath: string): Promise<void> => {
    await fetchJson(`/api/services/${id}/storage`, { method: 'POST', body: JSON.stringify({ hostPath, containerPath }) })
  },

  removeStorageMount: async (id: string, hostPath: string): Promise<void> => {
    await fetchJson(`/api/services/${id}/storage/${encodeURIComponent(hostPath)}`, { method: 'DELETE' })
  },

  logs: async (id: string): Promise<{ timestamp: string; processType: string; message: string }[]> => {
    return fetchJson(`/api/services/${id}/logs`)
  },

  databaseInfo: async (id: string): Promise<{
    success: boolean
    error?: string
    type?: string
    dsn?: string
    url?: string
    host?: string
    port?: number
    username?: string
    password?: string
    database?: string
    status?: string
    version?: string
    internal_ip?: string
  }> => {
    return fetchJson(`/api/services/${id}/database_info`)
  },

  metrics: async (id: string): Promise<{ cpu: number; memory: number; networkIn: number; networkOut: number }> => {
    return fetchJson(`/api/services/${id}/metrics`)
  },

  deployments: async (id: string): Promise<ApiDeployment[]> => {
    return fetchJson(`/api/services/${id}/deployments`)
  },

  backups: async (id: string): Promise<Backup[]> => {
    return fetchJson(`/api/services/${id}/backups`)
  },

  backupSchedules: async (id: string): Promise<{ id: string; frequency: string; retentionCount: number; lastRunAt: string; nextRunAt: string }[]> => {
    return fetchJson(`/api/services/${id}/backup_schedules`)
  },

  createBackupSchedule: async (id: string, data: { frequency: string; retentionCount: number }): Promise<void> => {
    await fetchJson(`/api/services/${id}/create_backup_schedule`, { method: 'POST', body: JSON.stringify({ backup_schedule: data }) })
  },

  destroyBackupSchedule: async (id: string, scheduleId: string): Promise<void> => {
    await fetchJson(`/api/services/${id}/backup_schedules/${scheduleId}`, { method: 'DELETE' })
  },

  deployment: async (deploymentId: string): Promise<ApiDeploymentDetail> => {
    return fetchJson(`/api/deployments/${deploymentId}`)
  },

  cancelDeployment: async (deploymentId: string): Promise<{ success: boolean; deploymentId: string; status: string }> => {
    return fetchJson(`/api/deployments/${deploymentId}/cancel`, { method: 'POST' })
  },

  link: async (id: string, targetId: string): Promise<{ success: boolean; linked_service_ids: string[] }> => {
    return fetchJson(`/api/services/${id}/link`, { method: 'POST', body: JSON.stringify({ target_id: targetId }) })
  },

  unlink: async (id: string, targetId: string): Promise<{ success: boolean; linked_service_ids: string[] }> => {
    return fetchJson(`/api/services/${id}/unlink`, { method: 'POST', body: JSON.stringify({ target_id: targetId }) })
  },

  linkedBy: async (id: string): Promise<Service[]> => {
    const data = await fetchJson<unknown[]>(`/api/services/${id}/linked_by`)
    return data.map(normalizeService)
  },

  backup: async (id: string, backupDestinationId?: string): Promise<{ success: boolean }> => {
    return fetchJson(`/api/services/${id}/backup`, { method: 'POST', body: JSON.stringify({ backup_destination_id: backupDestinationId }) })
  },

  recovery: async (id: string): Promise<RecoveryOverview> => fetchJson(`/api/services/${id}/recovery`),

  createBackupDestination: async (id: string, data: Record<string, string>): Promise<BackupDestination> =>
    fetchJson(`/api/services/${id}/recovery/destinations`, { method: 'POST', body: JSON.stringify(data) }),

  verifyBackupDestination: async (id: string, destinationId: string): Promise<BackupDestination> =>
    fetchJson(`/api/services/${id}/recovery/destinations/${destinationId}/verify`, { method: 'POST' }),

  deleteBackupDestination: async (id: string, destinationId: string): Promise<void> =>
    fetchJson(`/api/services/${id}/recovery/destinations/${destinationId}`, { method: 'DELETE' }),

  snapshotVolume: async (id: string, storageMountId: string, backupDestinationId?: string): Promise<void> =>
    fetchJson(`/api/services/${id}/recovery/volumes/${storageMountId}/snapshot`, { method: 'POST', body: JSON.stringify({ backup_destination_id: backupDestinationId }) }),

  configurePitr: async (id: string, backupDestinationId: string, retentionDays: number): Promise<PostgresPitrConfig> =>
    fetchJson(`/api/services/${id}/recovery/pitr`, { method: 'PUT', body: JSON.stringify({ backup_destination_id: backupDestinationId, retention_days: retentionDays }) }),

  disablePitr: async (id: string): Promise<PostgresPitrConfig> =>
    fetchJson(`/api/services/${id}/recovery/pitr`, { method: 'DELETE' }),

  runRestoreDrill: async (id: string, backupId: string): Promise<RestoreDrill> =>
    fetchJson(`/api/services/${id}/recovery/backups/${backupId}/drills`, { method: 'POST' }),

  downloadBackup: async (id: string, backupId: string): Promise<Blob> => {
    const res = await fetch(`${API_BASE}/api/services/${id}/backups/${backupId}/download`, { headers: getAuthHeaders() })
    if (!res.ok) throw new Error('Backup artifact is unavailable')
    return res.blob()
  },

  restoreBackup: async (id: string, backupId: string): Promise<{ success: boolean }> => {
    return fetchJson(`/api/services/${id}/backups/${backupId}/restore`, { method: 'POST' })
  },

  deleteBackup: async (id: string, backupId: string): Promise<void> => {
    await fetchJson(`/api/services/${id}/backups/${backupId}`, { method: 'DELETE' })
  },

  restore: async (id: string, file?: File): Promise<{ success: boolean }> => {
    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), REQUEST_TIMEOUT)

    try {
      const res = await fetch(`${API_BASE}/api/services/${id}/restore`, {
        method: 'POST',
        headers: getAuthHeaders(),
        body: file || undefined,
        signal: controller.signal,
      })
      clearTimeout(timeoutId)

      if (!res.ok) {
        const err = await res.json().catch(() => ({}))
        throw new Error(err.error || `HTTP ${res.status}`)
      }
      return res.json()
    } catch (error) {
      clearTimeout(timeoutId)
      if (error instanceof Error && error.name === 'AbortError') {
        throw new Error('Request timed out')
      }
      throw error
    }
  },

  rollback: async (id: string, deploymentId: string): Promise<void> => {
    return fetchJson(`/api/services/${id}/rollback`, { method: 'POST', body: JSON.stringify({ deployment_id: deploymentId }) })
  },

  containerStatus: async (id: string): Promise<{ status: string; output?: string }> => {
    return fetchJson(`/api/services/${id}/container_status`)
  },

  // One-off tasks
  runOneOff: async (id: string, command: string): Promise<{ success: boolean; output: string }> => {
    return fetchJson(`/api/services/${id}/run`, { method: 'POST', body: JSON.stringify({ command }) })
  },

  // Enter container
  enter: async (id: string, command: string): Promise<{ success: boolean; output: string }> => {
    return fetchJson(`/api/services/${id}/enter`, { method: 'POST', body: JSON.stringify({ command }) })
  },

  // App lock/unlock
  app_lock: async (id: string): Promise<{ success: boolean; output: string }> => {
    return fetchJson(`/api/services/${id}/app_lock`, { method: 'POST' })
  },

  app_unlock: async (id: string): Promise<{ success: boolean; output: string }> => {
    return fetchJson(`/api/services/${id}/app_unlock`, { method: 'POST' })
  },

  appLocked: async (id: string): Promise<{ locked: boolean }> => {
    return fetchJson(`/api/services/${id}/app_locked`)
  },

  // Config show
  configShow: async (projectId: string, serviceId: string): Promise<{ success: boolean; output: string }> => {
    return fetchJson(`/api/projects/${projectId}/services/${serviceId}/config_show`)
  },

  // Traefik config
  traefikConfig: async (projectId: string, serviceId: string): Promise<{ success: boolean; output: string }> => {
    return fetchJson(`/api/projects/${projectId}/services/${serviceId}/traefik_config`)
  },

  // Storage list
  storageList: async (projectId: string, serviceId: string): Promise<{ success: boolean; output: string }> => {
    return fetchJson(`/api/projects/${projectId}/services/${serviceId}/storage_list`)
  },
}

// ── Servers API ──────────────────────────────

export interface ServerTestResult {
  success: boolean
  error?: string
  host?: string
  sshUser?: string
  hostKey?: string
  hostKeyFingerprint?: string
  dokkuVersion?: string
  dockerVersion?: string
  os?: string
  uptime?: string
  publicIp?: string
  logs?: string[]
}

export const serversApi = {
  list: async (): Promise<Server[]> => {
    const data = await fetchJson<unknown[]>('/api/servers')
    return data.map(normalizeServer)
  },

  create: async (data: { name: string; host: string; sshKey?: string; sshUser?: string; baseDomain?: string; autoDomains?: boolean; hostKey?: string; hostKeyFingerprint?: string }): Promise<Server> => {
    const res = await fetchJson<unknown>('/api/servers', { method: 'POST', body: wrapBody('server', data) })
    return normalizeServer(res)
  },

  test: async (data: { host: string; sshUser?: string }): Promise<ServerTestResult> => {
    return fetchJson('/api/servers/test', { method: 'POST', body: wrapBody('server', data) })
  },

  provision: async (data: { host: string; adminUser?: string; setupId: string }): Promise<{ setupId: string }> => {
    return fetchJson('/api/servers/provision', { method: 'POST', body: wrapBody('server', data) })
  },

  update: async (id: string, data: Partial<Server>): Promise<Server> => {
    const res = await fetchJson<unknown>(`/api/servers/${id}`, { method: 'PATCH', body: wrapBody('server', data) })
    return normalizeServer(res)
  },

  validate: async (id: string): Promise<{ success: boolean; error?: string }> => {
    return fetchJson(`/api/servers/${id}/validate`, { method: 'POST' })
  },

  destroy: async (id: string): Promise<void> => {
    await fetchJson(`/api/servers/${id}`, { method: 'DELETE' })
  },
}

// ── Git Sources API ──────────────────────────

export const gitSourcesApi = {
  list: async (organizationId?: string): Promise<GitSource[]> => {
    const path = organizationId ? `/api/organizations/${organizationId}/git-sources` : '/api/git-sources'
    const data = await fetchJson<unknown[]>(path)
    return data.map(normalizeGitSource)
  },

  connect: async (provider: string, token: string, organizationId?: string): Promise<GitSource> => {
    const body: Record<string, unknown> = { provider, access_token: token }
    if (organizationId) body.organization_id = organizationId
    const res = await fetchJson<unknown>('/api/git-sources', { method: 'POST', body: JSON.stringify(body) })
    return normalizeGitSource(res)
  },

  disconnect: async (id: string): Promise<void> => {
    await fetchJson(`/api/git-sources/${id}`, { method: 'DELETE' })
  },

  repos: async (id: string): Promise<{ repos: GitRepo[]; syncing: boolean }> => {
    return fetchJson(`/api/git-sources/${id}/repos`)
  },

  config: async (): Promise<{ githubApp: GitHubAppConfig }> => {
    return fetchJson('/api/config')
  },

  installUrl: (appSlug: string, state: Record<string, unknown>): string => {
    const encodedState = btoa(JSON.stringify(state)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
    return `https://github.com/apps/${appSlug}/installations/new?state=${encodedState}`
  },
}

// ── Admin Settings API ───────────────────────

export const adminSettingsApi = {
  list: async (): Promise<SystemSetting[]> => {
    return fetchJson('/api/admin/settings')
  },

  update: async (settings: Record<string, string | undefined>): Promise<{ success: boolean }> => {
    return fetchJson('/api/admin/settings', { method: 'PATCH', body: JSON.stringify(settings) })
  },

  testGitHubApp: async (): Promise<{ valid: boolean; name?: string; description?: string; htmlUrl?: string; error?: string }> => {
    return fetchJson('/api/admin/settings/test-github-app', { method: 'POST' })
  },

  createGitHubAppManifest: async (): Promise<{ manifest: Record<string, unknown>; formUrl: string }> => {
    return fetchJson('/api/admin/github-app-manifest')
  },

  deleteGitHubApp: async (): Promise<{ success: boolean; message: string }> => {
    return fetchJson('/api/admin/github-app', { method: 'DELETE' })
  },

  finishGitHubAppSetup: async (
    installationId: string,
    organizationId?: string,
  ): Promise<{ authorizationUrl: string }> => {
    return fetchJson('/api/github-apps/finish-setup', {
      method: 'POST',
      body: JSON.stringify({
        installation_id: installationId,
        organization_id: organizationId,
      }),
    })
  },

  deleteGitHubAppInstallation: async (installationId: string): Promise<{ success: boolean; message: string }> => {
    return fetchJson(`/api/github-apps/installations/${installationId}`, { method: 'DELETE' })
  },

  testSmtp: async (email?: string): Promise<{ success: boolean; email: string }> => {
    return fetchJson('/api/admin/settings/test-smtp', { method: 'POST', body: JSON.stringify({ email }) })
  },
}

// ── Organizations API ──────────────────────────

export const organizationsApi = {
  list: async (): Promise<Organization[]> => {
    return fetchJson<Organization[]>('/api/organizations')
  },

  get: async (id: string): Promise<Organization> => {
    return fetchJson<Organization>(`/api/organizations/${id}`)
  },

  create: async (data: { name: string; slug: string; avatarUrl?: string }): Promise<Organization> => {
    return fetchJson<Organization>('/api/organizations', { method: 'POST', body: wrapBody('organization', data) })
  },

  destroy: async (id: string): Promise<void> => {
    await fetchJson(`/api/organizations/${id}`, { method: 'DELETE' })
  },

  serverBootstrap: async (id: string): Promise<{ publicKey: string; command: string }> => {
    return fetchJson(`/api/organizations/${id}/server_bootstrap`)
  },

  members: {
    list: async (organizationId: string): Promise<OrganizationMembership[]> => {
      return fetchJson<OrganizationMembership[]>(`/api/organizations/${organizationId}/members`)
    },

    // Add an existing user by email OR, when the user does not yet exist,
    // create a pending invitation and return its details.
    create: async (organizationId: string, data: { email: string; role?: 'admin' | 'member' }): Promise<{
      membership?: OrganizationMembership
      invitation?: OrganizationInvitation
      acceptUrl?: string
      existingUser: boolean
    }> => {
      return fetchJson(`/api/organizations/${organizationId}/members`, {
        method: 'POST',
        body: JSON.stringify(data),
      })
    },

    updateRole: async (organizationId: string, userId: string, role: 'owner' | 'admin' | 'member'): Promise<OrganizationMembership> => {
      return fetchJson<OrganizationMembership>(`/api/organizations/${organizationId}/members/${userId}`, {
        method: 'PATCH',
        body: JSON.stringify({ role }),
      })
    },

    remove: async (organizationId: string, userId: string): Promise<void> => {
      await fetchJson(`/api/organizations/${organizationId}/members/${userId}`, { method: 'DELETE' })
    },
  },

  invitations: {
    list: async (organizationId: string): Promise<OrganizationInvitation[]> => {
      return fetchJson<OrganizationInvitation[]>(`/api/organizations/${organizationId}/invitations`)
    },

    create: async (organizationId: string, data: { email: string; role?: 'admin' | 'member' }): Promise<{
      invitation: OrganizationInvitation
      acceptUrl: string
      existingUser: boolean
    }> => {
      return fetchJson(`/api/organizations/${organizationId}/invitations`, {
        method: 'POST',
        body: JSON.stringify(data),
      })
    },

    revoke: async (organizationId: string, invitationId: string): Promise<void> => {
      await fetchJson(`/api/organizations/${organizationId}/invitations/${invitationId}`, { method: 'DELETE' })
    },
  },
}

// ── Invitations (token-based, no JWT) ──────────────

export const invitationsApi = {
  show: async (token: string): Promise<{ invitation: InvitationDetails }> => {
    return fetchJson<{ invitation: InvitationDetails }>(`/api/invitations/${token}`)
  },

  accept: async (token: string, data: { name?: string; password: string }): Promise<{
    token: string
    user: { id: number; email: string; name: string; admin: boolean }
    organization: { id: string; name: string; slug: string; role: string }
    newAccount: boolean
  }> => {
    const res = await fetch(`${API_BASE}/api/invitations/${token}/accept`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    })
    if (!res.ok) {
      const err = await res.json().catch(() => ({}))
      throw new Error(err.error || 'Failed to accept invitation')
    }
    return camelizeKeys(await res.json()) as {
      token: string
      user: { id: number; email: string; name: string; admin: boolean }
      organization: { id: string; name: string; slug: string; role: string }
      newAccount: boolean
    }
  },
}

// ── Activity API ─────────────────────────────

export const activityApi = {
  list: async (projectId?: string): Promise<ActivityEvent[]> => {
    const path = projectId ? `/api/projects/${projectId}/activity` : '/api/activity'
    const data = await fetchJson<unknown[]>(path)
    return data.map(normalizeActivityEvent)
  },
}

// ── Templates API ────────────────────────────

export const templatesApi = {
  list: async (): Promise<Template[]> => {
    return fetchJson('/api/templates')
  },

  deploy: async (templateId: string, projectId: string): Promise<{ created: { id: string; name: string; type: string; subtype: string }[] }> => {
    return fetchJson(`/api/templates/${templateId}/deploy`, { method: 'POST', body: JSON.stringify({ project_id: projectId }) })
  },
}

// ── Manifest API ─────────────────────────────

export interface ManifestChange {
  serviceName: string
  field: string
  changeType: 'added' | 'removed' | 'modified'
  oldValue: unknown
  newValue: unknown
  severity: 'reload' | 'restart' | 'redeploy'
}

export interface ManifestPreview {
  changes: ManifestChange[]
  severity: 'reload' | 'restart' | 'redeploy'
  totalChanges: number
  bySeverity: Record<string, number>
  warnings: string[]
}

export const manifestApi = {
  get: async (projectId: string): Promise<{
    content: string
    format: string
    driftDetected: boolean
    lastSyncedAt: string | null
    lastAppliedAt: string | null
    synced: boolean
  }> => {
    return fetchJson(`/api/projects/${projectId}/manifest`)
  },

  update: async (projectId: string, content: string, format?: string): Promise<{
    content: string
    format: string
    preview: ManifestChange[]
    severity: string
    warnings: string[]
    synced: boolean
  }> => {
    return fetchJson(`/api/projects/${projectId}/manifest`, {
      method: 'PATCH',
      body: wrapBody('manifest', { content, format }),
    })
  },

  preview: async (projectId: string): Promise<ManifestPreview> => {
    return fetchJson(`/api/projects/${projectId}/manifest/preview`, { method: 'POST' })
  },

  apply: async (projectId: string): Promise<{ jobId: string; status: string; message: string }> => {
    return fetchJson(`/api/projects/${projectId}/manifest/apply`, { method: 'POST' })
  },

  status: async (projectId: string): Promise<{
    synced: boolean
    driftDetected: boolean
    lastSyncedAt: string | null
    lastAppliedAt: string | null
    format: string | null
    hasManifest: boolean
  }> => {
    return fetchJson(`/api/projects/${projectId}/manifest/status`)
  },
}

export const repositoryImportsApi = {
  preview: async (projectId: string, data: { gitSourceId: string; repository: string; branch: string }): Promise<RepositoryImportPreview> =>
    fetchJson(`/api/projects/${projectId}/repository-import/preview`, { method: 'POST', body: JSON.stringify({ git_source_id: data.gitSourceId, repository: data.repository, branch: data.branch }) }),
  apply: async (projectId: string, snapshotToken: string, builderOverrides: Record<string, string> = {}): Promise<{ status: string; serviceCount: number; commitSha: string }> =>
    fetchJson(`/api/projects/${projectId}/repository-import/apply`, { method: 'POST', body: JSON.stringify({ snapshot_token: snapshotToken, builder_overrides: builderOverrides }) }),
}

// ── Modules API ──────────────────────────────

export const modulesApi = {
  list: async (): Promise<Module[]> => {
    // TODO: Create a /api/modules endpoint in the backend
    // For now, fall back to templates
    return fetchJson('/api/modules')
  },
}

// ── Networks API ─────────────────────────────

export const networksApi = {
  list: async (serverId: string): Promise<{
    name: string
    driver: string
    scope: string
    internal: boolean
    containers: string[]
    traefikContainers: string[]
    recommended: boolean
    selectable: boolean
  }[]> => {
    return fetchJson(`/api/servers/${serverId}/networks`)
  },

  validate: async (serverId: string, network: string): Promise<{
    success: boolean
    network: string
    traefikContainers: string[]
  }> => {
    return fetchJson(`/api/servers/${serverId}/networks/validate`, {
      method: 'POST',
      body: JSON.stringify({ network }),
    })
  },
}

// ── Auth API ─────────────────────────────────

export interface AuthSession {
  token: string
  user: {
    id: number
    email: string
    name: string
    admin: boolean
    organizations: {
      id: string
      name: string
      slug: string
      role: 'owner' | 'admin' | 'member'
      memberCount: number
    }[]
  }
  organization?: {
    id: string
    name: string
    slug: string
    role: string
    memberCount: number
  }
}

export const authApi = {
  login: async (email: string, password: string): Promise<AuthSession> => {
    const res = await fetch(`${API_BASE}/api/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    })
    if (!res.ok) {
      const err = await res.json().catch(() => ({}))
      throw new Error(err.error || 'Login failed')
    }
    return camelizeKeys(await res.json()) as AuthSession
  },

  me: async (): Promise<AuthSession['user'] | null> => {
    try {
      return await fetchJson<AuthSession['user']>('/api/me')
    } catch {
      return null
    }
  },

  register: async (data: { name: string; email: string; password: string }): Promise<AuthSession> => {
    const res = await fetch(`${API_BASE}/api/users`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: wrapBody('user', data),
    })
    if (!res.ok) {
      const err = await res.json().catch(() => ({}))
      throw new Error(err.error || 'Registration failed')
    }
    return camelizeKeys(await res.json()) as AuthSession
  },
}

// ── Unified API Export ───────────────────────

// ── Deploy Keys API ──────────────────────────

export const deployKeysApi = {
  list: async (): Promise<{ id: string; name: string; publicKey: string; fingerprint: string; createdAt: string }[]> => {
    return fetchJson('/api/deploy-keys')
  },

  create: async (data: { name: string }): Promise<{ id: string; name: string; publicKey: string; fingerprint: string }> => {
    return fetchJson('/api/deploy-keys', { method: 'POST', body: JSON.stringify(data) })
  },

  destroy: async (id: string): Promise<void> => {
    await fetchJson(`/api/deploy-keys/${id}`, { method: 'DELETE' })
  },
}

// ── Update API ───────────────────────────────

export const updateApi = {
  getInfo: async (): Promise<AppUpdateInfo> => {
    return fetchJson('/api/admin/update')
  },

  check: async (): Promise<AppUpdateInfo> => {
    return fetchJson('/api/admin/update/check', { method: 'POST' })
  },

  apply: async (): Promise<{ success: boolean; message?: string; error?: string }> => {
    return fetchJson('/api/admin/update/apply', { method: 'POST' })
  },

  setAutoUpdate: async (enabled: boolean): Promise<{ autoUpdateEnabled: boolean }> => {
    return fetchJson('/api/admin/update/auto-update', { method: 'PATCH', body: JSON.stringify({ enabled }) })
  },
}

// ── Unified API Export ───────────────────────

export const api = {
  auth: authApi,
  projects: projectsApi,
  services: servicesApi,
  servers: serversApi,
  gitSources: gitSourcesApi,
  adminSettings: adminSettingsApi,
  activity: activityApi,
  modules: modulesApi,
  templates: templatesApi,
  networks: networksApi,
  organizations: organizationsApi,
  deployKeys: deployKeysApi,
  manifest: manifestApi,
  repositoryImports: repositoryImportsApi,
  updates: updateApi,
}
