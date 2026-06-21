import { useState, useEffect } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { Mail, Check } from 'lucide-react'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import { adminSettingsApi } from '@/lib/api'
import { toast } from 'sonner'
import type { SystemSetting } from '@/types'

const SMTP_KEYS = ['smtp_enabled', 'smtp_address', 'smtp_port', 'smtp_username', 'smtp_password', 'smtp_domain', 'smtp_auth', 'smtp_starttls'] as const

function settingValue(settings: SystemSetting[], key: string): string {
  return settings.find(s => s.key === key)?.value ?? ''
}

export default function SmtpConfigPanel() {
  const queryClient = useQueryClient()
  const { data: settings = [], isLoading } = useQuery<SystemSetting[]>({
    queryKey: ['admin-settings'],
    queryFn: () => adminSettingsApi.list(),
    staleTime: 30_000,
  })

  const [form, setForm] = useState<Record<string, string>>({})
  const [testEmail, setTestEmail] = useState('')

  useEffect(() => {
    if (settings.length) {
      setForm(Object.fromEntries(SMTP_KEYS.map(k => [k, settingValue(settings, k)])))
    }
  }, [settings])

  const updateMutation = useMutation({
    mutationFn: (values: Record<string, string | undefined>) => adminSettingsApi.update(values),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin-settings'] })
      toast.success('SMTP settings saved')
    },
    onError: (err: Error) => toast.error(`Failed to save: ${err.message}`),
  })

  const testMutation = useMutation({
    mutationFn: () => adminSettingsApi.testSmtp(testEmail || undefined),
    onSuccess: () => toast.success('Test email sent successfully'),
    onError: (err: Error) => toast.error(`Test email failed: ${err.message}`),
  })

  const handleSave = () => {
    updateMutation.mutate(form)
  }

  const handleTest = () => {
    testMutation.mutate()
  }

  const enabled = form.smtp_enabled === 'true'

  if (isLoading) {
    return <div className="text-xs text-[#4A4A55]">Loading...</div>
  }

  return (
    <div className="space-y-5">
      <div className="bg-[rgba(255,255,255,0.02)] border border-[rgba(255,255,255,0.05)] rounded-xl p-5">
        <div className="flex items-center justify-between mb-4">
          <div className="text-[10px] text-[#4A4A55] uppercase tracking-wider font-medium flex items-center gap-2">
            <Mail size={12} className="text-rail-purple" /> SMTP Configuration
          </div>
          <label className="flex items-center gap-2 cursor-pointer" htmlFor="smtp-enabled">
            <span className="text-[10px] text-[#4A4A55] uppercase tracking-wider font-medium">Enabled</span>
            <input
              id="smtp-enabled"
              type="checkbox"
              className="sr-only"
              checked={form.smtp_enabled === 'true'}
              onChange={() => setForm(f => ({ ...f, smtp_enabled: f.smtp_enabled === 'true' ? 'false' : 'true' }))}
            />
            <div
              className="relative w-8 h-4 rounded-full transition-colors"
              style={{ backgroundColor: form.smtp_enabled === 'true' ? '#7C3AED' : '#2a2a30' }}
            >
              <div
                className="absolute top-0.5 w-3 h-3 bg-white rounded-full transition-transform pointer-events-none"
                style={{ transform: form.smtp_enabled === 'true' ? 'translateX(16px)' : 'translateX(2px)' }}
              />
            </div>
          </label>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <Field label="Address" value={form.smtp_address ?? ''} onChange={v => setForm(f => ({ ...f, smtp_address: v }))} placeholder="smtp.example.com" />
          <Field label="Port" value={form.smtp_port ?? ''} onChange={v => setForm(f => ({ ...f, smtp_port: v }))} placeholder="587" />
          <Field label="Username" value={form.smtp_username ?? ''} onChange={v => setForm(f => ({ ...f, smtp_username: v }))} placeholder="user@example.com" />
          <Field label="Password" value={form.smtp_password ?? ''} onChange={v => setForm(f => ({ ...f, smtp_password: v }))} type="password" placeholder="••••••••" />
          <Field label="Domain" value={form.smtp_domain ?? ''} onChange={v => setForm(f => ({ ...f, smtp_domain: v }))} placeholder="example.com" />
          <div className="space-y-1">
            <label htmlFor="smtp-auth" className="text-[10px] text-[#4A4A55] uppercase tracking-wider font-medium">Auth</label>
            <select
              id="smtp-auth"
              value={form.smtp_auth ?? 'plain'}
              onChange={e => setForm(f => ({ ...f, smtp_auth: e.target.value }))}
              className="w-full h-9 px-2.5 text-xs text-white bg-[rgba(255,255,255,0.03)] border border-[rgba(255,255,255,0.08)] rounded-lg focus:outline-none focus:border-rail-purple transition-colors"
            >
              <option value="plain">plain</option>
              <option value="login">login</option>
              <option value="cram_md5">cram_md5</option>
            </select>
          </div>
        </div>

        <div className="flex items-center gap-3 mt-4">
          <Button
            size="sm"
            onClick={handleSave}
            disabled={updateMutation.isPending}
            className="bg-rail-purple hover:bg-rail-purple/90 text-white text-xs h-8"
          >
            {updateMutation.isPending ? 'Saving...' : 'Save'}
          </Button>

          {enabled && (
            <div className="flex items-center gap-2 ml-auto">
              <Input
                value={testEmail}
                onChange={e => setTestEmail(e.target.value)}
                placeholder="your@email.com"
                className="w-48 h-8 text-xs bg-[rgba(255,255,255,0.03)] border-[rgba(255,255,255,0.08)] text-white placeholder:text-[#4A4A55]"
              />
              <Button
                size="sm"
                variant="outline"
                onClick={handleTest}
                disabled={testMutation.isPending}
                className="text-xs h-8 border-[rgba(255,255,255,0.08)] text-[#A0A0B0] hover:text-white"
              >
                {testMutation.isPending ? 'Sending...' : 'Send Test'}
              </Button>
            </div>
          )}
        </div>

        {enabled && (
          <div className="flex items-center gap-1.5 mt-3">
            <Check size={10} className="text-green-500" />
            <span className="text-[10px] text-green-500">SMTP configured</span>
          </div>
        )}
      </div>
    </div>
  )
}

function Field({ label, value, onChange, placeholder, type }: {
  label: string
  value: string
  onChange: (v: string) => void
  placeholder?: string
  type?: string
}) {
  return (
    <div className="space-y-1">
      <label className="text-[10px] text-[#4A4A55] uppercase tracking-wider font-medium">{label}</label>
      <Input
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder={placeholder}
        type={type ?? 'text'}
        className="h-9 text-xs text-white bg-[rgba(255,255,255,0.03)] border-[rgba(255,255,255,0.08)] placeholder:text-[#4A4A55]"
      />
    </div>
  )
}