import { describe, expect, it } from 'vitest'
import { formatMbAsGb } from '@/lib/utils'

describe('formatMbAsGb', () => {
  it('scales MB to GB instead of relabelling the raw number', () => {
    expect(formatMbAsGb(60_000)).toBe('58.6')
    expect(formatMbAsGb(18_400)).toBe('18')
  })

  it('keeps exact binary sizes whole', () => {
    expect(formatMbAsGb(8_192)).toBe('8')
    expect(formatMbAsGb(2_048)).toBe('2')
  })

  it('drops the fraction once it is noise', () => {
    expect(formatMbAsGb(102_400)).toBe('100')
  })

  it('renders absent metrics as zero', () => {
    expect(formatMbAsGb(0)).toBe('0')
    expect(formatMbAsGb(Number.NaN)).toBe('0')
  })
})
