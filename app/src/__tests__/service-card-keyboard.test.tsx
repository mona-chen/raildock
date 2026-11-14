import { fireEvent, render, screen } from '@testing-library/react'
import { expect, it, vi } from 'vitest'
import ServiceCard from '@/features/project-canvas/components/ServiceCard'
import type { Service } from '@/types'

it('opens a service with Enter or Space without starting a mouse drag', () => {
  const activate = vi.fn()
  const drag = vi.fn()
  const service = { id: '1', name: 'api', type: 'app', subtype: 'web', status: 'running', linkedServiceIds: [] } as unknown as Service
  render(<ServiceCard service={service} position={{ x: 0, y: 0 }} isSelected={false} onActivate={activate} onMouseDown={drag} />)
  const card = screen.getByRole('button', { name: 'api app — running' })
  fireEvent.keyDown(card, { key: 'Enter' })
  fireEvent.keyDown(card, { key: ' ' })
  expect(activate).toHaveBeenCalledTimes(2)
  expect(drag).not.toHaveBeenCalled()
})
