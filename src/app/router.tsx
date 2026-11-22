import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { AppLayout } from '@/app/layout/AppLayout'
import {
  LoginPage,
  ProtectedRoute,
  RoleGuard,
  ROUTE_ROLES,
} from '@/features/auth'
import { DashboardPage } from '@/features/dashboard/pages/DashboardPage'
import { SalesPage } from '@/features/sales/pages/SalesPage'
import { PurchasesPage } from '@/features/purchases/pages/PurchasesPage'
import { InventoryPage } from '@/features/inventory/pages/InventoryPage'
import { AccountsPage } from '@/features/accounts/pages/AccountsPage'

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
              path="sales"
              element={
                <RoleGuard allow={ROUTE_ROLES.sales}>
                  <SalesPage />
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
              path="inventory"
              element={
                <RoleGuard allow={ROUTE_ROLES.inventory}>
                  <InventoryPage />
                </RoleGuard>
              }
            />
            <Route
              path="accounts"
              element={
                <RoleGuard allow={ROUTE_ROLES.accounts}>
                  <AccountsPage />
                </RoleGuard>
              }
            />
          </Route>
        </Route>

        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  )
}
