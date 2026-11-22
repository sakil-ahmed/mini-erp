import { NavLink } from 'react-router-dom'
import {
  LayoutDashboard,
  ShoppingCart,
  Truck,
  Warehouse,
  BookOpen,
  LogOut,
  type LucideIcon,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { useAuth, useRole, ROUTE_ROLES, type AppRole } from '@/features/auth'

type NavItem = {
  to: string
  label: string
  icon: LucideIcon
  roles: readonly AppRole[]
  end?: boolean
}

const navItems: NavItem[] = [
  {
    to: '/',
    label: 'Dashboard',
    icon: LayoutDashboard,
    roles: ROUTE_ROLES.dashboard,
    end: true,
  },
  { to: '/sales', label: 'Sales', icon: ShoppingCart, roles: ROUTE_ROLES.sales },
  {
    to: '/purchases',
    label: 'Purchases',
    icon: Truck,
    roles: ROUTE_ROLES.purchases,
  },
  {
    to: '/inventory',
    label: 'Inventory',
    icon: Warehouse,
    roles: ROUTE_ROLES.inventory,
  },
  {
    to: '/accounts',
    label: 'Accounts',
    icon: BookOpen,
    roles: ROUTE_ROLES.accounts,
  },
]

export function Sidebar() {
  const { profile, signOut } = useAuth()
  const { canAccess, role, isLoading } = useRole()

  const visibleItems = navItems.filter((item) => canAccess(item.roles))

  return (
    <aside className="flex h-full w-56 shrink-0 flex-col border-r border-sidebar-border bg-sidebar text-sidebar-foreground">
      <div className="flex h-14 items-center border-b border-sidebar-border px-4">
        <span className="text-sm font-semibold tracking-tight">Mini ERP</span>
      </div>

      <nav className="flex flex-1 flex-col gap-1 p-2">
        {isLoading ? (
          <p className="px-3 py-2 text-xs text-muted-foreground">Loading…</p>
        ) : (
          visibleItems.map(({ to, label, icon: Icon, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              className={({ isActive }) =>
                cn(
                  'flex items-center gap-2 rounded-lg px-3 py-2 text-sm transition-colors',
                  isActive
                    ? 'bg-sidebar-accent font-medium text-sidebar-accent-foreground'
                    : 'text-sidebar-foreground/80 hover:bg-sidebar-accent/60 hover:text-sidebar-accent-foreground',
                )
              }
            >
              <Icon className="size-4 shrink-0" />
              {label}
            </NavLink>
          ))
        )}
      </nav>

      <div className="space-y-2 border-t border-sidebar-border p-3">
        <div className="px-1">
          <p className="truncate text-xs font-medium">
            {profile?.full_name ?? 'Signed in'}
          </p>
          <p className="truncate text-[11px] text-muted-foreground capitalize">
            {role ?? '…'}
          </p>
        </div>
        <Button
          type="button"
          variant="outline"
          size="sm"
          className="w-full justify-start gap-2"
          onClick={() => {
            void signOut()
          }}
        >
          <LogOut className="size-3.5" />
          Sign out
        </Button>
      </div>
    </aside>
  )
}
