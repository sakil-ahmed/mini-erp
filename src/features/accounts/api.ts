import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { PAGE_SIZE, pageRange } from '@/shared/lib/pagination'
import { queryKeys } from '@/shared/lib/query-keys'
import { friendlyRpcError } from '@/shared/lib/rpc-error'
import type {
  Account,
  JournalEntry,
  LedgerRow,
  PartyBalanceRow,
  ProfitLossRow,
  ProfitLossSummary,
  TrialBalanceRow,
  TrialBalanceTotals,
} from '@/features/accounts/types'

export const accountKeys = {
  all: queryKeys.accounts,
  chart: [...queryKeys.accounts, 'chart'] as const,
  journals: (page: number) =>
    [...queryKeys.accounts, 'journals', page] as const,
  trialBalance: (asOf: string) =>
    [...queryKeys.accounts, 'trial-balance', asOf] as const,
  ledger: (accountId: string, from: string, to: string) =>
    [...queryKeys.accounts, 'ledger', accountId, from, to] as const,
  pnl: (from: string, to: string) =>
    [...queryKeys.accounts, 'pnl', from, to] as const,
  receivables: [...queryKeys.accounts, 'receivables'] as const,
  payables: [...queryKeys.accounts, 'payables'] as const,
}

function num(v: unknown) {
  return Number(v ?? 0)
}

export async function listChartOfAccounts(): Promise<Account[]> {
  const { data, error } = await supabase
    .from('accounts')
    .select('id, code, name, account_type, is_active')
    .order('code')

  if (error) throw new Error(friendlyRpcError(error))
  return (data ?? []).map((row) => {
    const r = row as Record<string, unknown>
    return {
      id: String(r.id),
      code: String(r.code),
      name: String(r.name),
      account_type: r.account_type as Account['account_type'],
      is_active: Boolean(r.is_active),
    }
  })
}

export async function listJournals(page: number) {
  const { from, to } = pageRange(page)
  const { data, error, count } = await supabase
    .from('journal_entries')
    .select(
      `
      id, entry_date, status, memo, source_type, source_id,
      journal_lines(
        id, account_id, debit, credit, memo,
        account:accounts(code, name)
      )
    `,
      { count: 'exact' },
    )
    .order('entry_date', { ascending: false })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (error) throw new Error(friendlyRpcError(error))

  const rows: JournalEntry[] = (data ?? []).map((row) => {
    const r = row as Record<string, unknown>
    const linesRaw = (r.journal_lines as Record<string, unknown>[] | null) ?? []
    return {
      id: String(r.id),
      entry_date: String(r.entry_date),
      status: r.status as JournalEntry['status'],
      memo: (r.memo as string | null) ?? null,
      source_type: (r.source_type as string | null) ?? null,
      source_id: r.source_id ? String(r.source_id) : null,
      lines: linesRaw.map((line) => {
        const account = line.account as Record<string, unknown> | null
        return {
          id: String(line.id),
          account_id: String(line.account_id),
          account_code: account ? String(account.code) : '—',
          account_name: account ? String(account.name) : '—',
          debit: num(line.debit),
          credit: num(line.credit),
          memo: (line.memo as string | null) ?? null,
        }
      }),
    }
  })

  return { rows, total: count ?? 0 }
}

export async function fetchTrialBalance(asOf: string) {
  const [rowsRes, totalsRes] = await Promise.all([
    supabase.rpc('get_trial_balance', { p_as_of: asOf }),
    supabase.rpc('get_trial_balance_totals', { p_as_of: asOf }),
  ])

  if (rowsRes.error) throw new Error(friendlyRpcError(rowsRes.error))
  if (totalsRes.error) throw new Error(friendlyRpcError(totalsRes.error))

  const rows: TrialBalanceRow[] = ((rowsRes.data ?? []) as Record<string, unknown>[]).map((r) => {
    return {
      account_id: String(r.account_id),
      code: String(r.code),
      name: String(r.name),
      account_type: r.account_type as TrialBalanceRow['account_type'],
      total_debit: num(r.total_debit),
      total_credit: num(r.total_credit),
      balance: num(r.balance),
    }
  })

  const t = ((totalsRes.data ?? [])[0] ?? {}) as Record<string, unknown>
  const totals: TrialBalanceTotals = {
    total_debit: num(t.total_debit),
    total_credit: num(t.total_credit),
    difference: num(t.difference),
    is_balanced: Boolean(t.is_balanced),
  }

  return { rows, totals }
}

export async function fetchAccountLedger(
  accountId: string,
  from: string,
  to: string,
): Promise<LedgerRow[]> {
  const { data, error } = await supabase.rpc('get_account_ledger', {
    p_account_id: accountId,
    p_from: from || null,
    p_to: to || null,
  })

  if (error) throw new Error(friendlyRpcError(error))

  return ((data ?? []) as Record<string, unknown>[]).map((r) => ({
    line_id: String(r.line_id),
    entry_id: String(r.entry_id),
    entry_date: String(r.entry_date),
    memo: (r.memo as string | null) ?? null,
    source_type: (r.source_type as string | null) ?? null,
    source_id: r.source_id ? String(r.source_id) : null,
    debit: num(r.debit),
    credit: num(r.credit),
    running_balance: num(r.running_balance),
  }))
}

export async function fetchProfitAndLoss(from: string, to: string) {
  const [rowsRes, summaryRes] = await Promise.all([
    supabase.rpc('get_profit_and_loss', { p_from: from, p_to: to }),
    supabase.rpc('get_profit_and_loss_summary', { p_from: from, p_to: to }),
  ])

  if (rowsRes.error) throw new Error(friendlyRpcError(rowsRes.error))
  if (summaryRes.error) throw new Error(friendlyRpcError(summaryRes.error))

  const rows: ProfitLossRow[] = ((rowsRes.data ?? []) as Record<string, unknown>[]).map((r) => ({
    section: r.section as ProfitLossRow['section'],
    account_id: String(r.account_id),
    code: String(r.code),
    name: String(r.name),
    amount: num(r.amount),
  }))

  const s = ((summaryRes.data ?? [])[0] ?? {}) as Record<string, unknown>
  const summary: ProfitLossSummary = {
    total_revenue: num(s.total_revenue),
    total_expense: num(s.total_expense),
    net_profit: num(s.net_profit),
  }

  return { rows, summary }
}

export async function listReceivables(): Promise<PartyBalanceRow[]> {
  const { data, error } = await supabase
    .from('v_party_receivables')
    .select('party_id, party_name, email, open_docs, balance')
    .order('balance', { ascending: false })

  if (error) throw new Error(friendlyRpcError(error))
  return (data ?? []).map((row) => {
    const r = row as Record<string, unknown>
    return {
      party_id: String(r.party_id),
      party_name: String(r.party_name),
      email: (r.email as string | null) ?? null,
      open_docs: Number(r.open_docs),
      balance: num(r.balance),
    }
  })
}

export async function listPayables(): Promise<PartyBalanceRow[]> {
  const { data, error } = await supabase
    .from('v_party_payables')
    .select('party_id, party_name, email, open_docs, balance')
    .order('balance', { ascending: false })

  if (error) throw new Error(friendlyRpcError(error))
  return (data ?? []).map((row) => {
    const r = row as Record<string, unknown>
    return {
      party_id: String(r.party_id),
      party_name: String(r.party_name),
      email: (r.email as string | null) ?? null,
      open_docs: Number(r.open_docs),
      balance: num(r.balance),
    }
  })
}

export function useChartOfAccountsQuery() {
  return useQuery({
    queryKey: accountKeys.chart,
    queryFn: listChartOfAccounts,
  })
}

export function useJournalsQuery(page: number) {
  return useQuery({
    queryKey: accountKeys.journals(page),
    queryFn: () => listJournals(page),
    placeholderData: (prev) => prev,
  })
}

export function useTrialBalanceQuery(asOf: string) {
  return useQuery({
    queryKey: accountKeys.trialBalance(asOf),
    queryFn: () => fetchTrialBalance(asOf),
  })
}

export function useAccountLedgerQuery(
  accountId: string | undefined,
  from: string,
  to: string,
) {
  return useQuery({
    queryKey: accountKeys.ledger(accountId ?? '', from, to),
    queryFn: () => fetchAccountLedger(accountId!, from, to),
    enabled: Boolean(accountId),
  })
}

export function useProfitAndLossQuery(from: string, to: string) {
  return useQuery({
    queryKey: accountKeys.pnl(from, to),
    queryFn: () => fetchProfitAndLoss(from, to),
  })
}

export function useReceivablesQuery() {
  return useQuery({
    queryKey: accountKeys.receivables,
    queryFn: listReceivables,
  })
}

export function usePayablesQuery() {
  return useQuery({
    queryKey: accountKeys.payables,
    queryFn: listPayables,
  })
}

export { PAGE_SIZE }
