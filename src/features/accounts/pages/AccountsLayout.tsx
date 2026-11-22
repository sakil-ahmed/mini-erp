import { Outlet } from 'react-router-dom'
import { AccountsSubnav } from '@/features/accounts/components/AccountsSubnav'

export function AccountsLayout() {
  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Accounts</h1>
        <p className="text-sm text-muted-foreground">
          Chart, journals, and SQL-backed reports — read-only.
        </p>
      </div>
      <AccountsSubnav />
      <Outlet />
    </div>
  )
}
