import { Plus, Minus, LayoutGrid, Undo2, Redo2, Layers, Maximize2 } from 'lucide-react'

interface CanvasControlsProps {
  onZoomIn: () => void
  onZoomOut: () => void
  onLayout: () => void
  onFit?: () => void
  canUndo?: boolean
  canRedo?: boolean
}

export default function CanvasControls({
  onZoomIn,
  onZoomOut,
  onLayout,
  onFit,
  canUndo = false,
  canRedo = false,
}: CanvasControlsProps) {
  return (
    <div className="absolute bottom-4 left-4 flex flex-col gap-1.5 z-30" onMouseDown={(e) => e.stopPropagation()}>
      <button
        onClick={onLayout}
        className="w-8 h-8 rounded-lg bg-[#1a1a1e] border border-white/[0.08] flex items-center justify-center text-white/40 hover:text-white/70 hover:border-white/[0.15] transition-all motion-reduce:transition-none"
        title="Auto layout"
        aria-label="Auto layout services"
      >
        <LayoutGrid size={14} />
      </button>

      <div className="flex flex-col gap-0.5">
        <button
          onClick={onZoomIn}
          className="w-8 h-8 rounded-lg bg-[#1a1a1e] border border-white/[0.08] flex items-center justify-center text-white/40 hover:text-white/70 hover:border-white/[0.15] transition-all motion-reduce:transition-none"
          title="Zoom in"
          aria-label="Zoom in"
        >
          <Plus size={14} />
        </button>
        <button
          onClick={onZoomOut}
          className="w-8 h-8 rounded-lg bg-[#1a1a1e] border border-white/[0.08] flex items-center justify-center text-white/40 hover:text-white/70 hover:border-white/[0.15] transition-all motion-reduce:transition-none"
          title="Zoom out"
          aria-label="Zoom out"
        >
          <Minus size={14} />
        </button>
        <button
          onClick={onFit}
          className="w-8 h-8 rounded-lg bg-[#1a1a1e] border border-white/[0.08] flex items-center justify-center text-white/40 hover:text-white/70 hover:border-white/[0.15] transition-all motion-reduce:transition-none"
          title="Fit to view"
          aria-label="Fit canvas to view"
        >
          <Maximize2 size={14} />
        </button>
      </div>

      <div className="flex flex-col gap-0.5">
        <button
          disabled={!canUndo}
          className="w-8 h-8 rounded-lg bg-[#1a1a1e] border border-white/[0.08] flex items-center justify-center text-white/40 hover:text-white/70 hover:border-white/[0.15] transition-all motion-reduce:transition-none disabled:opacity-30"
          title="Undo"
          aria-label="Undo last action"
        >
          <Undo2 size={14} />
        </button>
        <button
          disabled={!canRedo}
          className="w-8 h-8 rounded-lg bg-[#1a1a1e] border border-white/[0.08] flex items-center justify-center text-white/40 hover:text-white/70 hover:border-white/[0.15] transition-all motion-reduce:transition-none disabled:opacity-30"
          title="Redo"
          aria-label="Redo last action"
        >
          <Redo2 size={14} />
        </button>
      </div>

      <button
        className="w-8 h-8 rounded-lg bg-[#1a1a1e] border border-white/[0.08] flex items-center justify-center text-white/40 hover:text-white/70 hover:border-white/[0.15] transition-all motion-reduce:transition-none"
        title="Layers"
        aria-label="Toggle layers"
      >
        <Layers size={14} />
      </button>
    </div>
  )
}
