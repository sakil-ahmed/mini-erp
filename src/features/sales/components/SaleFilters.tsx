import { DatePicker } from '@/components/ui/date-picker'
import { Label } from '@/components/ui/label'
import type { CustomerOption, DocStatus } from '@/features/sales/types'

type SaleFiltersProps = {
  dateFrom: string
  dateTo: string
  customerId: string
  status: '' | DocStatus
  customers: CustomerOption[]
  onChange: (patch: {
    dateFrom?: string
    dateTo?: string
    customerId?: string
    status?: '' | DocStatus
  }) => void
}

export function SaleFilters({
  dateFrom,
  dateTo,
  customerId,
  status,
  customers,
  onChange,
}: SaleFiltersProps) {
  return (
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
      <div className="space-y-1.5">
        <Label htmlFor="sale-from">From</Label>
        <DatePicker
          id="sale-from"
          value={dateFrom}
          clearable
          placeholder="Any date"
          onChange={(iso) => onChange({ dateFrom: iso })}
        />
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="sale-to">To</Label>
        <DatePicker
          id="sale-to"
          value={dateTo}
          clearable
          placeholder="Any date"
          onChange={(iso) => onChange({ dateTo: iso })}
        />
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="sale-customer">Customer</Label>
        <select
          id="sale-customer"
          className="border-input bg-background h-8 w-full rounded-lg border px-2.5 text-sm"
          value={customerId}
          onChange={(e) => onChange({ customerId: e.target.value })}
        >
          <option value="">All customers</option>
          {customers.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </select>
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="sale-status">Status</Label>
        <select
          id="sale-status"
          className="border-input bg-background h-8 w-full rounded-lg border px-2.5 text-sm"
          value={status}
          onChange={(e) =>
            onChange({ status: e.target.value as '' | DocStatus })
          }
        >
          <option value="">All statuses</option>
          <option value="posted">Posted</option>
          <option value="void">Void</option>
        </select>
      </div>
    </div>
  )
}
