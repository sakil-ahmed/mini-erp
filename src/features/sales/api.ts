import {
  useMutation,
  useQuery,
  useQueryClient,
} from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { PAGE_SIZE, pageRange } from '@/shared/lib/pagination'
import { queryKeys } from '@/shared/lib/query-keys'
import { friendlyRpcError } from '@/shared/lib/rpc-error'
import { roundMoney, type SaleFormValues } from '@/features/sales/schemas'
import type {
  CustomerOption,
  ProductOption,
  SaleDetail,
  SaleListFilters,
  SaleListItem,
} from '@/features/sales/types'

export const saleKeys = {
  all: queryKeys.sales,
  list: (filters: SaleListFilters) =>
    [...queryKeys.sales, 'list', filters] as const,
  detail: (id: string) => [...queryKeys.sales, 'detail', id] as const,
  customers: [...queryKeys.sales, 'customers'] as const,
  productSearch: (q: string) =>
    [...queryKeys.sales, 'product-search', q] as const,
}

function mapListRow(row: Record<string, unknown>): SaleListItem {
  const customer = row.customer as Record<string, unknown> | null
  return {
    id: String(row.id),
    doc_number: String(row.doc_number),
    doc_date: String(row.doc_date),
    status: row.status as SaleListItem['status'],
    subtotal: Number(row.subtotal),
    discount: Number(row.discount ?? 0),
    total: Number(row.total),
    amount_paid: Number(row.amount_paid ?? 0),
    customer_id: String(row.customer_id),
    customer_name: customer ? String(customer.name) : '—',
  }
}

export async function listSales(filters: SaleListFilters) {
  const { from, to } = pageRange(filters.page)
  let query = supabase
    .from('sales')
    .select(
      'id, doc_number, doc_date, status, subtotal, discount, total, amount_paid, customer_id, customer:parties!sales_customer_id_fkey(id, name)',
      { count: 'exact' },
    )
    .order('doc_date', { ascending: false })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (filters.dateFrom) query = query.gte('doc_date', filters.dateFrom)
  if (filters.dateTo) query = query.lte('doc_date', filters.dateTo)
  if (filters.customerId) query = query.eq('customer_id', filters.customerId)
  if (filters.status) query = query.eq('status', filters.status)

  const { data, error, count } = await query
  if (error) throw new Error(friendlyRpcError(error))

  return {
    rows: (data ?? []).map((row) =>
      mapListRow(row as Record<string, unknown>),
    ),
    total: count ?? 0,
  }
}

export async function getSale(id: string): Promise<SaleDetail> {
  const { data, error } = await supabase
    .from('sales')
    .select(
      `
      id, doc_number, doc_date, status, subtotal, discount, total, amount_paid, customer_id, notes,
      customer:parties!sales_customer_id_fkey(id, name),
      sale_items(
        id, product_id, qty, unit_price, unit_cost, line_total,
        product:products(id, sku, name)
      )
    `,
    )
    .eq('id', id)
    .single()

  if (error) throw new Error(friendlyRpcError(error))

  const row = data as Record<string, unknown>
  const base = mapListRow(row)
  const itemsRaw = (row.sale_items as Record<string, unknown>[] | null) ?? []

  const items = itemsRaw.map((item) => {
    const product = item.product as Record<string, unknown> | null
    return {
      id: String(item.id),
      product_id: String(item.product_id),
      qty: Number(item.qty),
      unit_price: Number(item.unit_price),
      unit_cost: Number(item.unit_cost),
      line_total: Number(item.line_total),
      product_sku: product ? String(product.sku) : '—',
      product_name: product ? String(product.name) : '—',
    }
  })

  const cogs = roundMoney(
    items.reduce((sum, line) => sum + roundMoney(line.qty * line.unit_cost), 0),
  )
  const profit = roundMoney(base.total - cogs)

  return {
    ...base,
    notes: (row.notes as string | null) ?? null,
    items,
    cogs,
    profit,
  }
}

export async function listActiveCustomers(): Promise<CustomerOption[]> {
  const { data, error } = await supabase
    .from('parties')
    .select('id, name')
    .eq('kind', 'customer')
    .eq('is_active', true)
    .order('name')

  if (error) throw new Error(friendlyRpcError(error))
  return (data ?? []).map((row) => ({
    id: String((row as Record<string, unknown>).id),
    name: String((row as Record<string, unknown>).name),
  }))
}

export async function searchProducts(search: string): Promise<ProductOption[]> {
  const q = search.trim()
  let query = supabase
    .from('products')
    .select('id, sku, name, unit, sale_price, stock_qty')
    .eq('is_active', true)
    .gt('stock_qty', 0)
    .order('sku')
    .limit(15)

  if (q) query = query.or(`sku.ilike.%${q}%,name.ilike.%${q}%`)

  const { data, error } = await query
  if (error) throw new Error(friendlyRpcError(error))

  return (data ?? []).map((row) => {
    const r = row as Record<string, unknown>
    return {
      id: String(r.id),
      sku: String(r.sku),
      name: String(r.name),
      unit: String(r.unit),
      sale_price: Number(r.sale_price),
      stock_qty: Number(r.stock_qty),
    }
  })
}

export async function createSaleRpc(values: SaleFormValues) {
  const { data, error } = await supabase.rpc('create_sale', {
    p_customer: values.customer_id,
    p_date: values.doc_date,
    p_items: values.items.map((line) => ({
      product_id: line.product_id,
      qty: line.qty,
      unit_price: line.unit_price,
    })),
    p_discount: values.discount,
    p_paid: values.amount_paid,
  })

  if (error) throw new Error(friendlyRpcError(error))
  return String(data)
}

export async function voidSaleRpc(id: string) {
  const { error } = await supabase.rpc('void_sale', { p_id: id })
  if (error) throw new Error(friendlyRpcError(error))
}

export async function receivePaymentRpc(params: {
  customerId: string
  amount: number
  method: 'cash' | 'bank'
}) {
  const { data, error } = await supabase.rpc('record_payment', {
    p_party: params.customerId,
    p_amount: params.amount,
    p_direction: 'receipt',
    p_method: params.method,
  })

  if (error) throw new Error(friendlyRpcError(error))
  return String(data)
}

export function useSalesQuery(filters: SaleListFilters) {
  return useQuery({
    queryKey: saleKeys.list(filters),
    queryFn: () => listSales(filters),
    placeholderData: (prev) => prev,
  })
}

export function useSaleQuery(id: string | undefined) {
  return useQuery({
    queryKey: saleKeys.detail(id ?? ''),
    queryFn: () => getSale(id!),
    enabled: Boolean(id),
  })
}

export function useCustomersQuery() {
  return useQuery({
    queryKey: saleKeys.customers,
    queryFn: listActiveCustomers,
  })
}

export function useProductSearchQuery(search: string, enabled: boolean) {
  return useQuery({
    queryKey: saleKeys.productSearch(search),
    queryFn: () => searchProducts(search),
    enabled,
  })
}

export function useCreateSaleMutation() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: createSaleRpc,
    onSuccess: async () => {
      await Promise.all([
        qc.invalidateQueries({ queryKey: queryKeys.sales }),
        qc.invalidateQueries({ queryKey: queryKeys.products }),
        qc.invalidateQueries({ queryKey: queryKeys.stock }),
        qc.invalidateQueries({ queryKey: queryKeys.dashboard }),
      ])
    },
  })
}

export function useVoidSaleMutation() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: voidSaleRpc,
    onSuccess: async (_data, id) => {
      await Promise.all([
        qc.invalidateQueries({ queryKey: queryKeys.sales }),
        qc.invalidateQueries({ queryKey: saleKeys.detail(id) }),
        qc.invalidateQueries({ queryKey: queryKeys.products }),
        qc.invalidateQueries({ queryKey: queryKeys.stock }),
        qc.invalidateQueries({ queryKey: queryKeys.dashboard }),
      ])
    },
  })
}

export function useReceivePaymentMutation() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: receivePaymentRpc,
    onSuccess: async () => {
      await Promise.all([
        qc.invalidateQueries({ queryKey: queryKeys.sales }),
        qc.invalidateQueries({ queryKey: queryKeys.dashboard }),
      ])
    },
  })
}

export { PAGE_SIZE }
