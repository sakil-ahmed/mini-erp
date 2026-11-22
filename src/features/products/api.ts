import {
  useMutation,
  useQuery,
  useQueryClient,
} from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { PAGE_SIZE, pageRange } from '@/shared/lib/pagination'
import { queryKeys } from '@/shared/lib/query-keys'
import type { Product, ProductListResult } from '@/features/products/types'
import type { ProductFormValues } from '@/features/products/schemas'

function mapProduct(row: Record<string, unknown>): Product {
  return {
    id: String(row.id),
    sku: String(row.sku),
    name: String(row.name),
    unit: String(row.unit),
    sale_price: Number(row.sale_price),
    avg_cost: Number(row.avg_cost),
    stock_qty: Number(row.stock_qty),
    reorder_level: Number(row.reorder_level),
    is_active: Boolean(row.is_active),
    created_at: String(row.created_at),
  }
}

export async function listProducts(params: {
  page: number
  search: string
}): Promise<ProductListResult> {
  const { from, to } = pageRange(params.page)
  let query = supabase
    .from('products')
    .select('*', { count: 'exact' })
    .order('sku', { ascending: true })
    .range(from, to)

  const q = params.search.trim()
  if (q) {
    query = query.or(`sku.ilike.%${q}%,name.ilike.%${q}%`)
  }

  const { data, error, count } = await query
  if (error) throw new Error(error.message)

  return {
    rows: (data ?? []).map((row) => mapProduct(row as Record<string, unknown>)),
    total: count ?? 0,
  }
}

export async function createProduct(values: ProductFormValues) {
  const { data, error } = await supabase
    .from('products')
    .insert({
      sku: values.sku,
      name: values.name,
      unit: values.unit,
      sale_price: values.sale_price,
      reorder_level: values.reorder_level,
      is_active: values.is_active,
    })
    .select('*')
    .single()

  if (error) throw new Error(error.message)
  return mapProduct(data as Record<string, unknown>)
}

export async function updateProduct(id: string, values: ProductFormValues) {
  const { data, error } = await supabase
    .from('products')
    .update({
      sku: values.sku,
      name: values.name,
      unit: values.unit,
      sale_price: values.sale_price,
      reorder_level: values.reorder_level,
      is_active: values.is_active,
    })
    .eq('id', id)
    .select('*')
    .single()

  if (error) throw new Error(error.message)
  return mapProduct(data as Record<string, unknown>)
}

/** Soft deactivate / reactivate — never delete. */
export async function setProductActive(id: string, isActive: boolean) {
  const { error } = await supabase
    .from('products')
    .update({ is_active: isActive })
    .eq('id', id)

  if (error) throw new Error(error.message)
}

export const productKeys = {
  all: queryKeys.products,
  list: (page: number, search: string) =>
    [...queryKeys.products, 'list', page, search] as const,
}

export function useProductsQuery(page: number, search: string) {
  return useQuery({
    queryKey: productKeys.list(page, search),
    queryFn: () => listProducts({ page, search }),
    placeholderData: (prev) => prev,
  })
}

export function useProductMutations() {
  const qc = useQueryClient()
  const invalidate = () =>
    void qc.invalidateQueries({ queryKey: productKeys.all })

  const create = useMutation({
    mutationFn: createProduct,
    onSuccess: invalidate,
  })

  const update = useMutation({
    mutationFn: ({ id, values }: { id: string; values: ProductFormValues }) =>
      updateProduct(id, values),
    onSuccess: invalidate,
  })

  const setActive = useMutation({
    mutationFn: ({ id, isActive }: { id: string; isActive: boolean }) =>
      setProductActive(id, isActive),
    onSuccess: invalidate,
  })

  return { create, update, setActive, pageSize: PAGE_SIZE }
}
