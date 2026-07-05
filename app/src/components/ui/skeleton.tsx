import { cn } from "@/lib/utils"

function Skeleton({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="skeleton"
      className={cn(
        "relative overflow-hidden rounded-md bg-white/[0.04]",
        "before:absolute before:inset-0",
        "before:bg-[linear-gradient(90deg,transparent_0%,rgba(255,255,255,0.06)_50%,transparent_100%)] before:bg-[length:200%_100%]",
        "before:animate-shimmer",
        className
      )}
      {...props}
    />
  )
}

function SkeletonText({ className, lines = 1, ...props }: React.ComponentProps<"div"> & { lines?: number }) {
  return (
    <div data-slot="skeleton-text" className={cn("space-y-2", className)} {...props}>
      {Array.from({ length: lines }).map((_, i) => (
        <Skeleton key={i} className="h-3 w-full last:w-4/5" />
      ))}
    </div>
  )
}

function SkeletonCard({ className, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="skeleton-card"
      className={cn(
        "rounded-xl border border-white/[0.05] bg-white/[0.02] p-4",
        className
      )}
      {...props}
    >
      <div className="flex items-start gap-3">
        <Skeleton className="size-10 shrink-0 rounded-lg" />
        <div className="flex-1 space-y-2">
          <Skeleton className="h-3.5 w-1/3" />
          <Skeleton className="h-3 w-2/3" />
        </div>
      </div>
    </div>
  )
}

function SkeletonPage({ className, children, ...props }: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="skeleton-page"
      className={cn("h-full flex flex-col overflow-hidden", className)}
      {...props}
    >
      <div className="h-14 border-b border-white/[0.06] px-6 flex items-center gap-3">
        <Skeleton className="size-5 rounded" />
        <Skeleton className="h-4 w-32" />
      </div>
      <div className="flex-1 p-6">
        <div className="mx-auto max-w-5xl space-y-4">
          {children || (
            <>
              <Skeleton className="h-40 w-full rounded-xl" />
              <Skeleton className="h-40 w-full rounded-xl" />
              <Skeleton className="h-40 w-full rounded-xl" />
            </>
          )}
        </div>
      </div>
    </div>
  )
}

export { Skeleton, SkeletonText, SkeletonCard, SkeletonPage }
