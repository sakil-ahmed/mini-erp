/** Shared root keys so features can invalidate without cross-imports. */
export const queryKeys = {
  products: ['products'] as const,
  parties: ['parties'] as const,
  purchases: ['purchases'] as const,
  sales: ['sales'] as const,
  stock: ['stock'] as const,
  accounts: ['accounts'] as const,
  dashboard: ['dashboard'] as const,
}
