import { useMemo, useRef, useState } from 'react'
import { ArrowUp, ChevronRight, Download, File, Folder, FolderOpen, Loader2, RefreshCw, Upload } from 'lucide-react'
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Button } from '@/components/ui/button'
import { IconButton } from '@/components/ui/icon-button'
import FileCodeViewer from '@/components/files/FileCodeViewer'
import { api } from '@/lib/api'
import { useServiceFileContent, useServiceFiles, useUploadServiceFile } from '@/hooks/useServices'
import type { AppFileEntry } from '@/types'

function formatSize(bytes = 0) {
  if (!bytes) return '—'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  const unit = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1)
  return `${(bytes / 1024 ** unit).toFixed(unit ? 1 : 0)} ${units[unit]}`
}

function childPath(base: string, name: string) {
  return base === '/' ? `/${name}` : `${base.replace(/\/$/, '')}/${name}`
}

function parentPath(path: string) {
  const parts = path.split('/').filter(Boolean)
  parts.pop()
  return parts.length ? `/${parts.join('/')}` : '/'
}

function breadcrumbs(path: string) {
  const parts = path.split('/').filter(Boolean)
  return [
    { label: '/', path: '/' },
    ...parts.map((part, index) => ({ label: part, path: `/${parts.slice(0, index + 1).join('/')}` })),
  ]
}

function downloadBlob(blob: Blob, name: string) {
  const url = URL.createObjectURL(blob)
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = name
  anchor.click()
  URL.revokeObjectURL(url)
}

export default function AppFilesTab({ serviceId }: { serviceId: string }) {
  const [path, setPath] = useState('')
  const [process, setProcess] = useState('web')
  const [selected, setSelected] = useState<AppFileEntry | null>(null)
  const [previewOpen, setPreviewOpen] = useState(false)
  const [overwrite, setOverwrite] = useState(false)
  const [actionError, setActionError] = useState<string | null>(null)
  const inputRef = useRef<HTMLInputElement>(null)
  const upload = useUploadServiceFile()

  const query = useServiceFiles(serviceId, path, process)
  const currentPath = query.data?.path ?? (path || '/')
  const processTypes = query.data?.processTypes ?? ['web']
  const selectedPath = selected?.type === 'file' ? childPath(currentPath, selected.name) : null
  const content = useServiceFileContent(serviceId, selectedPath, process)
  const entries = useMemo(() => {
    const rows = query.data?.entries ?? []
    return [...rows].sort((a, b) => {
      if (a.type === b.type) return a.name.localeCompare(b.name)
      return a.type === 'directory' ? -1 : 1
    })
  }, [query.data?.entries])

  const changeProcess = (value: string) => {
    setProcess(value)
    setPath('')
    setSelected(null)
    setPreviewOpen(false)
  }

  const download = async (entry: AppFileEntry) => {
    setActionError(null)
    try {
      const blob = await api.services.downloadFile(serviceId, childPath(currentPath, entry.name), process)
      downloadBlob(blob, entry.name)
    } catch (error) {
      setActionError(error instanceof Error ? error.message : 'Download failed')
    }
  }

  const uploadFile = (file: File) => {
    setActionError(null)
    upload.mutate(
      { id: serviceId, path: currentPath, file, process, overwrite },
      { onSuccess: () => setOverwrite(false) }
    )
  }

  return (
    <div className="space-y-4 p-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-[14px] font-medium text-white/90">Files</h2>
          <p className="mt-1 max-w-2xl text-[11px] leading-5 text-white/45">
            Browse the running container. Uploads are written to its temporary filesystem and are replaced on the next deploy; use Storage for data that must persist.
          </p>
        </div>
        <div className="flex items-center gap-2">
          {processTypes.length > 1 ? (
            <Select value={process} onValueChange={changeProcess}>
              <SelectTrigger className="h-8 w-32 border-white/10 bg-black/30 text-xs text-white/70" aria-label="Process type">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {processTypes.map((name) => <SelectItem key={name} value={name}>{name}</SelectItem>)}
              </SelectContent>
            </Select>
          ) : (
            <span className="rounded-md border border-white/8 px-2 py-1 text-[11px] text-white/45">{process}</span>
          )}
          <IconButton title="Refresh files" onClick={() => void query.refetch()} disabled={query.isFetching}>
            <RefreshCw className={query.isFetching ? 'animate-spin' : ''} />
          </IconButton>
          <Button size="sm" variant="secondary" className="h-8 gap-1.5 text-xs" onClick={() => inputRef.current?.click()} disabled={upload.isPending || query.isLoading}>
            {upload.isPending ? <Loader2 size={13} className="animate-spin" /> : <Upload size={13} />}
            Upload
          </Button>
          <input ref={inputRef} type="file" className="hidden" onChange={(event) => {
            const file = event.target.files?.[0]
            if (file) uploadFile(file)
            event.target.value = ''
          }} />
        </div>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-white/8 bg-white/[0.015] px-3 py-2">
        <div className="flex min-w-0 flex-wrap items-center gap-1 text-[11px]">
          <FolderOpen size={13} className="mr-1 text-amber-300/70" />
          {breadcrumbs(currentPath).map((crumb, index, all) => (
            <span key={crumb.path} className="flex items-center gap-1">
              <button type="button" onClick={() => setPath(crumb.path)} className="max-w-36 truncate rounded px-1 py-0.5 font-mono text-white/60 hover:bg-white/6 hover:text-white/85">
                {crumb.label}
              </button>
              {index < all.length - 1 && <ChevronRight size={11} className="text-white/20" />}
            </span>
          ))}
        </div>
        {currentPath !== '/' && (
          <button type="button" onClick={() => setPath(parentPath(currentPath))} className="flex items-center gap-1 rounded px-2 py-1 text-[11px] text-white/45 hover:bg-white/5 hover:text-white/70">
            <ArrowUp size={12} /> Up
          </button>
        )}
      </div>

      {actionError && <div role="alert" className="rounded-lg border border-red-400/20 bg-red-400/5 px-3 py-2 text-xs text-red-300">{actionError}</div>}
      {upload.error && <div role="alert" className="rounded-lg border border-red-400/20 bg-red-400/5 px-3 py-2 text-xs text-red-300">{upload.error.message}</div>}

      <div className="overflow-hidden rounded-lg border border-white/8 bg-[#17171b]">
        {query.isLoading ? (
          <div className="flex items-center justify-center gap-2 py-12 text-xs text-white/45"><Loader2 size={14} className="animate-spin" /> Reading container…</div>
        ) : query.error ? (
          <div role="alert" className="flex flex-col items-center gap-2 py-10 text-center">
            <p className="text-xs text-red-300">{query.error.message}</p>
            <button type="button" onClick={() => void query.refetch()} className="text-[11px] text-rail-purple-light hover:underline">Retry</button>
          </div>
        ) : entries.length === 0 ? (
          <div className="py-12 text-center text-xs text-white/30">This directory is empty.</div>
        ) : (
          <ul className="divide-y divide-white/5" aria-label={`Files in ${currentPath}`}>
            {entries.map((entry) => (
              <li key={entry.name} className="flex items-center gap-1 pr-2 hover:bg-white/[0.025]">
                <button
                  type="button"
                  onClick={() => {
                    if (entry.type === 'directory') {
                      setPath(childPath(currentPath, entry.name))
                      setSelected(null)
                    } else if (entry.type === 'file') {
                      setSelected(entry)
                      setPreviewOpen(true)
                    }
                  }}
                  disabled={entry.type === 'other'}
                  className="flex min-w-0 flex-1 items-center gap-2.5 px-3 py-2.5 text-left disabled:cursor-default"
                >
                  {entry.type === 'directory' ? <Folder size={14} className="shrink-0 text-amber-300/70" /> : <File size={14} className="shrink-0 text-white/40" />}
                  <span className="min-w-0 flex-1 truncate font-mono text-[11px] text-white/70">{entry.name}</span>
                  <span className="w-20 shrink-0 text-right text-[10px] tabular-nums text-white/25">{entry.type === 'directory' ? 'folder' : formatSize(entry.size)}</span>
                </button>
                {entry.type === 'file' && (
                  <IconButton title={`Download ${entry.name}`} onClick={() => void download(entry)} className="hover:bg-white/6 hover:text-white">
                    <Download />
                  </IconButton>
                )}
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3 text-[11px] text-white/35">
        <label className="flex items-center gap-2">
          <input type="checkbox" checked={overwrite} onChange={(event) => setOverwrite(event.target.checked)} className="accent-rail-purple" />
          Overwrite an existing file with the same name
        </label>
        {query.data?.truncated && <span>Showing the first {entries.length} entries.</span>}
      </div>

      <Dialog open={previewOpen} onOpenChange={(open) => { setPreviewOpen(open); if (!open) setSelected(null) }}>
        <DialogContent className="border-white/9 bg-[#19191d] text-white sm:max-w-5xl">
          <DialogHeader>
            <DialogTitle className="break-all text-[14px]">{selected?.name}</DialogTitle>
            <DialogDescription className="break-all font-mono text-[11px] text-white/40">{selectedPath}</DialogDescription>
          </DialogHeader>
          {content.isPending ? (
            <div className="flex items-center justify-center gap-2 py-12 text-xs text-white/45"><Loader2 size={14} className="animate-spin" /> Reading file…</div>
          ) : content.error ? (
            <div role="alert" className="py-8 text-center text-xs text-red-300">{content.error.message}</div>
          ) : content.data?.binary ? (
            <div className="rounded-lg border border-white/8 bg-black/20 px-4 py-10 text-center text-xs text-white/45">Binary file — download it to inspect the contents.</div>
          ) : content.data?.tooLarge ? (
            <div className="rounded-lg border border-white/8 bg-black/20 px-4 py-10 text-center text-xs text-white/45">This file is too large to preview. Download it instead.</div>
          ) : (
            <FileCodeViewer key={selectedPath ?? selected?.name ?? ''} content={content.data?.content ?? ''} filename={selected?.name ?? ''} />
          )}
          <div className="flex items-center justify-between gap-3">
            <span className="text-[11px] text-white/35">{content.data ? formatSize(content.data.size) : ''}</span>
            <Button size="sm" variant="secondary" className="gap-1.5" disabled={!selected || !content.data} onClick={() => selected && void download(selected)}>
              <Download size={13} /> Download
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}
