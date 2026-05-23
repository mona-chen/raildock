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
  restartPolicy: 'on-failure' | 'always' | 'unless-stopped'
  restartMaxRetries: number
  locked: boolean
  autoDeploy: boolean
  rootDirectory?: string
  startCommand?: string
  maintenanceMode: boolean
  managedBy?: 'ui' | 'manifest' | 'hybrid'
  configOverrides?: Record<string, any>
  config?: Record<string, any>
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
  hostname: string
  port: number
  ssl: boolean
  letsencrypt: boolean
  temporary?: boolean
}

export interface StorageMount {
  hostPath: string
  containerPath: string
}

export interface LogEntry {
  timestamp: string
  processType: string
  message: string
}

export interface Backup {
  id: string
  createdAt: string
  size: string
  status: 'success' | 'failed' | 'pending'
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
  wait: number
  timeout: number
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
  baseDomain?: string
  autoDomains?: boolean
  publicIp?: string
}

// ───────────────────────────────────────────────
// Git Sources
// ───────────────────────────────────────────────

export interface GitSource {
  id: string
  provider: 'github' | 'gitlab' | 'bitbucket'
  connected: boolean
  username?: string
  repos: GitRepo[]
}

export interface GitRepo {
  id: string
  fullName: string
  defaultBranch: string
  private: boolean
  serviceName?: string  // which service this deploys to
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
}

// ───────────────────────────────────────────────
// Activity / Events
// ───────────────────────────────────────────────

export interface ActivityEvent {
  id: string
  projectId: string
  serviceName: string
  action: 'deployed' | 'stopped' | 'started' | 'scaled' | 'linked' | 'unlinked' | 'created' | 'destroyed'
  message: string
  timestamp: string
}
