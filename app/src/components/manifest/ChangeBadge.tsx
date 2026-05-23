interface ChangeBadgeProps {
  severity: 'reload' | 'restart' | 'redeploy'
  size?: 'sm' | 'md'
}

const STYLES = {
  reload: {
    bg: 'bg-emerald-500/15',
    text: 'text-emerald-400',
    label: 'Reload',
  },
  restart: {
    bg: 'bg-amber-500/15',
    text: 'text-amber-400',
    label: 'Restart',
  },
  redeploy: {
    bg: 'bg-rose-500/15',
    text: 'text-rose-400',
    label: 'Redeploy',
  },
}

export default function ChangeBadge({ severity, size = 'sm' }: ChangeBadgeProps) {
  const style = STYLES[severity] || STYLES.redeploy
  const sizeClasses = size === 'sm'
    ? 'text-[10px] px-1.5 py-0.5 rounded'
    : 'text-[11px] px-2 py-1 rounded-md'

  return (
    <span className={`${style.bg} ${style.text} ${sizeClasses} font-medium inline-block`}>
      {style.label}
    </span>
  )
}
