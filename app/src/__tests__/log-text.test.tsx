import { render, screen } from '@testing-library/react'
import { expect, it } from 'vitest'
import LogText, { stripLogFormatting } from '@/features/shared/LogText'

it('preserves terminal color without inserting HTML', () => {
  const { container } = render(<LogText text={'\x1b[31mERROR\x1b[0m <img src=x onerror=alert(1)>'} />)
  expect(screen.getByText('ERROR')).toHaveStyle({ color: '#f87171' })
  expect(container.querySelector('img')).toBeNull()
  expect(container.textContent).toContain('<img src=x onerror=alert(1)>')
})
it('colors BuildKit steps and completed steps consistently', () => {
  const { rerender } = render(<LogText text="#1 [internal] load build definition" />)
  expect(screen.getByText(/load build/)).toHaveStyle({ color: '#93c5fd' })
  rerender(<LogText text="#1 DONE 0.2s" />)
  expect(screen.getByText(/DONE/)).toHaveStyle({ color: '#86efac' })
})
it('strips terminal controls from searched and exported text', () => {
  expect(stripLogFormatting('\x1b[32mhello\x1b[0m')).toBe('hello')
})
