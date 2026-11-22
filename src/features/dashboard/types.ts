export type DashboardKpis = {
  today_sales: number
  month_sales: number
  month_purchases: number
  stock_value: number
  receivable: number
  payable: number
  low_stock_count: number
}

export type DailyFlowRow = {
  day: string
  sales_total: number
  purchase_total: number
}

export type TopProductRow = {
  product_id: string
  sku: string
  name: string
  qty_sold: number
  revenue: number
}

export type KpiKey =
  | 'today_sales'
  | 'month_sales'
  | 'month_purchases'
  | 'stock_value'
  | 'receivable'
  | 'payable'
  | 'low_stock_count'
