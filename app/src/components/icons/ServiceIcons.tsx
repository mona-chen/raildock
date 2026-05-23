/**
 * Service Icons — Real brand logos via @icons-pack/react-simple-icons
 *
 * NOTE: This file imports 40+ simple-icons components statically. If bundle
 * size becomes a concern (~80KB added to the ProjectCanvas chunk), switch to:
 *   1. Individual SVG imports from simple-icons (tree-shake friendly)
 *   2. Dynamic import() per subtype
 *   3. A lightweight custom SVG sprite sheet for just the brands we use
 */
import type { FC } from 'react'
import {
  SiPostgresql,
  SiMysql,
  SiMongodb,
  SiRedis,
  SiRabbitmq,
  SiElasticsearch,
  SiMinio,
  SiDocker,
  SiGit,
  SiWordpress,
  SiNginx,
  SiTraefikproxy,
  SiSupabase,
  SiMariadb,
  SiApachekafka,
  SiCockroachlabs,
  SiTimescale,
  SiClickhouse,
  SiNeo4j,
  SiApachecassandra,
  SiCouchbase,
  SiInfluxdb,
  SiSqlite,
  SiStrapi,
  SiNextdotjs,
  SiNodedotjs,
  SiPython,
  SiGo,
  SiRuby,
  SiPhp,
  SiRust,
  SiReact,
  SiVuedotjs,
  SiAngular,
  SiSvelte,
  SiDjango,
  SiFlask,
  SiLaravel,
  SiRubyonrails,
  SiSpring,
  SiExpress,
  SiFastify,
  SiNestjs,
  SiRemix,
  SiAstro,
  SiGatsby,
  SiVite,
  SiWebpack,
  SiBun,
  SiDeno,
} from '@icons-pack/react-simple-icons'
import {
  Globe,
  Box,
  Database,
  Zap,
  MessageSquare,
  Search,
  HardDrive,
  Clock,
  Container,
  Code2,
  Rocket,
  Cog,
  Server,
  Layers,
  Cpu,
} from 'lucide-react'

export const SERVICE_COLORS: Record<string, string> = {
  // Databases
  postgres: '#336791',
  mysql: '#4479A1',
  mariadb: '#003545',
  mongo: '#47A248',
  mongodb: '#47A248',
  redis: '#DC382D',
  rabbitmq: '#FF6600',
  elasticsearch: '#005571',
  minio: '#C72C48',
  supabase: '#3ECF8E',
  cockroachdb: '#6933FF',
  timescaledb: '#FDB515',
  clickhouse: '#FFCC01',
  neo4j: '#008CC1',
  cassandra: '#1287B1',
  couchbase: '#EA2328',
  influxdb: '#22ADF6',
  sqlite: '#003B57',
  memcached: '#2683C9',
  kafka: '#231F20',
  // Apps / Frameworks
  web: '#22c55e',
  worker: '#3b82f6',
  nextjs: '#000000',
  nodejs: '#339933',
  node: '#339933',
  python: '#3776AB',
  go: '#00ADD8',
  golang: '#00ADD8',
  ruby: '#CC342D',
  php: '#777BB4',
  rust: '#000000',
  react: '#61DAFB',
  vue: '#4FC08D',
  angular: '#DD0031',
  svelte: '#FF3E00',
  django: '#092E20',
  flask: '#000000',
  laravel: '#FF2D20',
  rails: '#CC0000',
  spring: '#6DB33F',
  express: '#000000',
  fastify: '#000000',
  nestjs: '#E0234E',
  remix: '#000000',
  astro: '#BC52EE',
  gatsby: '#663399',
  strapi: '#4945FF',
  wordpress: '#21759B',
  // Infrastructure
  docker: '#2496ED',
  git: '#F05032',
  nginx: '#009639',
  traefik: '#00A3E0',
  vite: '#646CFF',
  webpack: '#8DD6F9',
  bun: '#000000',
  deno: '#000000',
  // Generic
  clock: '#a855f7',
  service: '#6b7280',
  database: '#3b82f6',
  cache: '#f59e0b',
  queue: '#f97316',
  search: '#3b82f6',
}

const SIMPLE_ICON_MAP: Record<string, FC<{ size?: number; color?: string; className?: string }>> = {
  postgres: SiPostgresql,
  mysql: SiMysql,
  mariadb: SiMariadb,
  mongo: SiMongodb,
  mongodb: SiMongodb,
  redis: SiRedis,
  rabbitmq: SiRabbitmq,
  elasticsearch: SiElasticsearch,
  minio: SiMinio,
  supabase: SiSupabase,
  cockroachdb: SiCockroachlabs,
  timescaledb: SiTimescale,
  clickhouse: SiClickhouse,
  neo4j: SiNeo4j,
  cassandra: SiApachecassandra,
  couchbase: SiCouchbase,
  influxdb: SiInfluxdb,
  sqlite: SiSqlite,

  kafka: SiApachekafka,
  nextjs: SiNextdotjs,
  nodejs: SiNodedotjs,
  node: SiNodedotjs,
  python: SiPython,
  go: SiGo,
  golang: SiGo,
  ruby: SiRuby,
  php: SiPhp,
  rust: SiRust,
  react: SiReact,
  vue: SiVuedotjs,
  angular: SiAngular,
  svelte: SiSvelte,
  django: SiDjango,
  flask: SiFlask,
  laravel: SiLaravel,
  rails: SiRubyonrails,
  spring: SiSpring,
  express: SiExpress,
  fastify: SiFastify,
  nestjs: SiNestjs,
  remix: SiRemix,
  astro: SiAstro,
  gatsby: SiGatsby,
  strapi: SiStrapi,
  wordpress: SiWordpress,
  docker: SiDocker,
  git: SiGit,
  nginx: SiNginx,
  traefik: SiTraefikproxy,
  vite: SiVite,
  webpack: SiWebpack,
  bun: SiBun,
  deno: SiDeno,
}

const LUCIDE_ICON_MAP: Record<string, React.ElementType> = {
  web: Globe,
  worker: Box,
  clock: Clock,
  database: Database,
  cache: Zap,
  queue: MessageSquare,
  search: Search,
  service: Cog,
  app: Rocket,
  server: Server,
  container: Container,
  gitrepo: Code2,
  volume: HardDrive,
  layer: Layers,
  cpu: Cpu,
}

/**
 * Detect the actual service type from a Docker image string.
 * Examples:
 *   "wordpress:php8.4-apache" → "wordpress"
 *   "mysql:8.0" → "mysql"
 *   "postgres:16-alpine" → "postgres"
 *   "minio/minio:latest" → "minio"
 *   "nginx:alpine" → "nginx"
 *   "traefik:v3.0" → "traefik"
 */
export function detectSubtypeFromDockerImage(image: string | null | undefined): string | null {
  if (!image) return null
  const name = image.split('/').pop()?.split(':')[0]?.toLowerCase() || ''

  const detectors: [string, string][] = [
    ['wordpress', 'wordpress'],
    ['mysql', 'mysql'],
    ['mariadb', 'mariadb'],
    ['postgres', 'postgres'],
    ['mongodb', 'mongo'],
    ['mongo', 'mongo'],
    ['redis', 'redis'],
    ['rabbitmq', 'rabbitmq'],
    ['elasticsearch', 'elasticsearch'],
    ['minio', 'minio'],
    ['nginx', 'nginx'],
    ['traefik', 'traefik'],
    ['docker', 'docker'],
    ['supabase', 'supabase'],
    ['cockroachdb', 'cockroachdb'],
    ['neo4j', 'neo4j'],
    ['cassandra', 'cassandra'],
    ['couchbase', 'couchbase'],
    ['influxdb', 'influxdb'],
    ['clickhouse', 'clickhouse'],
    ['timescaledb', 'timescaledb'],
    ['sqlite', 'sqlite'],
    ['memcached', 'memcached'],
    ['kafka', 'kafka'],
    ['strapi', 'strapi'],
    ['nextjs', 'nextjs'],
    ['nodejs', 'nodejs'],
    ['node', 'nodejs'],
    ['python', 'python'],
    ['golang', 'go'],
    ['ruby', 'ruby'],
    ['php', 'php'],
    ['rust', 'rust'],
    ['django', 'django'],
    ['flask', 'flask'],
    ['laravel', 'laravel'],
    ['rails', 'rails'],
    ['spring', 'spring'],
    ['express', 'express'],
    ['nestjs', 'nestjs'],
    ['react', 'react'],
    ['vue', 'vue'],
    ['angular', 'angular'],
    ['svelte', 'svelte'],
    ['remix', 'remix'],
    ['astro', 'astro'],
    ['gatsby', 'gatsby'],
    ['vite', 'vite'],
    ['webpack', 'webpack'],
    ['bun', 'bun'],
    ['deno', 'deno'],
  ]

  for (const [pattern, subtype] of detectors) {
    if (name.includes(pattern)) return subtype
  }
  return null
}

interface ServiceIconProps {
  subtype: string
  dockerImage?: string | null
  size?: number
  className?: string
  fallback?: React.ElementType
}

const GENERIC_SUBTYPES = new Set(['docker', 'app', 'service', 'web', 'worker', 'container', 'image'])

function resolveSubtype(subtype: string, dockerImage?: string | null): string {
  const key = subtype.toLowerCase()
  // If subtype is generic AND we have a docker image, try to detect the actual service
  if (GENERIC_SUBTYPES.has(key) && dockerImage) {
    const detected = detectSubtypeFromDockerImage(dockerImage)
    if (detected) return detected
  }
  return key
}

export function ServiceIcon({ subtype, dockerImage, size = 18, className = '', fallback = Box }: ServiceIconProps) {
  const key = resolveSubtype(subtype, dockerImage)
  const SimpleIcon = SIMPLE_ICON_MAP[key]

  if (SimpleIcon) {
    const color = SERVICE_COLORS[key] || '#A0A0B0'
    return <SimpleIcon size={size} color={color} className={className} />
  }

  const LucideIcon = LUCIDE_ICON_MAP[key] || fallback
  const color = SERVICE_COLORS[key] || '#A0A0B0'
  return <LucideIcon size={size} style={{ color }} className={className} />
}

export function getServiceColor(subtype: string, dockerImage?: string | null): string {
  const key = resolveSubtype(subtype, dockerImage)
  return SERVICE_COLORS[key] || '#A0A0B0'
}

export function getServiceIconComponent(subtype: string, dockerImage?: string | null): React.ElementType {
  const key = resolveSubtype(subtype, dockerImage)
  return SIMPLE_ICON_MAP[key] || LUCIDE_ICON_MAP[key] || Box
}
