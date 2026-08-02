import { useState } from 'react'
import { Table2, RefreshCw, ChevronLeft, ChevronRight, Database } from 'lucide-react'
import { useDataTables, useDataTableRows } from '@/hooks/useServices'
import { Table, TableHeader, TableBody, TableHead, TableRow, TableCell } from '@/components/ui/table'
import { Skeleton } from '@/components/ui/skeleton'

const PAGE_SIZE = 50

function formatCell(value: unknown): string {
  if (value === null || value === undefined) return 'NULL'
  if (typeof value === 'object') return JSON.stringify(value)
  if (typeof value === 'boolean') return String(value)
  return String(value)
}

function CellValue({ value }: { value: unknown }) {
  if (value === null || value === undefined) {
    return <span className="text-white/25 italic">NULL</span>
  }
  const text = formatCell(value)
  return (
    <span className="inline-block max-w-[280px] truncate align-bottom font-mono text-[12px] text-white/80" title={text}>
      {text}
    </span>
  )
}

export default function DataTab({ serviceId }: { serviceId: string }) {
  const [table, setTable] = useState<string | null>(null)
  const [offset, setOffset] = useState(0)

  const { data: tablesData, isLoading: tablesLoading, error: tablesError, refetch: refetchTables, isFetching: tablesFetching } = useDataTables(serviceId)
  const { data: rowsData, isLoading: rowsLoading, error: rowsError } = useDataTableRows(serviceId, table, PAGE_SIZE, offset)

  const tables = tablesData?.tables ?? []
  const columns = rowsData?.columns ?? []
  const rows = rowsData?.rows ?? []

  const selectTable = (name: string) => {
    setTable(name)
    setOffset(0)
  }

  return (
    <div className="flex h-full">
      {/* Table sidebar */}
      <div className="w-[220px] flex-shrink-0 border-r border-white/[0.06] flex flex-col">
        <div className="flex items-center justify-between px-3 py-2.5 border-b border-white/[0.06]">
          <div className="text-[11px] font-medium text-white/50 uppercase tracking-wider flex items-center gap-1.5">
            <Database size={12} className="text-white/40" />
            Tables
          </div>
          <button
            type="button"
            onClick={() => refetchTables()}
            disabled={tablesFetching}
            className="text-white/30 hover:text-white/60 transition-colors disabled:opacity-50"
            title="Refresh"
          >
            <RefreshCw size={12} className={tablesFetching ? 'animate-spin' : ''} />
          </button>
        </div>
        <div className="flex-1 overflow-y-auto py-1">
          {tablesLoading ? (
            <div className="space-y-1 px-2 pt-1">
              {Array.from({ length: 8 }).map((_, i) => (
                <Skeleton key={i} className="h-7 w-full rounded-md" />
              ))}
            </div>
          ) : tablesError ? (
            <div className="px-3 py-3 text-[12px] text-red-400/80 leading-relaxed">
              {tablesData?.error || 'Failed to load tables'}
            </div>
          ) : tables.length === 0 ? (
            <div className="px-3 py-3 text-[12px] text-white/30">No tables found</div>
          ) : (
            tables.map((t) => (
              <button
                key={t.name}
                type="button"
                onClick={() => selectTable(t.name)}
                className={`w-full flex items-center gap-2 px-3 py-1.5 text-left text-[12.5px] transition-colors ${
                  table === t.name ? 'bg-[#8b5cf6]/10 text-[#a78bfa]' : 'text-white/60 hover:bg-white/[0.04] hover:text-white/80'
                }`}
              >
                <Table2 size={13} className="flex-shrink-0 opacity-60" />
                <span className="truncate">{t.name}</span>
              </button>
            ))
          )}
        </div>
      </div>

      {/* Data grid */}
      <div className="flex-1 flex flex-col min-w-0">
        {!table ? (
          <div className="flex-1 flex flex-col items-center justify-center p-8 text-center">
            <Table2 size={22} className="text-white/20 mb-3" />
            <p className="text-[13px] text-white/40">Select a table to preview its data</p>
            <p className="text-[12px] text-white/25 mt-1">Read-only view, up to {PAGE_SIZE} rows per page</p>
          </div>
        ) : rowsLoading ? (
          <div className="flex-1 p-4 space-y-2">
            <Skeleton className="h-8 w-56" />
            <div className="space-y-1.5">
              {Array.from({ length: 6 }).map((_, i) => (
                <Skeleton key={i} className="h-8 w-full" />
              ))}
            </div>
          </div>
        ) : rowsError || !rowsData?.success ? (
          <div className="flex-1 flex flex-col items-center justify-center p-8 text-center">
            <p className="text-[13px] text-red-400/80">{rowsData?.error || 'Failed to load rows'}</p>
          </div>
        ) : (
          <>
            <div className="flex items-center justify-between px-4 py-2.5 border-b border-white/[0.06] flex-shrink-0">
              <div className="text-[13px] font-medium text-white/80 truncate">
                {table}
                {tablesData?.type && <span className="ml-2 text-[11px] font-normal text-white/35">{tablesData.type}</span>}
              </div>
              <div className="flex items-center gap-1">
                <button
                  type="button"
                  disabled={offset === 0}
                  onClick={() => setOffset((o) => Math.max(0, o - PAGE_SIZE))}
                  className="flex items-center gap-0.5 px-2 py-1 rounded-md text-[11px] text-white/50 hover:text-white/80 hover:bg-white/[0.05] disabled:opacity-30 disabled:hover:bg-transparent disabled:hover:text-white/50 transition-colors"
                >
                  <ChevronLeft size={13} />
                  Prev
                </button>
                <span className="text-[11px] text-white/35 px-1.5 tabular-nums">
                  {offset + 1}–{offset + rows.length}
                </span>
                <button
                  type="button"
                  disabled={!rowsData.has_more}
                  onClick={() => setOffset((o) => o + PAGE_SIZE)}
                  className="flex items-center gap-0.5 px-2 py-1 rounded-md text-[11px] text-white/50 hover:text-white/80 hover:bg-white/[0.05] disabled:opacity-30 disabled:hover:bg-transparent disabled:hover:text-white/50 transition-colors"
                >
                  Next
                  <ChevronRight size={13} />
                </button>
              </div>
            </div>
            <div className="flex-1 overflow-auto">
              {rows.length === 0 ? (
                <div className="flex-1 flex flex-col items-center justify-center p-8 text-center">
                  <p className="text-[13px] text-white/40">No rows in this table</p>
                </div>
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      {columns.map((c) => (
                        <TableHead key={c.name} className="px-3 py-2 text-[11px] font-medium text-white/50 whitespace-nowrap">
                          <div className="flex items-center gap-1.5">
                            <span>{c.name}</span>
                            <span className="text-[10px] text-white/25 font-normal">{c.type}</span>
                          </div>
                        </TableHead>
                      ))}
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {rows.map((row, i) => (
                      <TableRow key={i} className="hover:bg-white/[0.02]">
                        {columns.map((c) => (
                          <TableCell key={c.name} className="px-3 py-1.5">
                            <CellValue value={row[c.name]} />
                          </TableCell>
                        ))}
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </div>
          </>
        )}
      </div>
    </div>
  )
}
