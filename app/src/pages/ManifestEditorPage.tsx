import { useState, useCallback, useEffect, useRef } from 'react'
import { useParams } from 'react-router-dom'
import {
  FileCode, Play, Eye, AlertTriangle, CheckCircle2,
  ChevronLeft, Download, Copy, RotateCcw, Loader2,
  LayoutTemplate, BookOpen
} from 'lucide-react'
import { toast } from 'sonner'
import {
  useManifest,
  useUpdateManifest,
  useManifestPreview,
  useManifestApply,
  useManifestStatus,
} from '@/hooks/useManifest'
import DiffViewer from '@/components/manifest/DiffViewer'
import TemplateGallery from '@/components/manifest/TemplateGallery'
import ChangeBadge from '@/components/manifest/ChangeBadge'
import ManifestCodeEditor from '@/components/manifest/ManifestCodeEditor'
import type { ManifestChange } from '@/lib/api'
import type { ManifestRemoval } from '@/types'

const DEFAULT_MANIFEST = `# RailDock Manifest
# Docs: https://raildock.dev/docs/manifest

[[services]]
name = "web"
category = "app"
subtype = "web"
builder = "nixpacks"
source = { type = "git" }

  [services.scaling]
  web = 1

  [services.proxy]
  enabled = true
  type = "traefik"

    [[services.proxy.ports]]
    host = 80
    container = 3000
`

export default function ManifestEditorPage() {
  const { projectId } = useParams<{ projectId: string }>()
  const { data: manifest, isLoading } = useManifest(projectId!)
  const { data: status } = useManifestStatus(projectId!)
  const updateManifest = useUpdateManifest()
  const previewManifest = useManifestPreview()
  const applyManifest = useManifestApply()

  const [content, setContent] = useState(DEFAULT_MANIFEST)
  const hasEditedRef = useRef(false)
  const [activeTab, setActiveTab] = useState<'editor' | 'preview' | 'templates'>('editor')
  const [previewResult, setPreviewResult] = useState<{
    changes: ManifestChange[]
    severity: 'reload' | 'restart' | 'redeploy'
    bySeverity: Record<string, number>
    warnings: string[]
    removals?: ManifestRemoval[]
    removalToken?: string
  } | null>(null)
  const [showRemovalConfirm, setShowRemovalConfirm] = useState(false)
  const [removalAcknowledged, setRemovalAcknowledged] = useState(false)
  const [destroyWithoutSnapshot, setDestroyWithoutSnapshot] = useState(false)

  useEffect(() => {
    if (manifest?.content && !hasEditedRef.current) {
      setContent(manifest.content)
    }
  }, [manifest])

  const handlePreview = useCallback(async () => {
    if (!projectId) return
    // First save the manifest to get validation
    await updateManifest.mutateAsync({ projectId, content })
    // Then get the diff
    const result = await previewManifest.mutateAsync({ projectId })
    setPreviewResult(result)
    setActiveTab('preview')
  }, [projectId, content, updateManifest, previewManifest])

  const removals = previewResult?.removals ?? []

  const performApply = useCallback(
    async (confirmRemovals: boolean) => {
      if (!projectId || !previewResult) return
      await applyManifest.mutateAsync({
        projectId,
        confirmRemovals,
        removalConfirmationToken: confirmRemovals ? previewResult.removalToken : undefined,
        forceDestroyData: confirmRemovals && destroyWithoutSnapshot,
      })
      setPreviewResult(null)
      setShowRemovalConfirm(false)
      setRemovalAcknowledged(false)
      setDestroyWithoutSnapshot(false)
    },
    [projectId, previewResult, applyManifest, destroyWithoutSnapshot],
  )

  const handleApply = useCallback(async () => {
    if (!projectId) return
    if (!previewResult || previewResult.changes.length === 0) {
      toast.error('No changes to apply')
      return
    }
    // Services the manifest no longer declares are never removed silently: the
    // backend keeps them unless we confirm this exact list.
    if (removals.length > 0) {
      setShowRemovalConfirm(true)
      return
    }
    await performApply(false)
  }, [projectId, previewResult, removals.length, performApply])

  const handleCopy = useCallback(() => {
    navigator.clipboard.writeText(content)
    toast.success('Copied to clipboard')
  }, [content])

  const handleReset = useCallback(() => {
    hasEditedRef.current = false
    if (manifest?.content) {
      setContent(manifest.content)
    } else {
      setContent(DEFAULT_MANIFEST)
    }
    setPreviewResult(null)
  }, [manifest])

  const handleUseAsManifest = useCallback((templateId: string, rawToml: string) => {
    if (!rawToml) {
      toast.error('Template source not available')
      return
    }
    setContent(rawToml)
    setPreviewResult(null)
    setActiveTab('editor')
    toast.success(`Loaded "${templateId}" into editor`)
  }, [])

  const hasChanges = content !== (manifest?.content || '')
  const isApplying = applyManifest.isPending
  const isPreviewing = previewManifest.isPending || updateManifest.isPending

  return (
    <div className="h-full flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-white/[0.06]">
        <div className="flex items-center gap-3">
          <button
            onClick={() => window.history.back()}
            className="p-1.5 hover:bg-white/[0.06] rounded-lg text-white/30 hover:text-white/60 transition-colors"
          >
            <ChevronLeft size={16} />
          </button>
          <div className="flex items-center gap-2">
            <FileCode size={16} className="text-[#8b5cf6]" />
            <span className="text-[14px] font-medium text-white/80">Manifest Editor</span>
          </div>
          {status?.driftDetected && (
            <div className="flex items-center gap-1.5 text-[11px] text-amber-400 bg-amber-500/10 px-2 py-0.5 rounded">
              <AlertTriangle size={12} />
              Drift detected
            </div>
          )}
          {status?.synced && (
            <div className="flex items-center gap-1.5 text-[11px] text-emerald-400 bg-emerald-500/10 px-2 py-0.5 rounded">
              <CheckCircle2 size={12} />
              In sync
            </div>
          )}
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={handleCopy}
            className="flex items-center gap-1.5 px-3 py-1.5 text-[12px] text-white/40 hover:text-white/60 hover:bg-white/[0.04] rounded-lg transition-all"
          >
            <Copy size={13} />
            Copy
          </button>
          <button
            onClick={handleReset}
            className="flex items-center gap-1.5 px-3 py-1.5 text-[12px] text-white/40 hover:text-white/60 hover:bg-white/[0.04] rounded-lg transition-all"
          >
            <RotateCcw size={13} />
            Reset
          </button>
          <button
            onClick={handlePreview}
            disabled={isPreviewing || !hasChanges}
            className="flex items-center gap-1.5 px-3 py-1.5 text-[12px] text-[#8b5cf6] bg-[#8b5cf6]/10 hover:bg-[#8b5cf6]/15 rounded-lg transition-all disabled:opacity-50"
          >
            {isPreviewing ? <Loader2 size={13} className="animate-spin" /> : <Eye size={13} />}
            Preview
          </button>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex items-center gap-1 px-4 border-b border-white/[0.06]">
        {[
          { id: 'editor' as const, label: 'Editor', icon: FileCode },
          { id: 'preview' as const, label: 'Preview', icon: Eye },
          { id: 'templates' as const, label: 'Templates', icon: LayoutTemplate },
        ].map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={`flex items-center gap-1.5 px-3 py-2 text-[12px] border-b-2 transition-all ${
              activeTab === tab.id
                ? 'text-[#8b5cf6] border-[#8b5cf6]'
                : 'text-white/40 border-transparent hover:text-white/60'
            }`}
          >
            <tab.icon size={13} />
            {tab.label}
            {tab.id === 'preview' && previewResult && (
              <span className="ml-1 text-[10px] px-1.5 py-0.5 rounded-full bg-white/[0.06]">
                {previewResult.changes.length}
              </span>
            )}
          </button>
        ))}
      </div>

      {/* Content */}
      <div className="flex-1 overflow-hidden">
        {activeTab === 'editor' && (
          <div className="h-full flex">
            <div className="flex-1 flex flex-col">
              <div className="px-3 py-1.5 border-b border-white/[0.04] flex items-center gap-2">
                <span className="text-[10px] text-white/30 font-mono">
                  {manifest?.format || 'raildock.toml'}
                </span>
                {hasChanges && (
                  <span className="text-[10px] text-amber-400/60">· unsaved changes</span>
                )}
              </div>
              <ManifestCodeEditor
                value={content}
                onChange={(value) => {
                  hasEditedRef.current = true
                  setContent(value)
                  setPreviewResult(null)
                }}
              />
            </div>
            <div className="w-[320px] border-l border-white/[0.06] bg-white/[0.01] overflow-y-auto">
              <div className="p-4 space-y-4">
                <div>
                  <div className="text-[11px] text-white/40 uppercase tracking-wider mb-2">Quick Reference</div>
                  <div className="space-y-2 text-[11px] text-white/30">
                    <div><code className="text-white/50">[[services]]</code> — Define a service</div>
                    <div><code className="text-white/50">name</code> — Service name</div>
                    <div><code className="text-white/50">category</code> — app, database, cache</div>
                    <div><code className="text-white/50">subtype</code> — rails, node, postgres</div>
                    <div><code className="text-white/50">[services.scaling]</code> — Process counts</div>
                    <div><code className="text-white/50">[services.env]</code> — Environment variables</div>
                    <div><code className="text-white/50">[[services.proxy.ports]]</code> — Port mappings</div>
                    <div><code className="text-white/50">[[links]]</code> — Service links</div>
                  </div>
                </div>
                <div className="border-t border-white/[0.06] pt-3">
                  <div className="text-[11px] text-white/40 uppercase tracking-wider mb-2">Formats</div>
                  <div className="space-y-1.5">
                    <div className="flex items-center gap-2 text-[11px]">
                      <div className="w-2 h-2 rounded-full bg-[#8b5cf6]" />
                      <span className="text-white/50">raildock.toml</span>
                      <span className="text-white/25">— Full features</span>
                    </div>
                    <div className="flex items-center gap-2 text-[11px]">
                      <div className="w-2 h-2 rounded-full bg-white/20" />
                      <span className="text-white/50">app.json</span>
                      <span className="text-white/25">— Heroku compatible</span>
                    </div>
                    <div className="flex items-center gap-2 text-[11px]">
                      <div className="w-2 h-2 rounded-full bg-white/20" />
                      <span className="text-white/50">railway.toml</span>
                      <span className="text-white/25">— Railway compatible</span>
                    </div>
                    <div className="flex items-center gap-2 text-[11px]">
                      <div className="w-2 h-2 rounded-full bg-white/20" />
                      <span className="text-white/50">railway.json</span>
                      <span className="text-white/25">— Railway compatible</span>
                    </div>
                  </div>
                </div>
                <a
                  href="https://raildock.dev/docs/manifest"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center gap-2 text-[11px] text-[#8b5cf6] hover:underline"
                >
                  <BookOpen size={12} />
                  Full manifest documentation
                </a>
              </div>
            </div>
          </div>
        )}

        {activeTab === 'preview' && (
          <div className="h-full flex">
            <div className="flex-1 overflow-y-auto p-4">
              {previewResult ? (
                <DiffViewer
                  changes={previewResult.changes}
                  severity={previewResult.severity}
                  warnings={previewResult.warnings}
                />
              ) : (
                <div className="text-center py-12">
                  <Eye size={32} className="text-white/10 mx-auto mb-3" />
                  <div className="text-[13px] text-white/40">No preview yet</div>
                  <div className="text-[11px] text-white/25 mt-1">
                    Click Preview in the toolbar to see what changes will be applied
                  </div>
                </div>
              )}
            </div>
            {previewResult && previewResult.changes.length > 0 && (
              <div className="w-[280px] border-l border-white/[0.06] bg-white/[0.01] p-4">
                <div className="text-[11px] text-white/40 uppercase tracking-wider mb-3">Summary</div>
                <div className="space-y-2 mb-4">
                  <div className="flex items-center justify-between text-[12px]">
                    <span className="text-white/50">Total changes</span>
                    <span className="text-white/70 font-medium">{previewResult.changes.length}</span>
                  </div>
                  <div className="flex items-center justify-between text-[12px]">
                    <span className="text-white/50">Max severity</span>
                    <ChangeBadge severity={previewResult.severity} />
                  </div>
                </div>
                <div className="border-t border-white/[0.06] pt-3">
                  <div className="text-[11px] text-white/40 uppercase tracking-wider mb-2">Impact</div>
                  <div className="text-[11px] text-white/30">
                    {previewResult.severity === 'reload' && 'These changes can be applied without restarting any services.'}
                    {previewResult.severity === 'restart' && 'Some services will be restarted. There may be brief downtime.'}
                    {previewResult.severity === 'redeploy' && 'Full rebuilds are required. Services will be unavailable during deploy.'}
                  </div>
                </div>
                {removals.length > 0 && (
                  <div className="mt-3 bg-red-500/5 border border-red-500/20 rounded-lg p-3">
                    <div className="flex items-center gap-1.5 text-[11px] text-red-400 font-medium mb-1.5">
                      <AlertTriangle size={12} />
                      {removals.length} service{removals.length === 1 ? '' : 's'} not in this manifest
                    </div>
                    <div className="text-[11px] text-white/40 mb-2">
                      They will be kept unless you confirm their removal.
                    </div>
                    <ul className="space-y-1">
                      {removals.map((removal) => (
                        <li key={removal.serviceName} className="text-[11px] font-mono text-white/60">
                          {removal.serviceName}
                          {removal.datastore && <span className="ml-1 text-red-400/70">(database)</span>}
                        </li>
                      ))}
                    </ul>
                  </div>
                )}
                <button
                  onClick={handleApply}
                  disabled={isApplying}
                  className="w-full mt-4 py-2.5 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[13px] font-medium hover:bg-[#8b5cf6]/25 transition-all disabled:opacity-50 flex items-center justify-center gap-2"
                >
                  {isApplying ? <Loader2 size={14} className="animate-spin" /> : <Play size={14} />}
                  {isApplying ? 'Applying...' : 'Apply Changes'}
                </button>
              </div>
            )}
          </div>
        )}

        {activeTab === 'templates' && (
          <div className="h-full overflow-y-auto p-4">
            <TemplateGallery projectId={projectId!} onUseAsManifest={handleUseAsManifest} />
          </div>
        )}
      </div>

      {showRemovalConfirm && (
        <div
          className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-center justify-center px-4"
          onClick={() => setShowRemovalConfirm(false)}
        >
          <div
            className="bg-[#18181B] border border-red-500/20 rounded-2xl p-6 w-full max-w-[460px] shadow-2xl"
            onClick={(event) => event.stopPropagation()}
          >
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 rounded-full bg-red-500/10 flex items-center justify-center">
                <AlertTriangle size={18} className="text-red-400" />
              </div>
              <div>
                <h3 className="text-base font-semibold text-white">Confirm service removals</h3>
                <p className="text-xs text-[#6B6B7B]">This deletes data and cannot be undone</p>
              </div>
            </div>

            <p className="text-sm text-[#A0A0B0] mb-3">
              This manifest does not declare the following services. Applying it will destroy them:
            </p>

            <ul className="space-y-2 mb-4 max-h-[220px] overflow-y-auto">
              {removals.map((removal) => (
                <li key={removal.serviceName} className="bg-black/30 border border-white/[0.06] rounded-lg p-3">
                  <div className="flex items-center justify-between">
                    <span className="text-[13px] font-mono text-white">{removal.serviceName}</span>
                    <span className="text-[11px] text-white/40">{removal.serviceType}/{removal.subtype}</span>
                  </div>
                  <div className="text-[11px] text-white/40 mt-1">
                    {removal.datastore ? 'Database — data will be destroyed. ' : ''}
                    {removal.storageMounts.length > 0
                      ? `${removal.storageMounts.length} volume(s) attached. `
                      : ''}
                    {removal.completedBackups > 0
                      ? `${removal.completedBackups} existing backup(s) preserved.`
                      : 'No existing backup recorded.'}
                  </div>
                </li>
              ))}
            </ul>

            <label className="flex items-start gap-2 mb-3 text-[11px] text-[#A0A0B0]">
              <input
                type="checkbox"
                checked={removalAcknowledged}
                onChange={(event) => setRemovalAcknowledged(event.target.checked)}
                className="mt-0.5"
              />
              I understand these services and their data will be permanently destroyed.
            </label>

            {removals.some((removal) => removal.dataBearing) && (
              <label className="flex items-start gap-2 mb-3 text-[11px] text-[#A0A0B0]">
                <input
                  type="checkbox"
                  checked={destroyWithoutSnapshot}
                  onChange={(event) => setDestroyWithoutSnapshot(event.target.checked)}
                  className="mt-0.5"
                />
                Destroy even if no verified snapshot can be taken (unrecoverable).
              </label>
            )}

            <div className="flex gap-2">
              <button
                onClick={() => setShowRemovalConfirm(false)}
                className="flex-1 py-2.5 border border-[rgba(255,255,255,0.08)] text-[#A0A0B0] text-sm rounded-lg hover:bg-[rgba(255,255,255,0.04)] transition-all"
              >
                Keep services
              </button>
              <button
                onClick={() => performApply(true)}
                disabled={!removalAcknowledged || isApplying}
                className="flex-1 py-2.5 bg-red-500 text-white text-sm font-medium rounded-lg hover:bg-red-600 transition-all disabled:opacity-30 disabled:cursor-not-allowed"
              >
                {isApplying ? 'Destroying...' : 'Destroy and apply'}
              </button>
            </div>

            <button
              onClick={() => performApply(false)}
              disabled={isApplying}
              className="w-full mt-2 py-2 text-[11px] text-white/40 hover:text-white/60 transition-all disabled:opacity-50"
            >
              Apply everything else and keep these services
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
