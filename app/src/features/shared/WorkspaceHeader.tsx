import type { ReactNode } from 'react'

/** Consistent page hierarchy outside the architecture canvas. */
export default function WorkspaceHeader({ title, description, children }: { title: string; description: string; children?: ReactNode }) {
  return <header className="flex shrink-0 flex-wrap items-center justify-between gap-4 border-b border-white/8 bg-[#101014] px-5 py-6 sm:px-8">
    <div><h1 className="text-xl font-semibold text-white">{title}</h1><p className="mt-1 text-xs leading-relaxed text-[#a0a0b0]">{description}</p></div>
    {children}
  </header>
}
