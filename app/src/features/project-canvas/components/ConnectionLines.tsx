import { memo, useState } from 'react'

interface Connection {
  from: { x: number; y: number }
  to: { x: number; y: number }
  fromId: string
  toId: string
}

interface ConnectionLinesProps {
  connections: Connection[]
}

function ConnectionLines({ connections }: ConnectionLinesProps) {
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
        const mx = conn.from.x + 110 + (conn.to.x - conn.from.x) / 2
        const pathD = `M ${conn.from.x + 110} ${conn.from.y + 30} L ${mx} ${conn.from.y + 30} L ${mx} ${conn.to.y + 30} L ${conn.to.x + 110} ${conn.to.y + 30}`

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
              stroke={isHovered ? 'rgba(139,92,246,0.6)' : 'rgba(255,255,255,0.22)'}
              strokeWidth={isHovered ? 2 : 1.5}
              strokeDasharray="6 4"
              style={{ transition: 'stroke 0.2s, stroke-width 0.2s' }}
            />
            <circle
              cx={conn.to.x + 110}
              cy={conn.to.y + 30}
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
