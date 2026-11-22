/** Returns the port as a number, or null when it is not a valid TCP port. */
export function parseSshPort(value: string): number | null {
  const trimmed = value.trim()
  if (!/^\d{1,5}$/.test(trimmed)) return null
  const port = Number(trimmed)
  return port >= 1 && port <= 65535 ? port : null
}
