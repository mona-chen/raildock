import { describe, expect, it } from 'vitest'
import { detectLanguage, tokenizeFileLine } from '@/lib/fileViewer'

describe('file viewer language detection', () => {
  it('recognizes common source files', () => {
    expect(detectLanguage('src/app.tsx')).toBe('typescript')
    expect(detectLanguage('config/app.yml')).toBe('yaml')
    expect(detectLanguage('Dockerfile')).toBe('dockerfile')
    expect(detectLanguage('README.md')).toBe('markdown')
    expect(detectLanguage('unknown.asset')).toBe('plaintext')
  })
})

describe('file viewer tokenizer', () => {
  it('highlights JSON keys, strings and numbers', () => {
    expect(tokenizeFileLine('  "port": 3000,', 'json')).toEqual([
      { kind: 'plain', value: '  ' },
      { kind: 'property', value: '"port"' },
      { kind: 'punctuation', value: ':' },
      { kind: 'plain', value: ' ' },
      { kind: 'number', value: '3000' },
      { kind: 'punctuation', value: ',' },
    ])
  })

  it('highlights JavaScript keywords, literals and comments', () => {
    const tokens = tokenizeFileLine('const ready = true // deploy', 'javascript')
    expect(tokens).toContainEqual({ kind: 'keyword', value: 'const' })
    expect(tokens).toContainEqual({ kind: 'literal', value: 'true' })
    expect(tokens).toContainEqual({ kind: 'comment', value: '// deploy' })
  })

  it('highlights shell variables and comments', () => {
    const tokens = tokenizeFileLine('echo $HOME # where', 'shell')
    expect(tokens).toContainEqual({ kind: 'variable', value: '$HOME' })
    expect(tokens).toContainEqual({ kind: 'comment', value: '# where' })
  })

  it('highlights markup tags, attributes and strings', () => {
    const tokens = tokenizeFileLine('<a href="/docs">Docs</a>', 'html')
    expect(tokens).toContainEqual({ kind: 'tag', value: '<a' })
    expect(tokens).toContainEqual({ kind: 'attribute', value: 'href' })
    expect(tokens).toContainEqual({ kind: 'string', value: '"/docs"' })
  })

  it('highlights CSS properties and colors', () => {
    const tokens = tokenizeFileLine('color-scheme: #fff;', 'css')
    expect(tokens).toContainEqual({ kind: 'property', value: 'color-scheme' })
    expect(tokens).toContainEqual({ kind: 'number', value: '#fff' })
  })

  it('highlights markdown headings and links', () => {
    expect(tokenizeFileLine('## Deploy notes', 'markdown')).toEqual([
      { kind: 'heading', value: '## Deploy notes' },
    ])
    expect(tokenizeFileLine('[documentation](https://example.com)', 'markdown')).toEqual([
      { kind: 'link', value: '[documentation](https://example.com)' },
    ])
  })
})
