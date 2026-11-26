export type FileLanguage =
  | 'json'
  | 'javascript'
  | 'typescript'
  | 'yaml'
  | 'html'
  | 'xml'
  | 'css'
  | 'markdown'
  | 'shell'
  | 'dockerfile'
  | 'ruby'
  | 'python'
  | 'sql'
  | 'toml'
  | 'go'
  | 'rust'
  | 'java'
  | 'php'
  | 'plaintext'

export type TokenKind =
  | 'plain'
  | 'comment'
  | 'string'
  | 'number'
  | 'keyword'
  | 'literal'
  | 'function'
  | 'type'
  | 'property'
  | 'tag'
  | 'attribute'
  | 'operator'
  | 'punctuation'
  | 'heading'
  | 'link'
  | 'variable'

export interface Token {
  kind: TokenKind
  value: string
}

export const LANGUAGE_LABELS: Record<FileLanguage, string> = {
  json: 'JSON',
  javascript: 'JavaScript',
  typescript: 'TypeScript',
  yaml: 'YAML',
  html: 'HTML',
  xml: 'XML',
  css: 'CSS',
  markdown: 'Markdown',
  shell: 'Shell',
  dockerfile: 'Dockerfile',
  ruby: 'Ruby',
  python: 'Python',
  sql: 'SQL',
  toml: 'TOML',
  go: 'Go',
  rust: 'Rust',
  java: 'Java',
  php: 'PHP',
  plaintext: 'Plain text',
}

export function detectLanguage(filename: string): FileLanguage {
  const name = filename.split('/').pop()?.toLowerCase() || ''
  if (name === 'dockerfile' || name.startsWith('dockerfile.')) return 'dockerfile'
  if (name === 'makefile' || name === '.env' || name.startsWith('.env.')) return 'shell'
  if (name === 'gemfile' || name === 'rakefile') return 'ruby'

  const extension = name.includes('.') ? name.split('.').pop() || '' : ''
  switch (extension) {
    case 'json':
    case 'jsonc':
    case 'json5':
      return 'json'
    case 'js':
    case 'jsx':
    case 'mjs':
    case 'cjs':
      return 'javascript'
    case 'ts':
    case 'tsx':
    case 'mts':
    case 'cts':
      return 'typescript'
    case 'yml':
    case 'yaml':
      return 'yaml'
    case 'html':
    case 'htm':
    case 'xhtml':
    case 'vue':
    case 'svelte':
      return 'html'
    case 'xml':
    case 'svg':
      return 'xml'
    case 'css':
    case 'scss':
    case 'sass':
    case 'less':
      return 'css'
    case 'md':
    case 'mdx':
      return 'markdown'
    case 'sh':
    case 'bash':
    case 'zsh':
    case 'fish':
      return 'shell'
    case 'rb':
    case 'rake':
    case 'gemspec':
      return 'ruby'
    case 'py':
      return 'python'
    case 'sql':
      return 'sql'
    case 'toml':
    case 'ini':
    case 'cfg':
    case 'conf':
      return 'toml'
    case 'go':
      return 'go'
    case 'rs':
      return 'rust'
    case 'java':
    case 'kt':
    case 'kts':
      return 'java'
    case 'php':
      return 'php'
    default:
      return 'plaintext'
  }
}

interface CodeConfig {
  lineComments: string[]
  blockComments?: boolean
  keywords: Set<string>
  literals: Set<string>
  variables?: boolean
  backticks?: boolean
  propertyColon?: boolean
  selectorBrace?: boolean
  hexColors?: boolean
  hyphenatedWords?: boolean
}

const words = (...values: string[]) => new Set(values)
const LITERALS = words('true', 'false', 'null', 'undefined', 'nil', 'none')
const JS_KEYWORDS = words(
  'const', 'let', 'var', 'function', 'return', 'if', 'else', 'for', 'while', 'switch', 'case', 'break', 'continue',
  'class', 'extends', 'new', 'import', 'from', 'export', 'default', 'async', 'await', 'try', 'catch', 'finally',
  'throw', 'typeof', 'instanceof', 'in', 'of', 'this', 'super', 'static', 'get', 'set', 'interface', 'type', 'enum',
  'implements', 'public', 'private', 'protected', 'readonly', 'as', 'delete', 'void', 'yield', 'constructor'
)
const RUBY_KEYWORDS = words(
  'def', 'class', 'module', 'end', 'if', 'elsif', 'else', 'unless', 'while', 'until', 'for', 'in', 'do', 'begin',
  'rescue', 'ensure', 'yield', 'return', 'require', 'require_relative', 'attr_reader', 'attr_writer', 'attr_accessor',
  'self', 'then', 'case', 'when', 'new', 'raise', 'puts', 'private', 'protected', 'public'
)
const PYTHON_KEYWORDS = words(
  'def', 'class', 'return', 'if', 'elif', 'else', 'for', 'while', 'import', 'from', 'as', 'try', 'except', 'finally',
  'with', 'lambda', 'yield', 'async', 'await', 'pass', 'break', 'continue', 'and', 'or', 'not', 'in', 'is', 'self'
)
const GO_KEYWORDS = words(
  'package', 'import', 'func', 'return', 'if', 'else', 'for', 'range', 'var', 'const', 'type', 'struct', 'interface',
  'map', 'chan', 'go', 'defer', 'select', 'switch', 'case', 'default', 'break', 'continue', 'fallthrough'
)
const RUST_KEYWORDS = words(
  'fn', 'let', 'mut', 'pub', 'use', 'mod', 'struct', 'enum', 'impl', 'trait', 'for', 'while', 'loop', 'if', 'else',
  'match', 'return', 'self', 'async', 'await', 'move', 'ref', 'where', 'crate', 'const', 'static', 'unsafe'
)
const JAVA_KEYWORDS = words(
  'public', 'private', 'protected', 'class', 'interface', 'enum', 'extends', 'implements', 'static', 'final', 'void',
  'new', 'return', 'if', 'else', 'for', 'while', 'switch', 'case', 'break', 'continue', 'try', 'catch', 'finally',
  'throw', 'throws', 'package', 'import', 'this', 'super', 'fun', 'val', 'var', 'object', 'when', 'data'
)
const PHP_KEYWORDS = words(
  'function', 'class', 'interface', 'trait', 'extends', 'implements', 'public', 'private', 'protected', 'static',
  'return', 'if', 'else', 'elseif', 'foreach', 'for', 'while', 'switch', 'case', 'break', 'continue', 'try', 'catch',
  'finally', 'throw', 'new', 'use', 'namespace', 'echo', 'require', 'include', 'true', 'false', 'null'
)
const SHELL_KEYWORDS = words(
  'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'do', 'done', 'case', 'esac', 'function', 'in', 'return', 'exit',
  'export', 'local', 'readonly', 'source', 'alias', 'set', 'unset', 'shift', 'trap'
)
const DOCKER_KEYWORDS = words(
  'from', 'run', 'cmd', 'label', 'expose', 'env', 'add', 'copy', 'entrypoint', 'volume', 'user', 'workdir', 'arg',
  'onbuild', 'stopsignal', 'healthcheck', 'shell', 'maintainer'
)
const SQL_KEYWORDS = words(
  'select', 'from', 'where', 'join', 'left', 'right', 'inner', 'outer', 'on', 'insert', 'into', 'values', 'update',
  'set', 'delete', 'create', 'table', 'alter', 'drop', 'group', 'order', 'by', 'limit', 'offset', 'having', 'as', 'and',
  'or', 'not', 'distinct', 'count', 'sum', 'avg', 'min', 'max', 'case', 'when', 'then', 'else', 'end', 'union', 'all',
  'exists', 'primary', 'key', 'foreign', 'references', 'index', 'view', 'with', 'returning'
)
const CSS_KEYWORDS = words(
  'important', 'media', 'supports', 'keyframes', 'font-face', 'import', 'charset', 'layer', 'container', 'from', 'to'
)

const CODE_CONFIG: Partial<Record<FileLanguage, CodeConfig>> = {
  javascript: { lineComments: [ '//' ], blockComments: true, keywords: JS_KEYWORDS, literals: LITERALS, backticks: true, propertyColon: true },
  typescript: { lineComments: [ '//' ], blockComments: true, keywords: JS_KEYWORDS, literals: LITERALS, backticks: true, propertyColon: true },
  ruby: { lineComments: [ '#' ], keywords: RUBY_KEYWORDS, literals: LITERALS, propertyColon: true },
  python: { lineComments: [ '#' ], keywords: PYTHON_KEYWORDS, literals: LITERALS, propertyColon: true },
  go: { lineComments: [ '//' ], blockComments: true, keywords: GO_KEYWORDS, literals: LITERALS, backticks: true },
  rust: { lineComments: [ '//' ], blockComments: true, keywords: RUST_KEYWORDS, literals: LITERALS },
  java: { lineComments: [ '//' ], blockComments: true, keywords: JAVA_KEYWORDS, literals: LITERALS },
  php: { lineComments: [ '//', '#' ], blockComments: true, keywords: PHP_KEYWORDS, literals: LITERALS, variables: true },
  shell: { lineComments: [ '#' ], keywords: SHELL_KEYWORDS, literals: LITERALS, variables: true, backticks: true },
  dockerfile: { lineComments: [ '#' ], keywords: DOCKER_KEYWORDS, literals: LITERALS, variables: true },
  sql: { lineComments: [ '--' ], blockComments: true, keywords: SQL_KEYWORDS, literals: LITERALS },
  toml: { lineComments: [ '#' ], keywords: words(), literals: LITERALS },
  yaml: { lineComments: [ '#' ], keywords: words(), literals: LITERALS },
  css: { lineComments: [], blockComments: true, keywords: CSS_KEYWORDS, literals: LITERALS, propertyColon: true, selectorBrace: true, hexColors: true, hyphenatedWords: true },
}

function readQuoted(value: string, quote: string) {
  let index = 1
  while (index < value.length) {
    if (value[index] === '\\') {
      index += 2
      continue
    }
    if (value[index] === quote) return value.slice(0, index + 1)
    index += 1
  }
  return value
}

function tokenizeCode(line: string, language: FileLanguage): Token[] {
  const config = CODE_CONFIG[language]
  if (!config) return [ { kind: 'plain', value: line } ]

  const tokens: Token[] = []
  let rest = line
  const push = (kind: TokenKind, value: string) => {
    tokens.push({ kind, value })
    rest = rest.slice(value.length)
  }

  while (rest) {
    const whitespace = rest.match(/^\s+/)
    if (whitespace) {
      push('plain', whitespace[0])
      continue
    }

    const comment = config.lineComments.find((marker) => rest.startsWith(marker))
    if (comment) {
      push('comment', rest)
      break
    }

    if (config.blockComments && rest.startsWith('/*')) {
      const end = rest.indexOf('*/', 2)
      push('comment', end >= 0 ? rest.slice(0, end + 2) : rest)
      continue
    }

    const quote = rest[0]
    if (quote === '"' || quote === "'" || (quote === '`' && config.backticks)) {
      push('string', readQuoted(rest, quote))
      continue
    }

    if (config.variables && quote === '$') {
      const variable = rest.match(/^\$\{[^}]*\}|^\$[A-Za-z_][A-Za-z0-9_]*/)
      if (variable) {
        push('variable', variable[0])
        continue
      }
    }

    if (config.hexColors && quote === '#' && /^#[0-9a-f]{3,8}\b/i.test(rest)) {
      push('number', rest.match(/^#[0-9a-f]{3,8}/i)?.[0] || '#')
      continue
    }

    if (quote === '@') {
      const atRule = rest.match(/^@[A-Za-z-]+/)
      if (atRule) {
        push('keyword', atRule[0])
        continue
      }
    }

    const number = rest.match(/^(?:0x[\da-f]+|0b[01]+|0o[0-7]+|\d+(?:\.\d+)?(?:e[-+]?\d+)?)/i)
    if (number) {
      push('number', number[0])
      continue
    }

    const word = rest.match(config.hyphenatedWords ? /^[A-Za-z_][A-Za-z0-9_-]*/ : /^[A-Za-z_][A-Za-z0-9_]*/)
    if (word) {
      const value = word[0]
      const after = rest.slice(value.length)
      if (config.keywords.has(value.toLowerCase())) push('keyword', value)
      else if (config.literals.has(value.toLowerCase())) push('literal', value)
      else if (config.propertyColon && /^\s*:/.test(after)) push('property', value)
      else if (config.selectorBrace && /^\s*\{/.test(after)) push('tag', value)
      else if (/^\s*\(/.test(after)) push('function', value)
      else if (/^[A-Z]/.test(value)) push('type', value)
      else push('plain', value)
      continue
    }

    const operator = rest.match(/^(?:=>|===|!==|==|!=|<=|>=|&&|\|\||\+\+|--|\+=|-=|\*=|\/=|[-+*/%=!<>&|^~?:]+)/)
    if (operator) {
      push('operator', operator[0])
      continue
    }

    if ('[]{}();,.'.includes(quote)) {
      push('punctuation', quote)
      continue
    }

    push('plain', quote)
  }

  return tokens
}

function tokenizeJson(line: string): Token[] {
  const tokens: Token[] = []
  let rest = line
  const push = (kind: TokenKind, value: string) => {
    tokens.push({ kind, value })
    rest = rest.slice(value.length)
  }

  while (rest) {
    const whitespace = rest.match(/^\s+/)
    if (whitespace) {
      push('plain', whitespace[0])
      continue
    }
    if (rest.startsWith('//')) {
      push('comment', rest)
      break
    }
    if (rest[0] === '"') {
      const value = readQuoted(rest, '"')
      push(/^\s*:/.test(rest.slice(value.length)) ? 'property' : 'string', value)
      continue
    }
    const number = rest.match(/^-?\d+(?:\.\d+)?(?:e[-+]?\d+)?/i)
    if (number) {
      push('number', number[0])
      continue
    }
    const literal = rest.match(/^(?:true|false|null)\b/)
    if (literal) {
      push('literal', literal[0])
      continue
    }
    push('[]{}();,.:'.includes(rest[0]) ? 'punctuation' : 'plain', rest[0])
  }

  return tokens
}

function tokenizeYaml(line: string): Token[] {
  if (/^\s*#/.test(line)) return [ { kind: 'comment', value: line } ]
  const key = line.match(/^(\s*(?:-\s+)?)([\w./-]+)(\s*:)(.*)$/)
  if (key) {
    return [
      { kind: 'plain', value: key[1] },
      { kind: 'property', value: key[2] },
      { kind: 'punctuation', value: key[3] },
      ...tokenizeCode(key[4], 'yaml'),
    ]
  }
  return tokenizeCode(line, 'yaml')
}

function tokenizeToml(line: string): Token[] {
  if (/^\s*#/.test(line)) return [ { kind: 'comment', value: line } ]
  const table = line.match(/^(\s*)(\[\[?[^\]]+\]?\])(\s*)(#.*)?$/)
  if (table) {
    return [
      { kind: 'plain', value: table[1] },
      { kind: 'type', value: table[2] },
      { kind: 'plain', value: table[3] },
      ...(table[4] ? [ { kind: 'comment' as const, value: table[4] } ] : []),
    ]
  }
  const assignment = line.match(/^(\s*)([\w.-]+)(\s*=\s*)(.*)$/)
  if (assignment) {
    return [
      { kind: 'plain', value: assignment[1] },
      { kind: 'property', value: assignment[2] },
      { kind: 'operator', value: assignment[3] },
      ...tokenizeCode(assignment[4], 'toml'),
    ]
  }
  return tokenizeCode(line, 'toml')
}

function tokenizeMarkup(line: string): Token[] {
  const tokens: Token[] = []
  let rest = line
  let inTag = false
  const push = (kind: TokenKind, value: string) => {
    tokens.push({ kind, value })
    rest = rest.slice(value.length)
  }

  while (rest) {
    if (rest.startsWith('<!--')) {
      const end = rest.indexOf('-->', 4)
      push('comment', end >= 0 ? rest.slice(0, end + 3) : rest)
      continue
    }
    if (rest.startsWith('<!')) {
      const declaration = rest.match(/^<![^>]*>/)
      if (declaration) {
        push('keyword', declaration[0])
        continue
      }
    }
    if (!inTag) {
      const tag = rest.match(/^<\/?(?:[A-Za-z][\w:-]*|\?[\w-]+)/)
      if (tag) {
        push('tag', tag[0])
        inTag = true
        continue
      }
      const text = rest.match(/^[^<]+/)
      push('plain', text ? text[0] : rest[0])
      continue
    }
    const whitespace = rest.match(/^\s+/)
    if (whitespace) {
      push('plain', whitespace[0])
      continue
    }
    if (rest[0] === '>') {
      push('punctuation', '>')
      inTag = false
      continue
    }
    if (rest[0] === '/' && rest[1] === '>') {
      push('punctuation', '/>')
      inTag = false
      continue
    }
    if (rest[0] === '"' || rest[0] === "'") {
      push('string', readQuoted(rest, rest[0]))
      continue
    }
    if (rest[0] === '=') {
      push('operator', '=')
      continue
    }
    const attribute = rest.match(/^[A-Za-z_:][\w:.-]*/)
    if (attribute) {
      push('attribute', attribute[0])
      continue
    }
    push('punctuation', rest[0])
  }

  return tokens
}

function tokenizeMarkdown(line: string): Token[] {
  if (/^\s*#{1,6}\s/.test(line)) return [ { kind: 'heading', value: line } ]
  if (/^\s*(?:```|~~~)/.test(line)) return [ { kind: 'string', value: line } ]
  if (/^\s*>\s?/.test(line)) return [ { kind: 'comment', value: line } ]

  const list = line.match(/^(\s*(?:[-*+]|\d+\.)\s)(.*)$/)
  if (list) {
    return [ { kind: 'punctuation', value: list[1] }, ...tokenizeInline(list[2]) ]
  }
  return tokenizeInline(line)
}

function tokenizeInline(line: string): Token[] {
  const tokens: Token[] = []
  let rest = line
  const push = (kind: TokenKind, value: string) => {
    tokens.push({ kind, value })
    rest = rest.slice(value.length)
  }

  while (rest) {
    const code = rest.match(/^`[^`]*`/)
    if (code) {
      push('string', code[0])
      continue
    }
    const link = rest.match(/^!?\[[^\]]*\]\([^)]+\)/)
    if (link) {
      push('link', link[0])
      continue
    }
    const strong = rest.match(/^(?:\*\*|__).*?(?:\*\*|__)/)
    if (strong) {
      push('keyword', strong[0])
      continue
    }
    const emphasis = rest.match(/^(?:\*|_)[^*_]+(?:\*|_)/)
    if (emphasis) {
      push('type', emphasis[0])
      continue
    }
    const url = rest.match(/^https?:\/\/\S+/)
    if (url) {
      push('link', url[0])
      continue
    }
    const plain = rest.match(/^[^`[*_]+/)
    push('plain', plain ? plain[0] : rest[0])
  }

  return tokens
}

export function tokenizeFileLine(line: string, language: FileLanguage): Token[] {
  switch (language) {
    case 'json':
      return tokenizeJson(line)
    case 'yaml':
      return tokenizeYaml(line)
    case 'toml':
      return tokenizeToml(line)
    case 'html':
    case 'xml':
      return tokenizeMarkup(line)
    case 'css':
      return tokenizeCode(line, 'css')
    case 'markdown':
      return tokenizeMarkdown(line)
    case 'plaintext':
      return [ { kind: 'plain', value: line } ]
    default:
      return tokenizeCode(line, language)
  }
}
