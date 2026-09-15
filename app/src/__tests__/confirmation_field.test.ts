import { describe, expect, it } from 'vitest'
import { confirmationFieldTone } from '@/lib/utils'

describe('confirmationFieldTone', () => {
  it('stays neutral while the field is empty', () => {
    const tone = confirmationFieldTone('', false)

    expect(tone).not.toContain('red')
    expect(tone).not.toContain('emerald')
    expect(tone).toContain('border-[rgba(255,255,255,0.08)]')
  })

  it('flags a typed value that does not match', () => {
    const tone = confirmationFieldTone('jea', false)

    expect(tone).toContain('border-red-500/40')
    expect(tone).not.toContain('emerald')
  })

  it('confirms a matching value', () => {
    const tone = confirmationFieldTone('jean', true)

    expect(tone).toContain('border-emerald-500/40')
    expect(tone).not.toContain('border-red-500/40')
  })
})
