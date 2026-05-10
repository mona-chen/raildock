import { memo } from 'react'

interface Connection {
  from: { x: number; y: number }
  to: { x: number; y: number }
}

interface ConnectionLinesProps {
  connections: Connection[]
}

function ConnectionLines({ connections }: ConnectionLinesProps) {
  if (connections.length === 0) return null

  return (
    <svg
      className="absolute inset-0 pointer-events-none"
      style={{ width: '100%', height: '100%' }}
    >
      {connections.map((conn, i) => {
        const mx = conn.from.x + 110 + (conn.to.x - conn.from.x) / 2
        return (
          <g key={i}>
            <path
              d={`M ${conn.from.x + 110} ${conn.from.y + 30} L ${mx} ${conn.from.y + 30} L ${mx} ${conn.to.y + 30} L ${conn.to.x + 110} ${conn.to.y + 30}`}
              fill="none"
              stroke="rgba(255,255,255,0.07)"
              strokeWidth={1.5}
              strokeDasharray="6 4"
            />
            <circle
              cx={conn.to.x + 110}
              cy={conn.to.y + 30}
              r={3}
              fill="rgba(255,255,255,0.1)"
            />
          </g>
        )
      })}
    </svg>
  )
}

export default memo(ConnectionLines)
