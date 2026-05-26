/**
 * Optimized canvas grid background.
 * Uses CSS radial-gradient instead of thousands of SVG circles.
 * Zero React re-renders on zoom/pan changes.
 */

interface CanvasGridProps {
  zoom: number
  pan: { x: number; y: number }
}

export default function CanvasGrid({ zoom, pan }: CanvasGridProps) {
  return (
    <div
      className="absolute inset-0 pointer-events-none"
      style={{
        backgroundImage: 'radial-gradient(circle, rgba(255,255,255,0.14) 1.5px, transparent 1.5px)',
        backgroundSize: `${20 * zoom}px ${20 * zoom}px`,
        backgroundPosition: `${pan.x % (20 * zoom)}px ${pan.y % (20 * zoom)}px`,
        zIndex: 0,
      }}
    />
  )
}
