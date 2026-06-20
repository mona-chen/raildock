import { createConsumer } from '@rails/actioncable'

function getToken(): string | null {
  try {
    const raw = localStorage.getItem('raildock-auth')
    if (!raw) return null
    const parsed = JSON.parse(raw)
    return parsed?.state?.token || null
  } catch {
    return null
  }
}

function getCableUrl(): string {
  let base: string
  if (import.meta.env.VITE_API_BASE_URL) {
    base = `${import.meta.env.VITE_API_BASE_URL.replace(/^http/, 'ws')}/cable`
  } else {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    base = `${protocol}//${window.location.host}/cable`
  }
  const token = getToken()
  return token ? `${base}?token=${encodeURIComponent(token)}` : base
}

let consumer: ReturnType<typeof createConsumer> | null = null
let consumerToken: string | null = null

export function getCable() {
  const token = getToken()
  if (!consumer || consumerToken !== token) {
    consumer?.disconnect()
    consumer = createConsumer(getCableUrl())
    consumerToken = token
  }
  return consumer
}

/** Disconnect and clear the cached consumer so the next call creates a fresh one */
export function reconnectCable() {
  if (consumer) {
    consumer.disconnect()
    consumer = null
    consumerToken = null
  }
  return getCable()
}

export function isCableAvailable() {
  return !!getToken()
}

// Legacy export for direct access
export const cable = { get subscriptions() { return getCable().subscriptions } }
