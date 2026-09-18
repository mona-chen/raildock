import type { EnvironmentDuplicateSummary } from '@/types'

/**
 * The name the duplicate dialog opens with.
 *
 * Railway pre-fills the duplicate form with a sensible sibling name rather than
 * an empty box, and the first two attempts should be the names an operator
 * actually wants: `staging`, then `development`, then a copy name.
 */
export function suggestEnvironmentName(sourceName: string, existingNames: string[]): string {
  const taken = new Set(existingNames.map((name) => name.trim().toLowerCase()))
  const slug = sourceName.trim().toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'production'

  for (const candidate of ['staging', 'development', 'test']) {
    if (!taken.has(candidate)) return candidate
  }

  let index = 1
  let candidate = `${slug}-copy`
  while (taken.has(candidate)) {
    index += 1
    candidate = `${slug}-copy-${index}`
  }
  return candidate
}

/**
 * What the duplication actually staged, as short phrases. Zero-count entries are
 * dropped so the review reads like a sentence rather than a table of zeroes.
 */
export function duplicateHighlights(summary: EnvironmentDuplicateSummary): string[] {
  const highlights: string[] = []
  const add = (count: number, singular: string, plural = `${singular}s`) => {
    if (count > 0) highlights.push(`${count} ${count === 1 ? singular : plural}`)
  }

  add(summary.services, 'service')
  add(summary.variables, 'variable')
  add(summary.volumes, 'new volume')
  add(summary.bindMounts, 'shared bind mount')
  add(summary.schedules, 'backup schedule')
  add(summary.links, 'link')
  add(summary.temporaryDomains, 'temporary domain')

  return highlights
}
