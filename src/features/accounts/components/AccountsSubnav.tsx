import { NavLink } from 'react-router-dom'
import { cn } from '@/lib/utils'

const links = [
  { to: '/accounts', label: 'Chart', end: true },
  { to: '/accounts/journals', label: 'Journals' },
  { to: '/accounts/trial-balance', label: 'Trial balance' },
  { to: '/accounts/profit-loss', label: 'P&L' },
  { to: '/accounts/receivables', label: 'Receivables' },
  { to: '/accounts/payables', label: 'Payables' },
] as const

export function AccountsSubnav() {
  return (
    <nav className="flex flex-wrap gap-1 border-b pb-2">
      {links.map((link) => (
        <NavLink
          key={link.to}
          to={link.to}
          end={'end' in link ? link.end : false}
          className={({ isActive }) =>
            cn(
              'rounded-md px-2.5 py-1.5 text-sm transition-colors',
              isActive
                ? 'bg-muted font-medium text-foreground'
                : 'text-muted-foreground hover:bg-muted/60 hover:text-foreground',
            )
          }
        >
          {link.label}
        </NavLink>
      ))}
    </nav>
  )
}
