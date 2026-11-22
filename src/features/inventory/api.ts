import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { PAGE_SIZE, pageRange } from '@/shared/lib/pagination'
import { queryKeys } from '@/shared/lib/query-keys'
import { friendlyRpcError } from '@/shared/lib/rpc-error'
import { roundMoney } from '@/features/inventory/lib/math'
import type {
  ProductSummary,
  StockLevelRow,
  StockMoveKind,
  StockMovementRow,
} from '@/features/inventory/types'

export const inventoryKeys = {
  all: queryKeys.stock,
  levels: (page: number, search: string, lowOnly: boolean) =>
    [...queryKeys.stock, 'levels', page, search, lowOnly] as const,
  product: (id: string) => [...queryKeys.stock, 'product', id] as const,
  movements: (
    productId: string,
    page: number,
    kind: '' | StockMoveKind,
  ) => [...queryKeys.stock, 'movements', productId, page, kind] as const,
}

export async function listStockLevels(params: {
  page: number
  search: string
  lowOnly: boolean
}) {
  const { from, to } = pageRange(params.page)
  let query = supabase
    .from('products')
    .select(
      'id, sku, name, unit, stock_qty, avg_cost, reorder_level, is_active',
      { count: 'exact' },
    )
    .order('sku', { ascending: true })
    .range(from, to)

  const q = params.search.trim()
  if (q) {
    query = query.or(`sku.ilike.%${q}%,name.ilike.%${q}%`)
  }

  if (params.lowOnly) {
    query = query.eq('is_low', true)
  }

  const { data, error, count } = await query
  if (error) throw new Error(friendlyRpcError(error))

  const rows: StockLevelRow[] = (data ?? []).map((row) => {
    const r = row as Record<string, unknown>
    const stock_qty = Number(r.stock_qty)
    const avg_cost = Number(r.avg_cost)
    const reorder_level = Number(r.reorder_level)
    return {
      id: String(r.id),
      sku: String(r.sku),
      name: String(r.name),
      unit: String(r.unit),
      stock_qty,
      avg_cost,
      reorder_level,
      is_active: Boolean(r.is_active),
      stock_value: roundMoney(stock_qty * avg_cost),
      is_low: stock_qty <= reorder_level,
    }
  })

  return { rows, total: count ?? 0 }
}

export async function getProductSummary(
  productId: string,
): Promise<ProductSummary> {
  const { data, error } = await supabase
    .from('products')
    .select('id, sku, name, unit, stock_qty, avg_cost')
    .eq('id', productId)
    .single()

  if (error) throw new Error(friendlyRpcError(error))
  const r = data as Record<string, unknown>
  return {
    id: String(r.id),
    sku: String(r.sku),
    name: String(r.name),
    unit: String(r.unit),
    stock_qty: Number(r.stock_qty),
    avg_cost: Number(r.avg_cost),
  }
}

export async function listMovements(params: {
  productId: string
  page: number
  kind: '' | StockMoveKind
}) {
  const { from, to } = pageRange(params.page)
  let query = supabase
    .from('stock_movements')
    .select(
      'id, kind, qty_delta, source_type, source_id, note, created_at',
      { count: 'exact' },
    )
    .eq('product_id', params.productId)
    .order('created_at', { ascending: false })
    .range(from, to)

  if (params.kind) {
    query = query.eq('kind', params.kind)
  }

  const { data, error, count } = await query
  if (error) throw new Error(friendlyRpcError(error))

  const rows: StockMovementRow[] = (data ?? []).map((row) => {
    const r = row as Record<string, unknown>
    return {
      id: String(r.id),
      kind: r.kind as StockMoveKind,
      qty_delta: Number(r.qty_delta),
      source_type: String(r.source_type),
      source_id: String(r.source_id),
      note: (r.note as string | null) ?? null,
      created_at: String(r.created_at),
    }
  })

  return { rows, total: count ?? 0 }
}

export function useStockLevelsQuery(
  page: number,
  search: string,
  lowOnly: boolean,
) {
  return useQuery({
    queryKey: inventoryKeys.levels(page, search, lowOnly),
    queryFn: () => listStockLevels({ page, search, lowOnly }),
    placeholderData: (prev) => prev,
  })
}

export function useProductSummaryQuery(productId: string | undefined) {
  return useQuery({
    queryKey: inventoryKeys.product(productId ?? ''),
    queryFn: () => getProductSummary(productId!),
    enabled: Boolean(productId),
  })
}

export function useMovementsQuery(
  productId: string | undefined,
  page: number,
  kind: '' | StockMoveKind,
) {
  return useQuery({
    queryKey: inventoryKeys.movements(productId ?? '', page, kind),
    queryFn: () =>
      listMovements({ productId: productId!, page, kind }),
    enabled: Boolean(productId),
    placeholderData: (prev) => prev,
  })
}

export { PAGE_SIZE }
