import { useState } from 'react'
import { Input } from '@/components/ui/input'
import { Switch } from '@/components/ui/switch'
import { Label } from '@/components/ui/label'
import { Button } from '@/components/ui/button'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import type { ConfigSchemaField } from '@/types'

interface ConfigSchemaFormProps {
  schema: Record<string, ConfigSchemaField>
  initialValues?: Record<string, string | number | boolean>
  onSubmit: (values: Record<string, string | number | boolean>) => void
  isSubmitting?: boolean
}

function buildDefaults(schema: Record<string, ConfigSchemaField>, initialValues?: Record<string, string | number | boolean>) {
  const defaults: Record<string, string | number | boolean> = {}
  Object.entries(schema).forEach(([key, field]) => {
    if (initialValues && key in initialValues) {
      defaults[key] = initialValues[key]
    } else if (field.default !== undefined) {
      defaults[key] = field.default
    } else if (field.type === 'boolean') {
      defaults[key] = false
    } else {
      defaults[key] = ''
    }
  })
  return defaults
}

export default function ConfigSchemaForm({ schema, initialValues, onSubmit, isSubmitting }: ConfigSchemaFormProps) {
  const [values, setValues] = useState<Record<string, string | number | boolean>>(() =>
    buildDefaults(schema, initialValues)
  )

  const handleChange = (key: string, value: string | number | boolean) => {
    setValues((prev) => ({ ...prev, [key]: value }))
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    onSubmit(values)
  }

  const fields = Object.entries(schema)
  if (fields.length === 0) {
    return <div className="text-[11px] text-[#4A4A55]">No configuration options for this plugin.</div>
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      {fields.map(([key, field]) => (
        <div key={key} className="space-y-1.5">
          <div className="flex items-center justify-between">
            <Label className="text-[11px] text-[#A0A0B0]">
              {field.label || key}
              {field.required && <span className="text-red-400 ml-1">*</span>}
            </Label>
          </div>
          {field.description && (
            <p className="text-[10px] text-[#4A4A55]">{field.description}</p>
          )}
          {renderField(key, field, values[key], handleChange)}
        </div>
      ))}
      <Button
        type="submit"
        disabled={isSubmitting}
        className="bg-rail-purple hover:bg-rail-purple/90 text-white text-xs h-8"
      >
        {isSubmitting ? 'Saving...' : 'Save Settings'}
      </Button>
    </form>
  )
}

function renderField(
  key: string,
  field: ConfigSchemaField,
  value: string | number | boolean | undefined,
  onChange: (key: string, value: string | number | boolean) => void
) {
  const commonInputClass =
    'bg-[rgba(255,255,255,0.04)] border-[rgba(255,255,255,0.08)] text-sm h-9 text-white placeholder:text-[#4A4A55]'

  switch (field.type) {
    case 'boolean':
      return (
        <Switch
          checked={value === true}
          onCheckedChange={(checked) => onChange(key, checked)}
          className="data-[state=checked]:bg-rail-purple"
        />
      )
    case 'select':
      return (
        <Select value={String(value ?? '')} onValueChange={(v) => onChange(key, v)}>
          <SelectTrigger className={commonInputClass}>
            <SelectValue placeholder="Select..." />
          </SelectTrigger>
          <SelectContent className="bg-[#1A1A1F] border-[rgba(255,255,255,0.1)]">
            {field.options?.map((opt) => (
              <SelectItem key={String(opt)} value={String(opt)} className="text-sm text-white">
                {String(opt)}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      )
    case 'number':
    case 'integer':
      return (
        <Input
          type="number"
          value={typeof value === 'boolean' ? '' : (value ?? '')}
          onChange={(e) => onChange(key, e.target.value === '' ? '' : Number(e.target.value))}
          min={field.min}
          max={field.max}
          className={commonInputClass}
        />
      )
    case 'string':
    default:
      return (
        <Input
          type="text"
          value={typeof value === 'boolean' ? '' : (value ?? '')}
          onChange={(e) => onChange(key, e.target.value)}
          className={commonInputClass}
        />
      )
  }
}
