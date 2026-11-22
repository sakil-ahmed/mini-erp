import { Outlet } from 'react-router-dom'
import { Sidebar } from './Sidebar'

export function AppLayout() {
  return (
    <div className="flex h-svh overflow-hidden bg-background text-foreground">
      <Sidebar />
      <main className="min-h-0 min-w-0 flex-1 overflow-y-auto p-6">
        <div className="mx-auto w-full max-w-7xl">
          <Outlet />
        </div>
      </main>
    </div>
  )
}
