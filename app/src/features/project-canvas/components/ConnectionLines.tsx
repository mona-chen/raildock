import { memo, useState } from 'react'

interface Connection {
  from: { x: number; y: number }
  to: { x: number; y: number }
  fromId: string
  toId: string
}

interface ConnectionLinesProps {
  connections: Connection[]
  activeServiceId?: string | null
}

function ConnectionLines({ connections, activeServiceId }: ConnectionLinesProps) {
  const [hovered, setHovered] = useState<string | null>(null)

  if (connections.length === 0) return null

  return (
    <svg
      className="absolute inset-0"
      style={{ width: '100%', height: '100%', pointerEvents: 'none' }}
    >
      {connections.map((conn) => {
        const key = `${conn.fromId}-${conn.toId}`
        const isHovered = hovered === key
        const related = !activeServiceId || conn.fromId === activeServiceId || conn.toId === activeServiceId
        const rightward = conn.to.x >= conn.from.x
        const startX = conn.from.x + (rightward ? 240 : 0)
        const endX = conn.to.x + (rightward ? 0 : 240)
        const startY = conn.from.y + 52
        const endY = conn.to.y + 52
        const bend = Math.max(60, Math.abs(endX - startX) * 0.5) * (rightward ? 1 : -1)
        const pathD = `M ${startX} ${startY} C ${startX + bend} ${startY}, ${endX - bend} ${endY}, ${endX} ${endY}`

        return (
          <g
            key={key}
            style={{ pointerEvents: 'auto' }}
            onMouseEnter={() => setHovered(key)}
            onMouseLeave={() => setHovered(null)}
          >
            {/* Invisible wider path for easier hover */}
            <path
              d={pathD}
              fill="none"
              stroke="transparent"
              strokeWidth={12}
              style={{ cursor: 'pointer' }}
            />
            <path
              d={pathD}
              fill="none"
              stroke={isHovered || (activeServiceId && related) ? '#a78bfa' : related ? 'rgba(167,139,250,0.35)' : 'rgba(255,255,255,0.08)'}
              strokeWidth={isHovered ? 2 : 1.5}
              strokeDasharray={related ? undefined : '4 5'}
              style={{ transition: 'stroke 0.2s, stroke-width 0.2s' }}
            />
            <circle
              cx={endX}
              cy={endY}
              r={isHovered ? 5 : 3.5}
              fill={isHovered ? 'rgba(139,92,246,0.7)' : 'rgba(255,255,255,0.25)'}
              style={{ transition: 'all 0.2s' }}
            />
          </g>
        )
      })}
    </svg>
  )
}

export default memo(ConnectionLines)
