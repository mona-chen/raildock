import { forwardRef, useId } from 'react'

interface AccessibleToggleProps {
  checked: boolean
  onChange: (checked: boolean) => void
  label?: string
  id?: string
  disabled?: boolean
}

/**
 * Accessible toggle switch using a real checkbox input.
 * Keyboard accessible, screen-reader friendly, respects prefers-reduced-motion.
 */
const AccessibleToggle = forwardRef<HTMLInputElement, AccessibleToggleProps>(
  ({ checked, onChange, label, id, disabled }, ref) => {
    const generatedId = useId()
    const toggleId = id || generatedId

    return (
      <label
        htmlFor={toggleId}
        className="inline-flex items-center gap-2 cursor-pointer"
        aria-label={label}
      >
        <span className="sr-only">{label || 'Toggle'}</span>
        <input
          ref={ref}
          id={toggleId}
          type="checkbox"
          checked={checked}
          onChange={(e) => onChange(e.target.checked)}
          disabled={disabled}
          className="sr-only peer"
        />
        <div
          className={`
            relative w-10 h-5 rounded-full transition-colors
            peer-focus-visible:ring-2 peer-focus-visible:ring-[#8b5cf6]/50 peer-focus-visible:ring-offset-2 peer-focus-visible:ring-offset-[#131318]
            ${checked ? 'bg-[#8b5cf6]' : 'bg-white/10'}
            ${disabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}
            motion-reduce:transition-none
          `}
        >
          <div
            className={`
              absolute top-0.5 left-0.5 w-4 h-4 rounded-full bg-white
              transition-transform motion-reduce:transition-none
              ${checked ? 'translate-x-5' : 'translate-x-0'}
            `}
          />
        </div>
      </label>
    )
  }
)

AccessibleToggle.displayName = 'AccessibleToggle'

export default AccessibleToggle
