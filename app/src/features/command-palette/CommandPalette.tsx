import { useCallback, useEffect, useMemo, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { Activity, Folder, Hammer, Plus, RefreshCw, Rocket, Server, Settings } from 'lucide-react'
import {
  CommandDialog,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
  CommandSeparator,
  CommandShortcut,
} from '@/components/ui/command'
import { useDeployService, useRebuildService, useRestartService } from '@/hooks/useServices'

const NAV_ITEMS = [
  { label: 'Projects', path: '/dashboard/projects', icon: Folder },
  { label: 'Servers', path: '/dashboard/servers', icon: Server },
  { label: 'Activity', path: '/dashboard/activity', icon: Activity },
  { label: 'Settings', path: '/dashboard/settings', icon: Settings },
]

export default function CommandPalette() {
  const [open, setOpen] = useState(false)
  const navigate = useNavigate()
  const location = useLocation()
  const deployService = useDeployService()
  const restartService = useRestartService()
  const rebuildService = useRebuildService()

  // The selected service only exists while a project canvas is open, so read it
  // from the URL instead of the canvas store, which can outlive the page.
  const selectedServiceId = useMemo(() => {
    if (!location.pathname.includes('/dashboard/project/')) return null
    return new URLSearchParams(location.search).get('service')
  }, [location])

  const projectBasePath = useMemo(() => {
    const match = location.pathname.match(/^(\/dashboard\/project\/[^/]+)/)
    return match ? match[1] : null
  }, [location.pathname])

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault()
        setOpen((value) => !value)
      }
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [])

  const run = useCallback((action: () => void) => {
    setOpen(false)
    // Let the dialog finish closing so focus returns to the page, not the list.
    requestAnimationFrame(action)
  }, [])

  const go = (path: string) => run(() => navigate(path))

  return (
    <CommandDialog
      open={open}
      onOpenChange={setOpen}
      title="Command palette"
      description="Jump to a page or act on the selected service"
    >
      <CommandInput placeholder="Type a command or search…" />
      <CommandList>
        <CommandEmpty>No matching commands.</CommandEmpty>
        <CommandGroup heading="Go to">
          {NAV_ITEMS.map((item) => (
            <CommandItem key={item.path} value={`go ${item.label}`} onSelect={() => go(item.path)}>
              <item.icon />
              {item.label}
            </CommandItem>
          ))}
        </CommandGroup>
        <CommandSeparator />
        <CommandGroup heading="Create">
          <CommandItem value="create project" onSelect={() => go('/dashboard/projects?new=1')}>
            <Plus />
            New project
          </CommandItem>
          <CommandItem
            value="create service"
            disabled={!projectBasePath}
            onSelect={() => projectBasePath && go(`${projectBasePath}/services?new=1`)}
          >
            <Plus />
            New service
            <CommandShortcut>in project</CommandShortcut>
          </CommandItem>
        </CommandGroup>
        {selectedServiceId && (
          <>
            <CommandSeparator />
            <CommandGroup heading="Selected service">
              <CommandItem value="deploy service" onSelect={() => run(() => deployService.mutate(selectedServiceId))}>
                <Rocket />
                Deploy latest
              </CommandItem>
              <CommandItem value="restart service" onSelect={() => run(() => restartService.mutate(selectedServiceId))}>
                <RefreshCw />
                Restart
              </CommandItem>
              <CommandItem value="rebuild service" onSelect={() => run(() => rebuildService.mutate(selectedServiceId))}>
                <Hammer />
                Rebuild
              </CommandItem>
            </CommandGroup>
          </>
        )}
      </CommandList>
    </CommandDialog>
  )
}
