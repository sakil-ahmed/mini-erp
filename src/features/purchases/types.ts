export type DocStatus = 'posted' | 'void'

export type PurchaseListItem = {
  id: string
  doc_number: string
  doc_date: string
  status: DocStatus
  subtotal: number
  discount: number
  total: number
  amount_paid: number
  supplier_id: string
  supplier_name: string
}

export type PurchaseItem = {
  id: string
  product_id: string
  qty: number
  unit_cost: number
  line_total: number
  product_sku: string
  product_name: string
}

export type PurchaseDetail = PurchaseListItem & {
  notes: string | null
  items: PurchaseItem[]
}

export type PurchaseListFilters = {
  page: number
  dateFrom: string
  dateTo: string
  supplierId: string
  status: '' | DocStatus
}

export type SupplierOption = {
  id: string
  name: string
}

export type ProductOption = {
  id: string
  sku: string
  name: string
  unit: string
  avg_cost: number
}
