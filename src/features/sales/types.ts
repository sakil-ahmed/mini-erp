export type DocStatus = 'posted' | 'void'

export type SaleListItem = {
  id: string
  doc_number: string
  doc_date: string
  status: DocStatus
  subtotal: number
  discount: number
  total: number
  amount_paid: number
  customer_id: string
  customer_name: string
}

export type SaleItem = {
  id: string
  product_id: string
  qty: number
  unit_price: number
  unit_cost: number
  line_total: number
  product_sku: string
  product_name: string
}

export type SaleDetail = SaleListItem & {
  notes: string | null
  items: SaleItem[]
  /** Revenue − COGS (qty × unit_cost snapshot). */
  cogs: number
  profit: number
}

export type SaleListFilters = {
  page: number
  dateFrom: string
  dateTo: string
  customerId: string
  status: '' | DocStatus
}

export type CustomerOption = {
  id: string
  name: string
}

export type ProductOption = {
  id: string
  sku: string
  name: string
  unit: string
  sale_price: number
  stock_qty: number
}
