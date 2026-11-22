export type StockMoveKind =
  | 'purchase'
  | 'sale'
  | 'adjustment'
  | 'void_reversal'

export type StockLevelRow = {
  id: string
  sku: string
  name: string
  unit: string
  stock_qty: number
  avg_cost: number
  reorder_level: number
  is_active: boolean
  stock_value: number
  is_low: boolean
}

export type StockMovementRow = {
  id: string
  kind: StockMoveKind
  qty_delta: number
  source_type: string
  source_id: string
  note: string | null
  created_at: string
}

export type ProductSummary = {
  id: string
  sku: string
  name: string
  unit: string
  stock_qty: number
  avg_cost: number
}
