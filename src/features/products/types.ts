export type Product = {
  id: string
  sku: string
  name: string
  unit: string
  sale_price: number
  avg_cost: number
  stock_qty: number
  reorder_level: number
  is_active: boolean
  created_at: string
}

export type ProductListResult = {
  rows: Product[]
  total: number
}
