import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { AppLayout } from '@/app/layout/AppLayout'
import {
  LoginPage,
  ProtectedRoute,
  RoleGuard,
  ROUTE_ROLES,
} from '@/features/auth'
import { DashboardPage } from '@/features/dashboard/pages/DashboardPage'
import { ProductsPage } from '@/features/products/pages/ProductsPage'
import { PartiesPage } from '@/features/parties/pages/PartiesPage'
import { SalesPage } from '@/features/sales/pages/SalesPage'
import { SaleCreatePage } from '@/features/sales/pages/SaleCreatePage'
import { SaleDetailPage } from '@/features/sales/pages/SaleDetailPage'
import { PurchasesPage } from '@/features/purchases/pages/PurchasesPage'
import { PurchaseCreatePage } from '@/features/purchases/pages/PurchaseCreatePage'
import { PurchaseDetailPage } from '@/features/purchases/pages/PurchaseDetailPage'
import { InventoryPage } from '@/features/inventory/pages/InventoryPage'
import { ProductMovementsPage } from '@/features/inventory/pages/ProductMovementsPage'
import { AccountsLayout } from '@/features/accounts/pages/AccountsLayout'
import { ChartOfAccountsPage } from '@/features/accounts/pages/ChartOfAccountsPage'
import { JournalsPage } from '@/features/accounts/pages/JournalsPage'
import { AccountLedgerPage } from '@/features/accounts/pages/AccountLedgerPage'
import { TrialBalancePage } from '@/features/accounts/pages/TrialBalancePage'
import { ProfitLossPage } from '@/features/accounts/pages/ProfitLossPage'
import { PartyBalancesPage } from '@/features/accounts/pages/PartyBalancesPage'

function AccountsGuard({ children }: { children: React.ReactNode }) {
  return <RoleGuard allow={ROUTE_ROLES.accounts}>{children}</RoleGuard>
}

export function AppRouter() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<LoginPage />} />

        <Route element={<ProtectedRoute />}>
          <Route element={<AppLayout />}>
            <Route
              index
              element={
                <RoleGuard allow={ROUTE_ROLES.dashboard}>
                  <DashboardPage />
                </RoleGuard>
              }
            />
            <Route
              path="products"
              element={
                <RoleGuard allow={ROUTE_ROLES.products}>
                  <ProductsPage />
                </RoleGuard>
              }
            />
            <Route
              path="parties"
              element={
                <RoleGuard allow={ROUTE_ROLES.parties}>
                  <PartiesPage />
                </RoleGuard>
              }
            />
            <Route
              path="sales"
              element={
                <RoleGuard allow={ROUTE_ROLES.sales}>
                  <SalesPage />
                </RoleGuard>
              }
            />
            <Route
              path="sales/new"
              element={
                <RoleGuard allow={ROUTE_ROLES.sales}>
                  <SaleCreatePage />
                </RoleGuard>
              }
            />
            <Route
              path="sales/:id"
              element={
                <RoleGuard allow={ROUTE_ROLES.sales}>
                  <SaleDetailPage />
                </RoleGuard>
              }
            />
            <Route
              path="purchases"
              element={
                <RoleGuard allow={ROUTE_ROLES.purchases}>
                  <PurchasesPage />
                </RoleGuard>
              }
            />
            <Route
              path="purchases/new"
              element={
                <RoleGuard allow={ROUTE_ROLES.purchases}>
                  <PurchaseCreatePage />
                </RoleGuard>
              }
            />
            <Route
              path="purchases/:id"
              element={
                <RoleGuard allow={ROUTE_ROLES.purchases}>
                  <PurchaseDetailPage />
                </RoleGuard>
              }
            />
            <Route
              path="inventory"
              element={
                <RoleGuard allow={ROUTE_ROLES.inventory}>
                  <InventoryPage />
                </RoleGuard>
              }
            />
            <Route
              path="inventory/:productId/movements"
              element={
                <RoleGuard allow={ROUTE_ROLES.inventory}>
                  <ProductMovementsPage />
                </RoleGuard>
              }
            />

            <Route
              path="accounts"
              element={
                <AccountsGuard>
                  <AccountsLayout />
                </AccountsGuard>
              }
            >
              <Route index element={<ChartOfAccountsPage />} />
              <Route path="journals" element={<JournalsPage />} />
              <Route path="trial-balance" element={<TrialBalancePage />} />
              <Route path="profit-loss" element={<ProfitLossPage />} />
              <Route
                path="receivables"
                element={<PartyBalancesPage kind="receivables" />}
              />
              <Route
                path="payables"
                element={<PartyBalancesPage kind="payables" />}
              />
              <Route path="ledger/:accountId" element={<AccountLedgerPage />} />
            </Route>
          </Route>
        </Route>

        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  )
}
