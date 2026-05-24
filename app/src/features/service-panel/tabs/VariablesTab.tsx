import { useState } from 'react'
import { FileCode, Plus, Check, Copy, Eye, EyeOff, Wrench, Trash2, AlertCircle } from 'lucide-react'
import { useProject } from '@/hooks/useProjects'
import { useSetEnvVar, useUnsetEnvVar } from '@/hooks/useServices'
import { useCopy } from '@/hooks/useCopy'
import { toast } from 'sonner'
import type { Service } from '@/types'

function resolveEnvRef(value: string, allServices: Service[]): string {
  const refPattern = /\$\{\{([^}]+)\}\}/g
  return value.replace(refPattern, (_, ref) => {
    const parts = ref.split('.')
    if (parts.length !== 2) return '${{' + ref + '}}'
    const [svcName, varName] = parts
    const target = allServices.find((s) => s.name === svcName)
    if (!target) return '${{' + ref + '}}'
    const targetVar = target.envVars.find((ev) => ev.key === varName)
    return targetVar?.value || '${{' + ref + '}}'
  })
}

export default function VariablesTab({ svc }: { svc: Service }) {
  const { data: project } = useProject(svc.projectId)
  const [mode, setMode] = useState<'list' | 'raw'>('list')
  const [rawText, setRawText] = useState('')
  const [editing, setEditing] = useState<string | null>(null)
  const [editValue, setEditValue] = useState('')
  const [newKey, setNewKey] = useState('')
  const [newVal, setNewVal] = useState('')
  const [revealed, setRevealed] = useState<Set<string>>(new Set())
  const { copiedKey, copy } = useCopy(1500)
  const setEnvVar = useSetEnvVar()
  const unsetEnvVar = useUnsetEnvVar()

  const userVars = svc.envVars.filter((ev) => !ev.isDokkuInternal)
  const dokkuVars = svc.envVars.filter((ev) => ev.isDokkuInternal)
  const sharedVars = project?.sharedVars || []

  const toggleReveal = (key: string) => {
    setRevealed((prev) => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })
  }

  const parseRawEnv = (text: string): { key: string; value: string }[] => {
    const out: { key: string; value: string }[] = []
    const lines = text.split('\n')
    for (const line of lines) {
      const trimmed = line.trim()
      if (!trimmed || trimmed.startsWith('#')) continue
      const eq = trimmed.indexOf('=')
      if (eq === -1) continue
      const key = trimmed.slice(0, eq).trim()
      let value = trimmed.slice(eq + 1).trim()
      if (
        (value.startsWith("'") && value.endsWith("'")) ||
        (value.startsWith('"') && value.endsWith('"'))
      ) {
        value = value.slice(1, -1)
      }
      if (key) out.push({ key, value })
    }
    return out
  }

  const formatRawEnv = (vars: typeof svc.envVars): string => {
    return vars
      .filter((ev) => !ev.isDokkuInternal)
      .map((ev) => {
        const needsQuotes = ev.value.includes(' ') || ev.value.includes('#') || ev.value.includes('=')
        return needsQuotes ? `${ev.key}="${ev.value}"` : `${ev.key}=${ev.value}`
      })
      .join('\n')
  }

  const handleRawSave = () => {
    const parsed = parseRawEnv(rawText)
    if (parsed.length === 0) {
      toast.error('No valid KEY=VALUE pairs found')
      return
    }
    for (const { key, value } of parsed) {
      setEnvVar.mutate({ id: svc.id, key, value })
    }
    setRawText('')
    setMode('list')
    toast.success(`Saved ${parsed.length} variable(s)`)
  }

  const handleInsertShared = (key: string) => {
    const ref = '${{shared.' + key + '}}'
    setNewVal((v) => (v ? v + ref : ref))
  }

  const maskValue = (val: string) => {
    if (val.length <= 8) return '••••••••'
    return val.slice(0, 2) + '•'.repeat(Math.min(val.length - 4, 16)) + val.slice(-2)
  }

  const renderVarRow = (ev: (typeof svc.envVars)[0], readonly?: boolean) => {
    const isRevealed = revealed.has(ev.key)
    const isEditing = editing === ev.key
    const displayValue = isRevealed || isEditing ? ev.value : maskValue(ev.value)
    const isReference = ev.value.includes('${{')

    return (
      <div
        key={ev.key}
        className={`flex items-start gap-3 border border-white/[0.06] rounded-xl p-3 group transition-colors ${
          ev.isDokkuInternal ? 'bg-[#131318]' : 'bg-[#1a1a1e] hover:border-white/[0.1]'
        }`}
      >
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <span className="text-[13px] font-mono text-[#8b5cf6]/80">{ev.key}</span>
            {ev.source && (
              <span className="text-[10px] px-1.5 py-0.5 bg-white/[0.06] text-white/40 rounded-full">
                {ev.source}
              </span>
            )}
            {ev.isDokkuInternal && (
              <span className="text-[10px] px-1.5 py-0.5 bg-[#22c55e]/10 text-[#22c55e]/60 rounded-full">
                dokku
              </span>
            )}
            {isReference && (
              <span className="text-[10px] px-1.5 py-0.5 bg-[#8b5cf6]/10 text-[#8b5cf6]/60 rounded-full">
                reference
              </span>
            )}
          </div>

          {isEditing ? (
            <div className="flex gap-2 mt-1">
              <input
                type="text"
                value={editValue}
                onChange={(e) => setEditValue(e.target.value)}
                autoFocus
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    setEnvVar.mutate({ id: svc.id, key: ev.key, value: editValue })
                    setEditing(null)
                  }
                  if (e.key === 'Escape') setEditing(null)
                }}
                className="flex-1 bg-black/40 border border-white/[0.08] rounded px-2 py-1 text-[12px] font-mono text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
              />
              <button
                onClick={() => {
                  setEnvVar.mutate({ id: svc.id, key: ev.key, value: editValue })
                  setEditing(null)
                }}
                className="px-2 py-1 bg-[#22c55e]/10 text-[#22c55e] rounded text-[11px] hover:bg-[#22c55e]/20"
              >
                Save
              </button>
              <button
                onClick={() => setEditing(null)}
                className="px-2 py-1 bg-white/5 text-white/40 rounded text-[11px] hover:bg-white/10"
              >
                Cancel
              </button>
            </div>
          ) : (
            <div className="text-[12px] text-white/50 font-mono break-all">{displayValue}</div>
          )}
        </div>

        <div className="flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
          <button
            onClick={() => copy(ev.value, ev.key)}
            className="p-1.5 hover:bg-white/[0.06] rounded text-white/20 hover:text-white/50"
            title="Copy value"
          >
            {copiedKey === ev.key ? <Check size={12} className="text-[#22c55e]" /> : <Copy size={12} />}
          </button>
          {!readonly && (
            <>
              <button
                onClick={() => toggleReveal(ev.key)}
                className="p-1.5 hover:bg-white/[0.06] rounded text-white/20 hover:text-white/50"
                title={isRevealed ? 'Hide value' : 'Show value'}
              >
                {isRevealed ? <EyeOff size={12} /> : <Eye size={12} />}
              </button>
              <button
                onClick={() => {
                  setEditing(ev.key)
                  setEditValue(ev.value)
                }}
                className="p-1.5 hover:bg-white/[0.06] rounded text-white/20 hover:text-white/50"
                title="Edit"
              >
                <Wrench size={12} />
              </button>
              <button
                onClick={() => unsetEnvVar.mutate({ id: svc.id, key: ev.key })}
                className="p-1.5 hover:bg-white/[0.06] rounded text-white/20 hover:text-red-400"
                title="Delete"
              >
                <Trash2 size={12} />
              </button>
            </>
          )}
        </div>
      </div>
    )
  }

  return (
    <div className="p-5 space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <div className="text-[14px] font-medium text-white/70">Environment Variables</div>
          <div className="text-[12px] text-white/40 mt-0.5">
            {userVars.length} user-defined · {dokkuVars.length} dokku-internal
          </div>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => {
              if (mode === 'list') {
                setRawText(formatRawEnv(svc.envVars))
                setMode('raw')
              } else {
                setMode('list')
              }
            }}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-white/5 text-white/50 rounded-lg text-[12px] hover:bg-white/10 hover:text-white/70 transition-all"
          >
            <FileCode size={13} />
            {mode === 'list' ? 'Raw Editor' : 'List View'}
          </button>
        </div>
      </div>

      {(setEnvVar.isPending || unsetEnvVar.isPending) && (
        <div className="bg-amber-500/5 border border-amber-500/20 rounded-lg p-3 flex items-center gap-2">
          <AlertCircle size={14} className="text-amber-400/60" />
          <span className="text-[12px] text-amber-400/70">
            Variable changes require a service restart to take effect.
          </span>
        </div>
      )}

      {mode === 'raw' && (
        <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4 space-y-3">
          <div className="text-[13px] font-medium text-white/70">Bulk Import</div>
          <p className="text-[11px] text-white/30">
            Paste <code className="text-white/50">KEY=VALUE</code> pairs, one per line. Lines starting with # are
            ignored.
          </p>
          <textarea
            value={rawText}
            onChange={(e) => setRawText(e.target.value)}
            placeholder={`DATABASE_URL=postgres://...\nREDIS_URL=redis://...\nAPI_KEY=sk-...`}
            className="w-full h-40 bg-black/30 border border-white/[0.08] rounded-lg px-3 py-2 text-[12px] font-mono text-white/60 focus:outline-none focus:border-[#8b5cf6]/40 resize-none"
          />
          <div className="flex items-center justify-between">
            <span className="text-[11px] text-white/30">{parseRawEnv(rawText).length} variable(s) ready to import</span>
            <div className="flex gap-2">
              <button
                onClick={() => {
                  setRawText('')
                  setMode('list')
                }}
                className="px-3 py-1.5 bg-white/5 text-white/40 rounded-lg text-[12px] hover:bg-white/10"
              >
                Cancel
              </button>
              <button
                onClick={handleRawSave}
                disabled={parseRawEnv(rawText).length === 0}
                className="flex items-center gap-1.5 px-3 py-1.5 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[12px] hover:bg-[#8b5cf6]/25 transition-all disabled:opacity-40"
              >
                <Plus size={12} />
                Import
              </button>
            </div>
          </div>
        </div>
      )}

      {mode === 'list' && (
        <>
          <div>
            <div className="flex items-center justify-between mb-3">
              <div className="text-[12px] font-medium text-white/50 uppercase tracking-wider">User Defined</div>
            </div>
            <div className="space-y-2">
              {userVars.length === 0 ? (
                <div className="text-[12px] text-white/20 py-4 text-center border border-dashed border-white/[0.06] rounded-xl">
                  No user-defined variables. Add one below or use the Raw Editor.
                </div>
              ) : (
                userVars.map((ev) => renderVarRow(ev))
              )}
            </div>
          </div>

          <div className="bg-[#1a1a1e] border border-white/[0.06] rounded-xl p-4">
            <div className="text-[13px] font-medium text-white/70 mb-3">Add Variable</div>
            <div className="flex gap-2">
              <input
                type="text"
                placeholder="KEY"
                value={newKey}
                onChange={(e) => setNewKey(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && e.preventDefault()}
                className="flex-1 bg-black/40 border border-white/[0.08] rounded-lg px-3 py-2 text-[12px] font-mono text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
              />
              <input
                type="text"
                placeholder="value or ${{Service.VAR}}"
                value={newVal}
                onChange={(e) => setNewVal(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' && newKey && newVal) {
                    setEnvVar.mutate({ id: svc.id, key: newKey, value: newVal })
                    setNewKey('')
                    setNewVal('')
                  }
                }}
                className="flex-[2] bg-black/40 border border-white/[0.08] rounded-lg px-3 py-2 text-[12px] font-mono text-white/70 focus:outline-none focus:border-[#8b5cf6]/40"
              />
              <button
                onClick={() => {
                  if (newKey && newVal) {
                    setEnvVar.mutate({ id: svc.id, key: newKey, value: newVal })
                    setNewKey('')
                    setNewVal('')
                  }
                }}
                disabled={!newKey || !newVal}
                className="px-4 py-2 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[12px] hover:bg-[#8b5cf6]/25 transition-all disabled:opacity-40"
              >
                Add
              </button>
            </div>

            {sharedVars.length > 0 && (
              <div className="mt-3 flex items-center gap-2 flex-wrap">
                <span className="text-[11px] text-white/30">Insert shared:</span>
                {sharedVars.map((sv) => (
                  <button
                    key={sv.key}
                    onClick={() => handleInsertShared(sv.key)}
                    className="text-[11px] px-2 py-1 bg-white/5 text-white/40 rounded hover:bg-white/10 hover:text-white/60 transition-colors"
                  >
                    {sv.key}
                  </button>
                ))}
              </div>
            )}
          </div>

          {dokkuVars.length > 0 && (
            <div>
              <div className="flex items-center justify-between mb-3">
                <div className="text-[12px] font-medium text-white/50 uppercase tracking-wider">Dokku-Injected</div>
                <span className="text-[10px] text-white/20">Read-only · managed by Dokku</span>
              </div>
              <div className="space-y-2">
                {dokkuVars.map((ev) => renderVarRow(ev, true))}
              </div>
              <p className="text-[11px] text-white/20 mt-2">
                These variables are automatically injected by Dokku when linking datastores. They are removed
                automatically when you unlink.
              </p>
            </div>
          )}
        </>
      )}
    </div>
  )
}
