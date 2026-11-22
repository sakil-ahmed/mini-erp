import { DatePicker } from '@/components/ui/date-picker'
import { Label } from '@/components/ui/label'
import type { DocStatus, SupplierOption } from '@/features/purchases/types'

type PurchaseFiltersProps = {
  dateFrom: string
  dateTo: string
  supplierId: string
  status: '' | DocStatus
  suppliers: SupplierOption[]
  onChange: (patch: {
    dateFrom?: string
    dateTo?: string
    supplierId?: string
    status?: '' | DocStatus
  }) => void
}

export function PurchaseFilters({
  dateFrom,
  dateTo,
  supplierId,
  status,
  suppliers,
  onChange,
}: PurchaseFiltersProps) {
  return (
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
      <div className="space-y-1.5">
        <Label htmlFor="dateFrom">From</Label>
        <DatePicker
          id="dateFrom"
          value={dateFrom}
          clearable
          placeholder="Any date"
          onChange={(iso) => onChange({ dateFrom: iso })}
        />
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="dateTo">To</Label>
        <DatePicker
          id="dateTo"
          value={dateTo}
          clearable
          placeholder="Any date"
          onChange={(iso) => onChange({ dateTo: iso })}
        />
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="supplier">Supplier</Label>
        <select
          id="supplier"
          className="border-input bg-background h-8 w-full rounded-lg border px-2.5 text-sm"
          value={supplierId}
          onChange={(e) => onChange({ supplierId: e.target.value })}
        >
          <option value="">All suppliers</option>
          {suppliers.map((s) => (
            <option key={s.id} value={s.id}>
              {s.name}
            </option>
          ))}
        </select>
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="status">Status</Label>
        <select
          id="status"
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
