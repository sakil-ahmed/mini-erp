import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { AppLayout } from '@/app/layout/AppLayout'
import { ProtectedRoute } from '@/app/routes/ProtectedRoute'
import { LoginPage } from '@/features/auth/pages/LoginPage'
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
            <Route index element={<DashboardPage />} />
            <Route path="sales" element={<SalesPage />} />
            <Route path="purchases" element={<PurchasesPage />} />
            <Route path="inventory" element={<InventoryPage />} />
            <Route path="accounts" element={<AccountsPage />} />
          </Route>
        </Route>

        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  )
}
