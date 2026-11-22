/**
 * Hand-maintained Supabase Database types for Mini ERP.
 * Regenerate later with `supabase gen types typescript` when CLI is linked.
 */

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type AppRole = 'admin' | 'sales' | 'purchase' | 'accountant'
export type PartyKind = 'customer' | 'supplier'
export type DocStatus = 'posted' | 'void'
export type StockMoveKind =
  | 'purchase'
  | 'sale'
  | 'adjustment'
  | 'void_reversal'
export type AccountType =
  | 'asset'
  | 'liability'
  | 'equity'
  | 'revenue'
  | 'expense'
export type PaymentKind = 'receipt' | 'disbursement'

type Timestamps = {
  created_at: string
  created_by: string | null
}

export type Database = {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string
          full_name: string | null
          role: AppRole
          created_at: string
          created_by: string | null
        }
        Insert: {
          id: string
          full_name?: string | null
          role?: AppRole
          created_at?: string
          created_by?: string | null
        }
        Update: {
          id?: string
          full_name?: string | null
          role?: AppRole
          created_at?: string
          created_by?: string | null
        }
        Relationships: []
      }
      products: {
        Row: {
          id: string
          sku: string
          name: string
          unit: string
          sale_price: number
          avg_cost: number
          stock_qty: number
          reorder_level: number
          is_active: boolean
          is_low: boolean
        } & Timestamps
        Insert: {
          id?: string
          sku: string
          name: string
          unit?: string
          sale_price?: number
          avg_cost?: number
          stock_qty?: number
          reorder_level?: number
          is_active?: boolean
          created_at?: string
          created_by?: string | null
        }
        Update: {
          id?: string
          sku?: string
          name?: string
          unit?: string
          sale_price?: number
          avg_cost?: number
          stock_qty?: number
          reorder_level?: number
          is_active?: boolean
          created_at?: string
          created_by?: string | null
        }
        Relationships: []
      }
      parties: {
        Row: {
          id: string
          kind: PartyKind
          name: string
          email: string | null
          phone: string | null
          is_active: boolean
        } & Timestamps
        Insert: {
          id?: string
          kind: PartyKind
          name: string
          email?: string | null
          phone?: string | null
          is_active?: boolean
          created_at?: string
          created_by?: string | null
        }
        Update: {
          id?: string
          kind?: PartyKind
          name?: string
          email?: string | null
          phone?: string | null
          is_active?: boolean
          created_at?: string
          created_by?: string | null
        }
        Relationships: []
      }
      purchases: {
        Row: {
          id: string
          doc_number: string
          supplier_id: string
          status: DocStatus
          doc_date: string
          subtotal: number
          discount: number
          total: number
          amount_paid: number
          notes: string | null
        } & Timestamps
        Insert: Record<string, never>
        Update: {
          status?: DocStatus
          amount_paid?: number
        }
        Relationships: []
      }
      purchase_items: {
        Row: {
          id: string
          purchase_id: string
          product_id: string
          qty: number
          unit_cost: number
          line_total: number
          inv_amount: number
        } & Timestamps
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
      sales: {
        Row: {
          id: string
          doc_number: string
          customer_id: string
          status: DocStatus
          doc_date: string
          subtotal: number
          discount: number
          total: number
          amount_paid: number
          notes: string | null
        } & Timestamps
        Insert: Record<string, never>
        Update: {
          status?: DocStatus
          amount_paid?: number
        }
        Relationships: []
      }
      sale_items: {
        Row: {
          id: string
          sale_id: string
          product_id: string
          qty: number
          unit_price: number
          unit_cost: number
          line_total: number
        } & Timestamps
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
      stock_movements: {
        Row: {
          id: string
          product_id: string
          kind: StockMoveKind
          qty_delta: number
          source_type: string
          source_id: string
          note: string | null
        } & Timestamps
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
      accounts: {
        Row: {
          id: string
          code: string
          name: string
          account_type: AccountType
          is_active: boolean
        } & Timestamps
        Insert: {
          id?: string
          code: string
          name: string
          account_type: AccountType
          is_active?: boolean
          created_at?: string
          created_by?: string | null
        }
        Update: {
          code?: string
          name?: string
          account_type?: AccountType
          is_active?: boolean
        }
        Relationships: []
      }
      journal_entries: {
        Row: {
          id: string
          entry_date: string
          status: DocStatus
          memo: string | null
          source_type: string | null
          source_id: string | null
        } & Timestamps
        Insert: Record<string, never>
        Update: { status?: DocStatus }
        Relationships: []
      }
      journal_lines: {
        Row: {
          id: string
          journal_entry_id: string
          account_id: string
          debit: number
          credit: number
          memo: string | null
        } & Timestamps
        Insert: Record<string, never>
        Update: Record<string, never>
        Relationships: []
      }
      payments: {
        Row: {
          id: string
          kind: PaymentKind
          party_id: string
          account_id: string
          amount: number
          status: DocStatus
          payment_date: string
          source_type: string | null
          source_id: string | null
          reference: string | null
          notes: string | null
        } & Timestamps
        Insert: Record<string, never>
        Update: { status?: DocStatus }
        Relationships: []
      }
    }
    Views: {
      v_dashboard_kpis: {
        Row: {
          today_sales: number
          month_sales: number
          month_purchases: number
          stock_value: number
          receivable: number
          payable: number
          low_stock_count: number
        }
        Relationships: []
      }
      v_dashboard_daily_30d: {
        Row: {
          day: string
          sales_total: number
          purchase_total: number
        }
        Relationships: []
      }
      v_dashboard_top_products: {
        Row: {
          product_id: string
          sku: string
          name: string
          qty_sold: number
          revenue: number
        }
        Relationships: []
      }
      v_party_receivables: {
        Row: {
          party_id: string
          party_name: string
          email: string | null
          open_docs: number
          balance: number
        }
        Relationships: []
      }
      v_party_payables: {
        Row: {
          party_id: string
          party_name: string
          email: string | null
          open_docs: number
          balance: number
        }
        Relationships: []
      }
    }
    Functions: {
      create_purchase: {
        Args: {
          p_supplier: string
          p_date: string
          p_items: Json
          p_discount: number
          p_paid: number
        }
        Returns: string
      }
      create_sale: {
        Args: {
          p_customer: string
          p_date: string
          p_items: Json
          p_discount: number
          p_paid: number
        }
        Returns: string
      }
      void_purchase: { Args: { p_id: string }; Returns: string }
      void_sale: { Args: { p_id: string }; Returns: string }
      record_payment: {
        Args: {
          p_party: string
          p_amount: number
          p_direction: string
          p_method: string
        }
        Returns: string
      }
      adjust_stock: {
        Args: {
          p_product: string
          p_qty_delta: number
          p_unit_cost?: number | null
          p_note?: string | null
        }
        Returns: string
      }
      get_trial_balance: {
        Args: { p_as_of?: string }
        Returns: {
          account_id: string
          code: string
          name: string
          account_type: AccountType
          total_debit: number
          total_credit: number
          balance: number
        }[]
      }
      get_trial_balance_totals: {
        Args: { p_as_of?: string }
        Returns: {
          total_debit: number
          total_credit: number
          difference: number
          is_balanced: boolean
        }[]
      }
      get_account_ledger: {
        Args: {
          p_account_id: string
          p_from?: string | null
          p_to?: string | null
        }
        Returns: {
          line_id: string
          entry_id: string
          entry_date: string
          memo: string | null
          source_type: string | null
          source_id: string | null
          debit: number
          credit: number
          running_balance: number
        }[]
      }
      get_profit_and_loss: {
        Args: { p_from: string; p_to: string }
        Returns: {
          section: string
          account_id: string
          code: string
          name: string
          amount: number
        }[]
      }
      get_profit_and_loss_summary: {
        Args: { p_from: string; p_to: string }
        Returns: {
          total_revenue: number
          total_expense: number
          net_profit: number
        }[]
      }
      has_role: {
        Args: { required: string[] | AppRole | AppRole[] }
        Returns: boolean
      }
    }
    Enums: {
      app_role: AppRole
      party_kind: PartyKind
      doc_status: DocStatus
      stock_move_kind: StockMoveKind
      account_type: AccountType
      payment_kind: PaymentKind
    }
    CompositeTypes: Record<string, never>
  }
}

export type Tables<T extends keyof Database['public']['Tables']> =
  Database['public']['Tables'][T]['Row']

export type Views<T extends keyof Database['public']['Views']> =
  Database['public']['Views'][T]['Row']
