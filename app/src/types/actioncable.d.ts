declare module '@rails/actioncable' {
  export function createConsumer(url?: string | null): Cable

  interface Cable {
    subscriptions: Subscriptions
  }

  interface Subscriptions {
    create(channel: string | object, mixin: SubscriptionMixin): Subscription
  }

  interface SubscriptionMixin {
    connected?: () => void
    disconnected?: () => void
    received?: (data: any) => void
  }

  interface Subscription {
    unsubscribe(): void
  }
}
