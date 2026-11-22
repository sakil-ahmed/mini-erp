export type PartyKind = 'customer' | 'supplier'

export type Party = {
  id: string
  kind: PartyKind
  name: string
  email: string | null
  phone: string | null
  is_active: boolean
  created_at: string
}

export type PartyListResult = {
  rows: Party[]
  total: number
}
