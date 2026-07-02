// RailDock: Railway UX + Dokku Engine
// Types organized around "Projects" and "Services" (Railway pattern)
// Services = Dokku apps + Datastores (unified concept)

// ───────────────────────────────────────────────
// Project (top-level container like Railway)
// ───────────────────────────────────────────────

export interface Project {
  id: string
  name: string
  description: string
  environment: 'production' | 'staging' | 'development'
  serviceIds: string[]       // references to services in this project
  serviceCounts: { total: number; app: number; database: number; cache: number }
  sharedVars: SharedVar[]    // project-level env vars (Railway shared variables)
  serverId?: string
  hasDeployments?: boolean
  createdAt: string
}

export interface SharedVar {
  key: string
  value: string
}

// ───────────────────────────────────────────────
// Service (unified: app or datastore)
// Every service appears as a card on the canvas
// ───────────────────────────────────────────────

export type ServiceType = 'app' | 'database' | 'cache' | 'queue' | 'search' | 'service'

export interface Service {
  id: string
  name: string
  type: ServiceType
  subtype: string           // 'web' | 'worker' | 'postgres' | 'redis' | 'mysql' | 'mongo'
  projectId: string
  status: 'running' | 'stopped' | 'deploying' | 'error' | 'building'
  // For apps
  builder?: 'herokuish' | 'pack' | 'dockerfile' | 'nixpacks' | 'railpack' | 'lambda' | 'null'
  processTypes?: ProcessType[]
  gitRepo?: string
  dockerImage?: string
  branch?: string
  lastDeployed?: string
  // For datastores
  version?: string
  exposed?: boolean
  port?: number
  // Common
  linkedServiceIds: string[] // which services this one is linked to (for canvas connections)
  envVars: EnvVar[]
  domains: Domain[]
  detectedPort?: number
  internalHostname?: string
  storageMounts: StorageMount[]
  logs: LogEntry[]
  backups: Backup[]
  // Plugin configs (baked-in, not exposed as "plugins")
  proxy: ProxySettings
  dockerOptions: DockerOption[]
  resourceLimits: ResourceSetting[]
  resourceReservations: ResourceSetting[]
  checks: ChecksSettings
  letsencrypt: LetsEncryptSettings
  git: GitSettings
  traefik: TraefikSettings
  restartPolicy: 'never' | 'on-failure' | 'always' | 'unless-stopped'
  restartMaxRetries: number
  locked: boolean
  autoDeploy: boolean
  webhookUrl?: string
  webhookToken?: string
  rootDirectory?: string
  startCommand?: string
  maintenanceMode: boolean
  managedBy?: 'ui' | 'manifest' | 'hybrid'
  configOverrides?: Record<string, any>
  config?: Record<string, any>
  canvas_x?: number | null
  canvas_y?: number | null
}

export interface ProcessType {
  name: string
  quantity: number
  running: number
  command: string
}

export interface EnvVar {
  key: string
  value: string
  isDokkuInternal?: boolean
  source?: string   // which service this var references (for Railway-style ${{Service.VAR}})
}

export interface Domain {
  id?: string
  hostname: string
  port: number
  targetPort?: number
  ssl: boolean
  letsencrypt: boolean
  temporary?: boolean
  wildcard?: boolean
  sslStatus: 'none' | 'pending' | 'active' | 'failed'
  sslStatusMessage?: string
  sslExpiresAt?: string
  challengeType: 'http' | 'dns'
}

export type StorageMountKind = 'volume' | 'bind' | 'tmpfs'

export interface StorageMount {
  id: string
  hostPath: string
  containerPath: string
  kind: StorageMountKind
}

export interface LogEntry {
  timestamp: string
  processType: string
  message: string
}

export interface Backup {
  id: string
  createdAt: string
  size: number
  status: 'completed' | 'failed' | 'pending' | 'running'
  filePath?: string
  metadata?: Record<string, string>
  backupKind?: 'database' | 'volume' | 'pitrBase' | 'wal'
  encrypted?: boolean
  backupDestinationId?: string
}

export interface BackupDestination {
  id: string
  name: string
  provider: 's3' | 'r2'
  endpoint?: string
  region: string
  bucket: string
  pathPrefix?: string
  status: 'pending' | 'verified' | 'failed'
  configured: boolean
  lastVerifiedAt?: string
  lastError?: string
  recoveryKey?: string
}

export interface PostgresPitrConfig {
  id: string
  enabled: boolean
  status: 'pending' | 'active' | 'error' | 'paused'
  retentionDays: number
  backupDestinationId: string
  lastBaseBackupAt?: string
  lastWalArchivedAt?: string
  lastError?: string
}

export interface RestoreDrill {
  id: string
  backupId: string
  status: 'pending' | 'running' | 'succeeded' | 'failed'
  checksumVerified: boolean
  log?: string
  completedAt?: string
}

export interface RecoveryOverview {
  destinations: BackupDestination[]
  pitr?: PostgresPitrConfig | null
  drills: RestoreDrill[]
}

// ───────────────────────────────────────────────
// Baked-in Plugin Settings (always available)
// ───────────────────────────────────────────────

export interface TraefikSettings {
  labels: Record<string, string>
  properties: Record<string, string>
}

export interface ProxySettings {
  enabled: boolean
  proxyType: 'nginx' | 'caddy' | 'haproxy' | 'traefik' | 'openresty'
  portMappings: PortMapping[]
}

export interface PortMapping {
  scheme: 'http' | 'https' | 'grpc'
  hostPort: number
  containerPort: number
}

export interface DockerOption {
  phase: 'build' | 'deploy' | 'run'
  option: string
}

export interface ResourceSetting {
  processType: string
  cpu?: string
  memory?: string
  memorySwap?: string
  nvidiaGpu?: number
}

export interface ChecksSettings {
  enabled: boolean
  mode?: 'enabled' | 'skipped' | 'disabled'
  wait: number
  timeout: number
  attempts?: number
  waitToRetire?: number
  skipList: string[]
}

export interface LetsEncryptSettings {
  enabled: boolean
  email: string
  staging: boolean
  autoRenew: boolean
  lastIssued?: string
  expiryDate?: string
}

export interface GitSettings {
  deployBranch: string
  keepGitDir: boolean
  revEnvVar: boolean
}

// ───────────────────────────────────────────────
// Templates (Stack Marketplace)
// ───────────────────────────────────────────────

export interface Template {
  id: string
  name: string
  category: string
  description: string
  services: TemplateService[]
  raw?: string
  logo?: string
}

export interface TemplateService {
  name: string
  subtype: string
  type: ServiceType
  category: string
}

// ───────────────────────────────────────────────
// Modules (Heroku add-ons style)
// ───────────────────────────────────────────────

export interface Module {
  id: string
  name: string
  description: string
  icon: string
  category: 'database' | 'service' | 'tool'
  plugins: string[]   // which dokku plugins this module uses
  services: ModuleService[]
}

export interface ModuleService {
  subtype: string
  name: string
  description: string
  defaultVersion: string
}

// ───────────────────────────────────────────────
// Server / Host
// ───────────────────────────────────────────────

export interface Server {
  id: string
  name: string
  host: string
  sshUser?: string          // SSH user (defaults to 'dokku')
  status: 'connected' | 'disconnected' | 'error'
  dokkuVersion: string
  dockerVersion: string
  os: string
  uptime: string
  diskUsage: { used: number; total: number }
  memoryUsage: { used: number; total: number }
  projectIds: string[]
  defaultProxy: string
  proxyMode: 'managed' | 'external'
  externalProxyNetwork?: string
  externalProxyHttpEntrypoint: string
  externalProxyHttpsEntrypoint: string
  externalProxyCertResolver?: string
  externalProxyRedirectMiddleware?: string
  externalProxyDefaultLabels: Record<string, string>
  baseDomain?: string
  autoDomains?: boolean
  publicIp?: string
}

export interface DockerContainer {
  id: string
  name: string
  image: string
  status: string
  running: boolean
  created: string
  command?: string
  ports: Array<{ containerPort: string; hostPort?: string; hostIp?: string }>
  env: Record<string, string>
  mounts: Array<{ source: string; destination: string; type: string; mode?: string }>
  labels: Record<string, string>
  serviceType: 'app' | 'database'
  subtype?: string
}

// ───────────────────────────────────────────────
// Git Sources
// ───────────────────────────────────────────────

export interface GitSource {
  id: string
  provider: 'github' | 'gitlab' | 'bitbucket' | 'gitea'
  connected: boolean
  username?: string
  repos: GitRepo[]
  authMethod?: 'oauth_app' | 'oauth2' | 'ssh_deploy_key' | 'token'
  accountType?: 'personal' | 'organization'
  installationId?: string
  organizationId?: string
}

export interface GitRepo {
  id: string
  fullName: string
  defaultBranch: string
  private: boolean
  cloneUrl?: string
  sshUrl?: string
  htmlUrl?: string
  serviceName?: string  // which service this deploys to
}

export interface RepositoryImportService {
  name: string
  category: string
  subtype: string
  builder?: string
  rootDirectory?: string
  scripts?: { build?: string; predeploy?: string; postdeploy?: string }
  checks?: { enabled?: boolean; path?: string }
}

export interface RepositoryImportPreview {
  repository: string
  branch: string
  commitSha: string
  services: RepositoryImportService[]
  links: { from: string; to: string }[]
  warnings: string[]
  conflicts: string[]
  evidence: { path: string; format: string; decision: string; confidence: string }[]
  snapshotToken: string
}

export interface GitHubAppConfig {
  enabled: boolean
  appSlug?: string
  clientId?: string
}

export interface SystemSetting {
  key: string
  value?: string
}

export interface AppUpdateInfo {
  currentVersion: string
  checkedAt: string | null
  updateAvailable: boolean
  latestVersion: string | null
  releaseUrl: string | null
  publishedAt: string | null
  prerelease: boolean
  canApply: boolean
  applyStrategy: 'install_sh' | 'docker_compose' | 'ssh_to_local' | 'manual'
  autoUpdateEnabled: boolean
}

// ───────────────────────────────────────────────
// Deployment — covers deploys, restarts, and env syncs
// ───────────────────────────────────────────────

export interface Deployment {
  id: string
  status: 'pending' | 'building' | 'deploying' | 'succeeded' | 'failed' | 'cancelled'
  kind?: 'deploy' | 'restart' | 'rebuild' | 'env_sync'
  branch?: string | null
  commitSha?: string | null
  commitMessage?: string | null
  triggeredBy?: 'manual' | 'webhook' | string
  startedAt?: string | null
  completedAt?: string | null
  createdAt: string
  deployLog?: string | null
  buildLog?: string | null
  eventSequence?: number
}

export interface DeploymentDetail extends Deployment {
  deployLog: string
  buildLog: string
}

// ───────────────────────────────────────────────
// Organization
// ───────────────────────────────────────────────

export interface Organization {
  id: string
  name: string
  slug: string
  avatarUrl?: string
  ownerId: string
  memberCount?: number
  createdAt?: string
  role?: 'owner' | 'admin' | 'member'
}

export interface OrganizationMembership {
  id: string
  userId: string
  role: 'owner' | 'admin' | 'member'
  user: { id: number; name: string; email: string }
  createdAt: string
  isYou: boolean
}

export interface OrganizationInvitation {
  id: string
  email: string
  role: 'owner' | 'admin' | 'member'
  token: string
  expiresAt: string
  acceptedAt: string | null
  createdAt: string
  invitedBy?: { id: number; name: string; email: string }
}

export interface InvitationDetails {
  email: string
  role: 'admin' | 'member'
  organization: { id: string; name: string; slug: string }
  invitedBy: { name: string; email: string }
  expiresAt: string
  existingUser: boolean
}

// ───────────────────────────────────────────────
// Activity / Events
// ───────────────────────────────────────────────

export interface ActivityEvent {
  id: string
  projectId: string
  serviceName: string
  action: 'deployed' | 'stopped' | 'started' | 'restarted' | 'scaled' | 'linked' | 'unlinked' | 'created' | 'destroyed' | 'rebuilt' | 'warning'
  message: string
  timestamp: string
}
