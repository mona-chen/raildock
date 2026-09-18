import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import DriftPanel from '@/components/manifest/DriftPanel'
import type { ManifestDriftReport } from '@/lib/api'

const mergeMutateAsync = vi.fn()
let driftState: { data?: ManifestDriftReport; isLoading?: boolean; isError?: boolean } = {}

vi.mock('@/hooks/useManifest', () => ({
  useManifestDrift: () => ({
    data: driftState.data,
    isLoading: driftState.isLoading ?? false,
    isError: driftState.isError ?? false,
    refetch: vi.fn(),
  }),
  useManifestMerge: () => ({ mutateAsync: mergeMutateAsync, isPending: false }),
}))

function report(overrides: Partial<ManifestDriftReport> = {}): ManifestDriftReport {
  return {
    supported: true,
    format: 'raildock.toml',
    driftDetected: true,
    summary: { driftDetected: true, driftedFields: 1, missingFromManifest: 0, missingFromHost: 0, mergeableServices: 1 },
    services: [
      {
        name: 'web',
        managedBy: 'manifest',
        status: 'drifted',
        mergeable: true,
        changes: [
          { field: 'port', changeType: 'modified', severity: 'redeploy', manifestValue: 3000, liveValue: 8080 },
        ],
      },
    ],
    ...overrides,
  }
}

describe('DriftPanel', () => {
  beforeEach(() => {
    mergeMutateAsync.mockReset()
    driftState = { data: report() }
  })

  it('lists drifted fields and merges the selected service into the editor', async () => {
    mergeMutateAsync.mockResolvedValue({
      content: 'merged manifest',
      format: 'raildock.toml',
      adopted: ['web'],
      skipped: [],
    })
    const onMerge = vi.fn()

    render(<DriftPanel projectId="p1" enabled onMerge={onMerge} />)

    expect(screen.getByText('port')).toBeInTheDocument()
    expect(screen.getByText('3000')).toBeInTheDocument()
    expect(screen.getByText('8080')).toBeInTheDocument()

    fireEvent.click(screen.getByLabelText('Merge web'))
    fireEvent.click(screen.getByRole('button', { name: /merge 1 into editor/i }))

    await waitFor(() =>
      expect(onMerge).toHaveBeenCalledWith('merged manifest', expect.objectContaining({ adopted: ['web'] })),
    )
    expect(mergeMutateAsync).toHaveBeenCalledWith({ projectId: 'p1', services: ['web'] })
  })

  it('does not offer a merge when nothing has drifted', () => {
    driftState = { data: report({ driftDetected: false, services: [] }) }

    render(<DriftPanel projectId="p1" enabled onMerge={vi.fn()} />)

    expect(screen.getByText('No drift detected')).toBeInTheDocument()
  })

  it('explains that compatibility formats cannot be merged', () => {
    driftState = { data: report({ supported: false, format: 'railway.toml', services: [] }) }

    render(<DriftPanel projectId="p1" enabled onMerge={vi.fn()} />)

    expect(screen.getByText(/unavailable for railway.toml/i)).toBeInTheDocument()
  })
})
