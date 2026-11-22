import {
  useMutation,
  useQuery,
  useQueryClient,
} from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { PAGE_SIZE, pageRange } from '@/shared/lib/pagination'
import { queryKeys } from '@/shared/lib/query-keys'
import { friendlyRpcError } from '@/shared/lib/rpc-error'
import type { PurchaseFormValues } from '@/features/purchases/schemas'
import type {
  ProductOption,
  PurchaseDetail,
  PurchaseListFilters,
  PurchaseListItem,
  SupplierOption,
} from '@/features/purchases/types'

export const purchaseKeys = {
  all: queryKeys.purchases,
  list: (filters: PurchaseListFilters) =>
    [...queryKeys.purchases, 'list', filters] as const,
  detail: (id: string) => [...queryKeys.purchases, 'detail', id] as const,
  suppliers: [...queryKeys.purchases, 'suppliers'] as const,
  productSearch: (q: string) =>
    [...queryKeys.purchases, 'product-search', q] as const,
}

function mapListRow(row: Record<string, unknown>): PurchaseListItem {
  const supplier = row.supplier as Record<string, unknown> | null
  return {
    id: String(row.id),
    doc_number: String(row.doc_number),
    doc_date: String(row.doc_date),
    status: row.status as PurchaseListItem['status'],
    subtotal: Number(row.subtotal),
    discount: Number(row.discount ?? 0),
    total: Number(row.total),
    amount_paid: Number(row.amount_paid ?? 0),
    supplier_id: String(row.supplier_id),
    supplier_name: supplier ? String(supplier.name) : '—',
  }
}

export async function listPurchases(filters: PurchaseListFilters) {
  const { from, to } = pageRange(filters.page)
  let query = supabase
    .from('purchases')
    .select(
      'id, doc_number, doc_date, status, subtotal, discount, total, amount_paid, supplier_id, supplier:parties!purchases_supplier_id_fkey(id, name)',
      { count: 'exact' },
    )
    .order('doc_date', { ascending: false })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (filters.dateFrom) query = query.gte('doc_date', filters.dateFrom)
  if (filters.dateTo) query = query.lte('doc_date', filters.dateTo)
  if (filters.supplierId) query = query.eq('supplier_id', filters.supplierId)
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

export async function getPurchase(id: string): Promise<PurchaseDetail> {
  const { data, error } = await supabase
    .from('purchases')
    .select(
      `
      id, doc_number, doc_date, status, subtotal, discount, total, amount_paid, supplier_id, notes,
      supplier:parties!purchases_supplier_id_fkey(id, name),
      purchase_items(
        id, product_id, qty, unit_cost, line_total,
        product:products(id, sku, name)
      )
    `,
    )
    .eq('id', id)
    .single()

  if (error) throw new Error(friendlyRpcError(error))

  const row = data as Record<string, unknown>
  const base = mapListRow(row)
  const itemsRaw = (row.purchase_items as Record<string, unknown>[] | null) ?? []

  return {
    ...base,
    notes: (row.notes as string | null) ?? null,
    items: itemsRaw.map((item) => {
      const product = item.product as Record<string, unknown> | null
      return {
        id: String(item.id),
        product_id: String(item.product_id),
        qty: Number(item.qty),
        unit_cost: Number(item.unit_cost),
        line_total: Number(item.line_total),
        product_sku: product ? String(product.sku) : '—',
        product_name: product ? String(product.name) : '—',
      }
    }),
  }
}

export async function listActiveSuppliers(): Promise<SupplierOption[]> {
  const { data, error } = await supabase
    .from('parties')
    .select('id, name')
    .eq('kind', 'supplier')
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
    .select('id, sku, name, unit, avg_cost')
    .eq('is_active', true)
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
      avg_cost: Number(r.avg_cost),
    }
  })
}

export async function createPurchaseRpc(values: PurchaseFormValues) {
  const { data, error } = await supabase.rpc('create_purchase', {
    p_supplier: values.supplier_id,
    p_date: values.doc_date,
    p_items: values.items.map((line) => ({
      product_id: line.product_id,
      qty: line.qty,
      unit_cost: line.unit_cost,
    })),
    p_discount: values.discount,
    p_paid: values.amount_paid,
  })

  if (error) throw new Error(friendlyRpcError(error))
  return String(data)
}

export async function voidPurchaseRpc(id: string) {
  const { error } = await supabase.rpc('void_purchase', { p_id: id })
  if (error) throw new Error(friendlyRpcError(error))
}

export async function paySupplierRpc(params: {
  supplierId: string
  amount: number
  method: 'cash' | 'bank'
}) {
  const { data, error } = await supabase.rpc('record_payment', {
    p_party: params.supplierId,
    p_amount: params.amount,
    p_direction: 'disbursement',
    p_method: params.method,
  })

  if (error) throw new Error(friendlyRpcError(error))
  return String(data)
}

export function usePurchasesQuery(filters: PurchaseListFilters) {
  return useQuery({
    queryKey: purchaseKeys.list(filters),
    queryFn: () => listPurchases(filters),
    placeholderData: (prev) => prev,
  })
}

export function usePurchaseQuery(id: string | undefined) {
  return useQuery({
    queryKey: purchaseKeys.detail(id ?? ''),
    queryFn: () => getPurchase(id!),
    enabled: Boolean(id),
  })
}

export function useSuppliersQuery() {
  return useQuery({
    queryKey: purchaseKeys.suppliers,
    queryFn: listActiveSuppliers,
  })
}

export function useProductSearchQuery(search: string, enabled: boolean) {
  return useQuery({
    queryKey: purchaseKeys.productSearch(search),
    queryFn: () => searchProducts(search),
    enabled,
  })
}

export function useCreatePurchaseMutation() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: createPurchaseRpc,
    onSuccess: async () => {
      await Promise.all([
        qc.invalidateQueries({ queryKey: queryKeys.purchases }),
        qc.invalidateQueries({ queryKey: queryKeys.products }),
        qc.invalidateQueries({ queryKey: queryKeys.stock }),
        qc.invalidateQueries({ queryKey: queryKeys.dashboard }),
      ])
    },
  })
}

export function useVoidPurchaseMutation() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: voidPurchaseRpc,
    onSuccess: async (_data, id) => {
      await Promise.all([
        qc.invalidateQueries({ queryKey: queryKeys.purchases }),
        qc.invalidateQueries({ queryKey: purchaseKeys.detail(id) }),
        qc.invalidateQueries({ queryKey: queryKeys.products }),
        qc.invalidateQueries({ queryKey: queryKeys.stock }),
        qc.invalidateQueries({ queryKey: queryKeys.dashboard }),
      ])
    },
  })
}

export function usePaySupplierMutation() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: paySupplierRpc,
    onSuccess: async () => {
      await Promise.all([
        qc.invalidateQueries({ queryKey: queryKeys.purchases }),
        qc.invalidateQueries({ queryKey: queryKeys.dashboard }),
        qc.invalidateQueries({ queryKey: queryKeys.accounts }),
      ])
    },
  })
}

export { PAGE_SIZE }
