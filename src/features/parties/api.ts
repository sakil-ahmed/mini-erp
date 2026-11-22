import {
  useMutation,
  useQuery,
  useQueryClient,
} from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { PAGE_SIZE, pageRange } from '@/shared/lib/pagination'
import type { Party, PartyKind, PartyListResult } from '@/features/parties/types'
import type { PartyFormValues } from '@/features/parties/schemas'

function mapParty(row: Record<string, unknown>): Party {
  return {
    id: String(row.id),
    kind: row.kind as PartyKind,
    name: String(row.name),
    email: (row.email as string | null) ?? null,
    phone: (row.phone as string | null) ?? null,
    is_active: Boolean(row.is_active),
    created_at: String(row.created_at),
  }
}

export async function listParties(params: {
  page: number
  search: string
  kind: PartyKind
}): Promise<PartyListResult> {
  const { from, to } = pageRange(params.page)
  let query = supabase
    .from('parties')
    .select('*', { count: 'exact' })
    .eq('kind', params.kind)
    .order('name', { ascending: true })
    .range(from, to)

  const q = params.search.trim()
  if (q) {
    query = query.or(`name.ilike.%${q}%,email.ilike.%${q}%,phone.ilike.%${q}%`)
  }

  const { data, error, count } = await query
  if (error) throw new Error(error.message)

  return {
    rows: (data ?? []).map((row) => mapParty(row as Record<string, unknown>)),
    total: count ?? 0,
  }
}

function toNullable(value: string | undefined) {
  const v = value?.trim() ?? ''
  return v.length > 0 ? v : null
}

export async function createParty(kind: PartyKind, values: PartyFormValues) {
  const { data, error } = await supabase
    .from('parties')
    .insert({
      kind,
      name: values.name,
      email: toNullable(values.email),
      phone: toNullable(values.phone),
      is_active: values.is_active,
    })
    .select('*')
    .single()

  if (error) throw new Error(error.message)
  return mapParty(data as Record<string, unknown>)
}

export async function updateParty(id: string, values: PartyFormValues) {
  const { data, error } = await supabase
    .from('parties')
    .update({
      name: values.name,
      email: toNullable(values.email),
      phone: toNullable(values.phone),
      is_active: values.is_active,
    })
    .eq('id', id)
    .select('*')
    .single()

  if (error) throw new Error(error.message)
  return mapParty(data as Record<string, unknown>)
}

export async function setPartyActive(id: string, isActive: boolean) {
  const { error } = await supabase
    .from('parties')
    .update({ is_active: isActive })
    .eq('id', id)

  if (error) throw new Error(error.message)
}

export const partyKeys = {
  all: ['parties'] as const,
  list: (kind: PartyKind, page: number, search: string) =>
    [...partyKeys.all, kind, page, search] as const,
}

export function usePartiesQuery(
  kind: PartyKind,
  page: number,
  search: string,
) {
  return useQuery({
    queryKey: partyKeys.list(kind, page, search),
    queryFn: () => listParties({ kind, page, search }),
    placeholderData: (prev) => prev,
  })
}

export function usePartyMutations() {
  const qc = useQueryClient()
  const invalidate = () =>
    void qc.invalidateQueries({ queryKey: partyKeys.all })

  const create = useMutation({
    mutationFn: ({
      kind,
      values,
    }: {
      kind: PartyKind
      values: PartyFormValues
    }) => createParty(kind, values),
    onSuccess: invalidate,
  })

  const update = useMutation({
    mutationFn: ({ id, values }: { id: string; values: PartyFormValues }) =>
      updateParty(id, values),
    onSuccess: invalidate,
  })

  const setActive = useMutation({
    mutationFn: ({ id, isActive }: { id: string; isActive: boolean }) =>
      setPartyActive(id, isActive),
    onSuccess: invalidate,
  })

  return { create, update, setActive, pageSize: PAGE_SIZE }
}
