import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { useRole } from '@/features/auth'
import { PartyKindPanel } from '@/features/parties/components/PartyKindPanel'
import type { PartyKind } from '@/features/parties/types'

export function PartiesPage() {
  const { role, isAdmin } = useRole()

  const showCustomers = isAdmin || role === 'sales' || role === 'accountant'
  const showSuppliers = isAdmin || role === 'purchase' || role === 'accountant'
  const defaultTab: PartyKind = showCustomers ? 'customer' : 'supplier'

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Parties</h1>
        <p className="text-sm text-muted-foreground">
          Customers and suppliers — soft deactivate instead of delete.
        </p>
      </div>

      {!showCustomers && !showSuppliers ? (
        <p className="text-sm text-muted-foreground">No party access for this role.</p>
      ) : (
        <Tabs defaultValue={defaultTab}>
          <TabsList>
            {showCustomers ? (
              <TabsTrigger value="customer">Customers</TabsTrigger>
            ) : null}
            {showSuppliers ? (
              <TabsTrigger value="supplier">Suppliers</TabsTrigger>
            ) : null}
          </TabsList>

          {showCustomers ? (
            <TabsContent value="customer" className="mt-4">
              <PartyKindPanel kind="customer" canWrite={isAdmin} />
            </TabsContent>
          ) : null}

          {showSuppliers ? (
            <TabsContent value="supplier" className="mt-4">
              <PartyKindPanel kind="supplier" canWrite={isAdmin} />
            </TabsContent>
          ) : null}
        </Tabs>
      )}
    </div>
  )
}
