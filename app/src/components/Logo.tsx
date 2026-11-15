interface LogoProps {
  className?: string
  size?: number | string
  wordmark?: boolean
}

export default function Logo({ className = 'h-8 w-8', size, wordmark = false }: LogoProps) {
  return <img src={wordmark ? '/brand/raildock-logo-on-dark.png' : '/brand/raildock-mark.png'} alt="RailDock" className={`object-contain ${className}`} style={size ? { width: size, height: size } : undefined} draggable={false} />
}
