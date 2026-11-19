import { useEffect, useRef, useState } from 'react'
import { useScaleProcess } from '@/hooks/useServices'
import ConfirmDialog from '@/features/shared/ConfirmDialog'
import type { ProcessType } from '@/types'

export default function ProcessScaling({ serviceId, process }: { serviceId: string; process: ProcessType }) {
  const scale = useScaleProcess()
  const [quantity, setQuantity] = useState(String(process.quantity))
  const [review, setReview] = useState(false)
  const [error, setError] = useState('')
  const previous = useRef(process.quantity)
  useEffect(() => {
    setQuantity((current) => current === String(previous.current) ? String(process.quantity) : current)
    previous.current = process.quantity
  }, [process.quantity])
  const target = Number(quantity)
  const valid = quantity.trim() !== '' && Number.isSafeInteger(target) && target >= 0
  const apply = () => {
    if (!valid || scale.isPending) return
    setError('')
    scale.mutate({ id: serviceId, processName: process.name, quantity: target }, {
      onSuccess: () => setReview(false),
      onError: () => setError('Could not apply scaling. Your target is retained.'),
    })
  }
  return <div className="border-b border-white/8 py-4">
    <div className="flex flex-wrap items-center justify-between gap-4">
      <div className="min-w-0"><h4 className="text-sm font-medium text-white/85">{process.name}</h4><p className="mt-1 text-xs text-[#a0a0b0]">{process.running} running · {process.quantity} requested</p>{process.command && <p className="mt-1 break-all font-mono text-xs text-[#a0a0b0]">{process.command}</p>}</div>
      <form className="flex items-end gap-2" onSubmit={(event) => { event.preventDefault(); if (!valid || target === process.quantity || scale.isPending) return; if (target === 0) setReview(true); else apply() }}>
        <label className="text-xs text-[#a0a0b0]">Replicas<input aria-label={`${process.name} replicas`} type="number" min="0" step="1" value={quantity} disabled={scale.isPending} onChange={(event) => setQuantity(event.target.value)} className="input-dark mt-1 w-24" /></label>
        <button type="submit" disabled={!valid || target === process.quantity || scale.isPending} className="btn-secondary h-9 text-xs">{scale.isPending ? 'Applying…' : 'Apply'}</button>
      </form>
    </div>
    {error && <p role="alert" className="mt-2 text-xs text-red-300">{error}</p>}
    <ConfirmDialog open={review} onOpenChange={setReview} title={`Stop all ${process.name} replicas?`} description="Setting replicas to zero stops this process. Requests or background work handled by it will stop until you scale it up again." confirmLabel="Set replicas to zero" destructive pending={scale.isPending} onConfirm={apply} />
  </div>
}
