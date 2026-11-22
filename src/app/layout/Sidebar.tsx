import { NavLink } from 'react-router-dom'
import {
  LayoutDashboard,
  ShoppingCart,
  Truck,
  Warehouse,
  BookOpen,
  type LucideIcon,
} from 'lucide-react'
import { cn } from '@/lib/utils'

type NavItem = {
  to: string
  label: string
  icon: LucideIcon
  end?: boolean
}

const navItems: NavItem[] = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard, end: true },
  { to: '/sales', label: 'Sales', icon: ShoppingCart },
  { to: '/purchases', label: 'Purchases', icon: Truck },
  { to: '/inventory', label: 'Inventory', icon: Warehouse },
  { to: '/accounts', label: 'Accounts', icon: BookOpen },
]

export function Sidebar() {
  return (
    <aside className="flex h-full w-56 shrink-0 flex-col border-r border-sidebar-border bg-sidebar text-sidebar-foreground">
      <div className="flex h-14 items-center border-b border-sidebar-border px-4">
        <span className="text-sm font-semibold tracking-tight">Mini ERP</span>
      </div>
      <nav className="flex flex-1 flex-col gap-1 p-2">
        {navItems.map(({ to, label, icon: Icon, end }) => (
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
        ))}
      </nav>
    </aside>
  )
}
