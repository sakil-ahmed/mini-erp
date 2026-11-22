export type AccountType =
  | 'asset'
  | 'liability'
  | 'equity'
  | 'revenue'
  | 'expense'

export type Account = {
  id: string
  code: string
  name: string
  account_type: AccountType
  is_active: boolean
}

export type JournalLine = {
  id: string
  account_id: string
  account_code: string
  account_name: string
  debit: number
  credit: number
  memo: string | null
}

export type JournalEntry = {
  id: string
  entry_date: string
  status: 'posted' | 'void'
  memo: string | null
  source_type: string | null
  source_id: string | null
  lines: JournalLine[]
}

export type TrialBalanceRow = {
  account_id: string
  code: string
  name: string
  account_type: AccountType
  total_debit: number
  total_credit: number
  balance: number
}

export type TrialBalanceTotals = {
  total_debit: number
  total_credit: number
  difference: number
  is_balanced: boolean
}

export type LedgerRow = {
  line_id: string
  entry_id: string
  entry_date: string
  memo: string | null
  source_type: string | null
  source_id: string | null
  debit: number
  credit: number
  running_balance: number
}

export type ProfitLossRow = {
  section: 'revenue' | 'expense'
  account_id: string
  code: string
  name: string
  amount: number
}

export type ProfitLossSummary = {
  total_revenue: number
  total_expense: number
  net_profit: number
}

export type PartyBalanceRow = {
  party_id: string
  party_name: string
  email: string | null
  open_docs: number
  balance: number
}
