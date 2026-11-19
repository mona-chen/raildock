import { forwardRef, type ComponentProps } from 'react'
import { cn } from '@/lib/utils'

/** Lucide action icons use 16px glyphs and a minimum 32px target. */
export const IconButton = forwardRef<HTMLButtonElement, ComponentProps<'button'> & { title: string }>(
  function IconButton({ title, className, type = 'button', ...props }, ref) {
    return <button ref={ref} type={type} title={title} aria-label={props['aria-label'] ?? title} className={cn('inline-flex min-h-8 min-w-8 shrink-0 items-center justify-center rounded-md text-[#a0a0b0] transition-colors hover:bg-white/6 hover:text-white disabled:opacity-40 [&_svg]:size-4 [&_svg]:shrink-0 [&_svg]:stroke-2', className)} {...props} />
  }
)
