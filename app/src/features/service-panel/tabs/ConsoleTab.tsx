import { useState, useRef, useEffect } from 'react'
import { Terminal, Play, Loader2, Copy, Check, ArrowRight, Monitor } from 'lucide-react'
import { copyToClipboard } from '@/lib/clipboard'
import { useRunOneOff } from '@/hooks/useServices'

interface ConsoleTabProps {
  serviceId: string
  serviceName: string
}

interface OutputLine {
  id: number
  type: 'command' | 'output' | 'error' | 'info'
  text: string
  timestamp: Date
}

export default function ConsoleTab({ serviceId, serviceName }: ConsoleTabProps) {
  const [command, setCommand] = useState('')
  const [history, setHistory] = useState<OutputLine[]>([])
  const [isRunning, setIsRunning] = useState(false)
  const [copied, setCopied] = useState(false)
  const outputRef = useRef<HTMLDivElement>(null)
  const runOneOff = useRunOneOff()

  const lineIdRef = useRef(0)

  const addLine = (type: OutputLine['type'], text: string) => {
    setHistory((prev) => [...prev, { id: lineIdRef.current++, type, text, timestamp: new Date() }])
  }

  useEffect(() => {
    if (outputRef.current) {
      outputRef.current.scrollTop = outputRef.current.scrollHeight
    }
  }, [history])

  const handleRun = () => {
    if (!command.trim() || isRunning) return
    const cmd = command.trim()
    setCommand('')
    setIsRunning(true)
    addLine('command', `$ ${cmd}`)

    runOneOff.mutate(
      { id: serviceId, command: cmd },
      {
        onSuccess: (data: { success: boolean; output: string }) => {
          if (data.output) {
            data.output.split('\n').forEach((line: string) => addLine('output', line))
          } else {
            addLine('info', 'Command completed successfully.')
          }
          setIsRunning(false)
        },
        onError: (err) => {
          addLine('error', `Error: ${err.message}`)
          setIsRunning(false)
        },
      }
    )
  }

  const enterCommand = `dokku enter ${serviceName}`

  const copyEnterCommand = async () => {
    const success = await copyToClipboard(enterCommand)
    if (success) {
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    }
  }

  const typeColors: Record<OutputLine['type'], string> = {
    command: 'text-[#8b5cf6]',
    output: 'text-white/70',
    error: 'text-red-400',
    info: 'text-blue-400',
  }

  return (
    <div className="flex flex-col h-full">
      {/* Enter Container */}
      <div className="px-4 py-3 border-b border-white/[0.06] bg-[#0f0f13]">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-[12px] text-white/50">Enter Container Shell</div>
            <div className="text-[11px] text-white/30 mt-0.5">Interactive shell session within the container</div>
          </div>
          <button
            onClick={copyEnterCommand}
            className="flex items-center gap-2 px-3 py-2 bg-white/[0.06] text-white/60 rounded-lg text-[12px] hover:bg-white/[0.1] transition-all"
          >
            {copied ? <Check size={13} className="text-emerald-400" /> : <Copy size={13} />}
            {copied ? 'Copied!' : 'Copy Command'}
          </button>
        </div>
        <div className="mt-2 bg-black/30 rounded-lg p-2.5 font-mono text-[12px] text-white/40 flex items-center gap-2">
          <Monitor size={13} className="text-white/30 shrink-0" />
          <span className="text-white/60">{enterCommand}</span>
        </div>
      </div>

      {/* Command Input */}
      <div className="px-4 py-3 border-b border-white/[0.06] bg-[#131318]">
        <div className="flex gap-2">
          <div className="flex-1 flex items-center gap-2 bg-black/30 border border-white/[0.08] rounded-lg px-3 py-2">
            <span className="text-[#8b5cf6] font-mono text-[13px]">$</span>
            <input
              type="text"
              value={command}
              onChange={(e) => setCommand(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleRun()}
              placeholder="Enter one-off command (e.g., ls -la, rails c, ps aux)"
              className="flex-1 bg-transparent text-[12px] text-white/70 font-mono placeholder:text-white/20 focus:outline-none"
              disabled={isRunning}
            />
          </div>
          <button
            onClick={handleRun}
            disabled={!command.trim() || isRunning}
            className="flex items-center gap-1.5 px-4 py-2 bg-[#8b5cf6]/15 text-[#8b5cf6] rounded-lg text-[12px] font-medium hover:bg-[#8b5cf6]/25 transition-all disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {isRunning ? (
              <>
                <Loader2 size={13} className="animate-spin" />
                Running...
              </>
            ) : (
              <>
                <Play size={13} />
                Run
              </>
            )}
          </button>
        </div>
      </div>

      {/* Output */}
      <div
        ref={outputRef}
        className="flex-1 overflow-y-auto p-4 font-mono text-[12px] bg-[#0a0a0c]"
      >
        {history.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-white/20">
            <Terminal size={32} className="mb-3 opacity-30" />
            <p className="text-[13px]">Run a command to see output here</p>
          </div>
        ) : (
          <div className="space-y-0.5">
            {history.map((line) => (
              <div key={line.id} className={`flex items-start gap-2 ${typeColors[line.type]}`}>
                {line.type === 'command' && (
                  <span className="text-[10px] text-white/20 mt-0.5 shrink-0">
                    {line.timestamp.toLocaleTimeString('en-US', { hour12: false })}
                  </span>
                )}
                <span className={line.type === 'command' ? 'font-semibold' : ''}>
                  {line.text}
                </span>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}