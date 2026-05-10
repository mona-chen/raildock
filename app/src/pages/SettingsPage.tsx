import { Settings, GitBranch, Globe, Database, Server, Puzzle } from 'lucide-react'
import { useGitSources } from '@/hooks/useGitSources'
import { useModules, useNetworks } from '@/hooks/useModules'

export default function SettingsPage() {
  const { data: gitSources = [] } = useGitSources()
  const { data: modules = [] } = useModules()
  const { data: networks = [] } = useNetworks()

  return (
    <div className="h-full flex flex-col overflow-hidden">
      <div className="px-6 py-4 border-b border-[rgba(255,255,255,0.06)]">
        <div className="flex items-center gap-3">
          <Settings size={18} className="text-rail-purple" />
          <h1 className="text-base font-semibold text-white">Platform Settings</h1>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-6">
        <div className="max-w-3xl space-y-5">
          {/* Git Sources */}
          <div className="bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-xl p-5">
            <div className="text-[10px] text-[#4A4A55] uppercase tracking-wider font-medium mb-3 flex items-center gap-2">
              <GitBranch size={12} className="text-rail-purple" /> Git Sources
            </div>
            <div className="space-y-2">
              {gitSources.map((gs) => {
                const Icon = gs.provider === 'github' ? GitBranch : gs.provider === 'gitlab' ? Globe : Database
                return (
                  <div key={gs.id} className="flex items-center justify-between p-3 bg-[rgba(255,255,255,0.02)] rounded-lg">
                    <div className="flex items-center gap-2.5">
                      <Icon size={16} className={gs.connected ? 'text-white' : 'text-[#4A4A55]'} />
                      <span className="text-sm text-white capitalize">{gs.provider}</span>
                    </div>
                    <span className={`text-[10px] px-2 py-0.5 rounded-full ${gs.connected ? 'bg-rail-green/10 text-rail-green' : 'bg-[rgba(255,255,255,0.04)] text-[#4A4A55]'}`}>
                      {gs.connected ? `Connected (${gs.repos.length} repos)` : 'Not connected'}
                    </span>
                  </div>
                )
              })}
            </div>
          </div>

          {/* Installed Modules */}
          <div className="bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-xl p-5">
            <div className="text-[10px] text-[#4A4A55] uppercase tracking-wider font-medium mb-3 flex items-center gap-2">
              <Puzzle size={12} className="text-rail-purple" /> Modules
            </div>
            <div className="space-y-2">
              {modules.map((mod) => (
                <div key={mod.id} className="flex items-center justify-between p-3 bg-[rgba(255,255,255,0.02)] rounded-lg">
                  <div>
                    <div className="text-sm text-white">{mod.name}</div>
                    <div className="text-[10px] text-[#4A4A55]">{mod.description}</div>
                  </div>
                  <div className="flex gap-1">
                    {mod.services.map((s) => (
                      <span key={s.subtype} className="text-[9px] px-1.5 py-0.5 bg-[rgba(139,92,246,0.08)] text-rail-purple rounded capitalize">{s.subtype}</span>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Docker Networks */}
          <div className="bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-xl p-5">
            <div className="text-[10px] text-[#4A4A55] uppercase tracking-wider font-medium mb-3 flex items-center gap-2">
              <Server size={12} className="text-rail-purple" /> Docker Networks
            </div>
            <div className="space-y-2">
              {networks.map((net) => (
                <div key={net.name} className="flex items-center justify-between p-3 bg-[rgba(255,255,255,0.02)] rounded-lg">
                  <div>
                    <div className="text-sm text-white font-mono">{net.name}</div>
                    <div className="text-[10px] text-[#4A4A55]">{net.apps.length} services</div>
                  </div>
                  <div className="flex flex-wrap gap-1 max-w-[200px] justify-end">
                    {net.apps.map((app) => (
                      <span key={app} className="text-[9px] px-1.5 py-0.5 bg-[rgba(255,255,255,0.04)] text-[#A0A0B0] rounded font-mono">{app}</span>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
