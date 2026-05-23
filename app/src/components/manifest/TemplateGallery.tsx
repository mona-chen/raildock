import { useState } from 'react'
import { Rocket, Database, Zap, Search, ChevronRight, GitBranch, FileCode, Loader2 } from 'lucide-react'
import { useTemplates, useDeployTemplate } from '@/hooks/useServices'

interface TemplateGalleryProps {
  onUseAsManifest: (templateId: string, rawToml: string) => void
  projectId: string
}

const CATEGORY_ICONS: Record<string, React.ElementType> = {
  stack: Rocket,
  database: Database,
  cache: Zap,
  search: Search,
}

const CATEGORY_COLORS: Record<string, string> = {
  stack: '#8b5cf6',
  database: '#3b82f6',
  cache: '#f59e0b',
  search: '#ec4899',
}

export default function TemplateGallery({ onUseAsManifest, projectId }: TemplateGalleryProps) {
  const { data: templates = [] } = useTemplates()
  const deployTemplate = useDeployTemplate()
  const [deployingId, setDeployingId] = useState<string | null>(null)

  const categories = Array.from(new Set(templates.map((t) => t.category)))

  const handleDeploy = async (templateId: string) => {
    setDeployingId(templateId)
    try {
      await deployTemplate.mutateAsync({ templateId, projectId })
    } finally {
      setDeployingId(null)
    }
  }

  return (
    <div className="space-y-4">
      <div className="text-[12px] text-white/40">
        Templates are open-source TOML files. You can{' '}
        <span className="text-white/50 font-medium">load one into the editor</span> to customize it,
        or <span className="text-white/50 font-medium">deploy it directly</span> to create services.
        <a
          href="https://github.com/raildock/templates"
          target="_blank"
          rel="noopener noreferrer"
          className="text-[#8b5cf6] hover:underline ml-1"
        >
          Contribute on GitHub →
        </a>
      </div>

      {categories.map((category) => {
        const categoryTemplates = templates.filter((t) => t.category === category)
        const Icon = CATEGORY_ICONS[category] || Rocket
        const color = CATEGORY_COLORS[category] || '#8b5cf6'

        return (
          <div key={category}>
            <div className="flex items-center gap-2 mb-2">
              <Icon size={14} style={{ color }} />
              <span className="text-[11px] text-white/40 uppercase tracking-wider">{category}</span>
            </div>
            <div className="grid grid-cols-1 gap-2">
              {categoryTemplates.map((template) => {
                const isDeploying = deployingId === template.id
                return (
                  <div
                    key={template.id}
                    className="flex items-center gap-3 p-3 border border-white/[0.06] bg-[#1a1a1e] rounded-lg hover:border-white/[0.12] transition-all"
                  >
                    <div className="flex-1 min-w-0">
                      <div className="text-[13px] text-white/70 font-medium">{template.name}</div>
                      <div className="text-[11px] text-white/40">{template.description}</div>
                      <div className="flex items-center gap-2 mt-1.5">
                        {template.services?.map((s: { name: string; category: string }, i: number) => (
                          <span
                            key={i}
                            className="text-[10px] px-1.5 py-0.5 rounded bg-white/[0.05] text-white/30"
                          >
                            {s.name}
                          </span>
                        ))}
                      </div>
                    </div>
                    <div className="flex items-center gap-2 flex-shrink-0">
                      <button
                        onClick={() => onUseAsManifest(template.id, template.raw || '')}
                        disabled={!template.raw}
                        className="flex items-center gap-1.5 px-3 py-1.5 text-[11px] text-[#8b5cf6] bg-[#8b5cf6]/10 hover:bg-[#8b5cf6]/15 rounded-lg transition-all disabled:opacity-50"
                      >
                        <FileCode size={12} />
                        Use as Manifest
                      </button>
                      <button
                        onClick={() => handleDeploy(template.id)}
                        disabled={isDeploying}
                        className="flex items-center gap-1.5 px-3 py-1.5 text-[11px] text-white/60 bg-white/[0.06] hover:bg-white/[0.1] rounded-lg transition-all disabled:opacity-50"
                      >
                        {isDeploying ? <Loader2 size={12} className="animate-spin" /> : <Rocket size={12} />}
                        {isDeploying ? 'Deploying...' : 'Deploy'}
                      </button>
                    </div>
                  </div>
                )
              })}
            </div>
          </div>
        )
      })}

      {templates.length === 0 && (
        <div className="text-center py-6">
          <GitBranch size={24} className="text-white/20 mx-auto mb-2" />
          <div className="text-[13px] text-white/40">No templates loaded</div>
          <div className="text-[11px] text-white/25 mt-1">
            Templates are loaded from disk on boot.
            Set RAILDOCK_TEMPLATES_REPO for community templates.
          </div>
        </div>
      )}
    </div>
  )
}
