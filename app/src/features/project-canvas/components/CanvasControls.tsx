import { Plus, Minus, LayoutGrid, Maximize2, CircleHelp } from 'lucide-react'

interface CanvasControlsProps {
  onZoomIn: () => void
  onZoomOut: () => void
  onLayout: () => void
  onFit?: () => void
  zoom?: number
  onHelp?: () => void
}

export default function CanvasControls({ onZoomIn, onZoomOut, onLayout, onFit, zoom = 1, onHelp }: CanvasControlsProps) {
  const control = 'flex h-9 w-9 shrink-0 items-center justify-center rounded-lg text-[#a0a0b0] hover:bg-white/[0.07] hover:text-white disabled:opacity-30 transition-colors'
  return (
    <div className="absolute bottom-5 left-5 z-30 flex max-w-[calc(100%-2.5rem)] items-center gap-1 rounded-xl border border-white/[0.1] bg-[#18181e]/95 p-1 shadow-xl backdrop-blur-md" onMouseDown={(event) => event.stopPropagation()}>
      <button type="button" onClick={onZoomOut} disabled={zoom <= 0.3} className={control} title="Zoom out" aria-label="Zoom out"><Minus size={16} /></button>
      <span className="w-10 text-center font-mono text-[11px] text-[#b7b7c5]" aria-live="polite">{Math.round(zoom * 100)}%</span>
      <button type="button" onClick={onZoomIn} disabled={zoom >= 2} className={control} title="Zoom in" aria-label="Zoom in"><Plus size={16} /></button>
      <span className="mx-1 h-4 w-px bg-white/10" />
      <button type="button" onClick={onFit} className={control} title="Fit to view" aria-label="Fit canvas to view"><Maximize2 size={16} /></button>
      <button type="button" onClick={onLayout} className={control} title="Arrange services" aria-label="Auto layout services"><LayoutGrid size={16} /></button>
      {onHelp && <><span className="mx-1 h-4 w-px bg-white/10" /><button type="button" onClick={onHelp} className={control} title="Keyboard shortcuts (?)" aria-label="Keyboard shortcuts"><CircleHelp size={16} /></button></>}
    </div>
  )
}
