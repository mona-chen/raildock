import { useId } from 'react'

interface LogoProps {
  className?: string
  size?: number | string
}

export default function Logo({ className = 'h-8 w-8', size }: LogoProps) {
  const gradientId = useId().replace(/:/g, '')
  const fillId = `raildock-gradient-${gradientId}`

  return (
    <svg
      viewBox="0 0 40 40"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className={className}
      style={size ? { width: size, height: size } : undefined}
      aria-label="RailDock"
    >
      <defs>
        <linearGradient id={fillId} x1="0" y1="0" x2="40" y2="40" gradientUnits="userSpaceOnUse">
          <stop stopColor="#A78BFA" />
          <stop offset="1" stopColor="#7C3AED" />
        </linearGradient>
      </defs>

      {/* Rail tracks */}
      <rect x="4" y="28" width="32" height="3" rx="1.5" fill={`url(#${fillId})`} opacity="0.45" />
      <rect x="4" y="22" width="32" height="3" rx="1.5" fill={`url(#${fillId})`} opacity="0.7" />

      {/* Wheels */}
      <circle cx="10" cy="32.5" r="2.5" fill={`url(#${fillId})`} />
      <circle cx="30" cy="32.5" r="2.5" fill={`url(#${fillId})`} />

      {/* Shipping container body */}
      <rect x="6" y="8" width="28" height="16" rx="3" fill={`url(#${fillId})`} opacity="0.12" />
      <rect x="6" y="8" width="28" height="16" rx="3" stroke={`url(#${fillId})`} strokeWidth="2" />

      {/* Container corrugation */}
      <line x1="14" y1="8" x2="14" y2="24" stroke={`url(#${fillId})`} strokeWidth="1.5" opacity="0.5" />
      <line x1="20" y1="8" x2="20" y2="24" stroke={`url(#${fillId})`} strokeWidth="1.5" opacity="0.5" />
      <line x1="26" y1="8" x2="26" y2="24" stroke={`url(#${fillId})`} strokeWidth="1.5" opacity="0.5" />
    </svg>
  )
}
