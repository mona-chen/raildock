import { describe, expect, it } from 'vitest'
import { tokenizeTomlLine } from '@/components/manifest/ManifestCodeEditor'

describe('tokenizeTomlLine', () => {
  it('highlights TOML tables and comments', () => {
    expect(tokenizeTomlLine('  [[services.proxy.ports]] # routing')).toEqual([
      { kind: 'plain', value: '  ' },
      { kind: 'table', value: '[[services.proxy.ports]]' },
      { kind: 'plain', value: ' ' },
      { kind: 'comment', value: '# routing' },
    ])
  })

  it('highlights assignment keys and typed values', () => {
    const tokens = tokenizeTomlLine('enabled = true # public')

    expect(tokens).toContainEqual({ kind: 'key', value: 'enabled' })
    expect(tokens).toContainEqual({ kind: 'boolean', value: 'true' })
    expect(tokens).toContainEqual({ kind: 'comment', value: '# public' })
  })

  it('does not treat hashes inside strings as comments', () => {
    expect(tokenizeTomlLine('color = "#8b5cf6"')).toContainEqual({
      kind: 'string',
      value: '"#8b5cf6"',
    })
  })
})
