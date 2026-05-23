import { useState } from 'react'
import { Rocket, Database, Zap, Search, ChevronRight, GitBranch } from 'lucide-react'
import { useTemplates } from '@/hooks/useServices'

interface TemplateGalleryProps {
  onSelect: (templateId: string) => void
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

export default function TemplateGallery({ onSelect, projectId }: TemplateGalleryProps) {
  const { data: templates = [] } = useTemplates()
  const [selectedId, setSelectedId] = useState<string | null>(null)

  const categories = Array.from(new Set(templates.map((t) => t.category)))

  return (
    <div className="space-y-4">
      <div className="text-[12px] text-white/40">
        Choose a template to generate a manifest. Templates are open-source —
        <a
          href="https://github.com/raildock/templates"
          target="_blank"
          rel="noopener noreferrer"
          className="text-[#8b5cf6] hover:underline ml-1"
        >
          contribute on GitHub
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
              {categoryTemplates.map((template) => (
                <button
                  key={template.id}
                  onClick={() => {
                    setSelectedId(template.id)
                    onSelect(template.id)
                  }}
                  className={`flex items-center gap-3 p-3 border rounded-lg text-left transition-all ${
                    selectedId === template.id
                      ? 'border-[#8b5cf6]/40 bg-[#8b5cf6]/5'
                      : 'border-white/[0.06] bg-[#1a1a1e] hover:border-white/[0.12]'
                  }`}
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
                  <ChevronRight size={14} className="text-white/20 flex-shrink-0" />
                </button>
              ))}
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
