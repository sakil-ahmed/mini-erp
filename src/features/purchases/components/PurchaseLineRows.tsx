import type {
  FieldArrayWithId,
  UseFieldArrayAppend,
  UseFieldArrayRemove,
  UseFormRegister,
  UseFormWatch,
} from 'react-hook-form'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { ProductSearchField } from '@/features/purchases/components/ProductSearchField'
import {
  roundMoney,
  type PurchaseFormValues,
  type PurchaseLineValues,
} from '@/features/purchases/schemas'
import { formatMoney } from '@/shared/lib/money'

type PurchaseLineRowsProps = {
  fields: FieldArrayWithId<PurchaseFormValues, 'items', 'id'>[]
  register: UseFormRegister<PurchaseFormValues>
  watch: UseFormWatch<PurchaseFormValues>
  append: UseFieldArrayAppend<PurchaseFormValues, 'items'>
  remove: UseFieldArrayRemove
  disabled?: boolean
}

export function PurchaseLineRows({
  fields,
  register,
  watch,
  append,
  remove,
  disabled,
}: PurchaseLineRowsProps) {
  const items = watch('items')

  return (
    <div className="space-y-3">
      <ProductSearchField
        label="Add product"
        disabled={disabled}
        onSelect={(product) => {
          const line: PurchaseLineValues = {
            product_id: product.id,
            product_label: `${product.sku} · ${product.name}`,
            qty: 1,
            unit_cost: product.avg_cost,
          }
          append(line)
        }}
      />

      {fields.length === 0 ? (
        <p className="rounded-lg border border-dashed p-4 text-sm text-muted-foreground">
          Search and select products to add lines.
        </p>
      ) : (
        <div className="space-y-2">
          {fields.map((field, index) => {
            const qty = items?.[index]?.qty ?? 0
            const cost = items?.[index]?.unit_cost ?? 0
            const lineTotal = roundMoney(
              (Number.isFinite(qty) ? qty : 0) *
                (Number.isFinite(cost) ? cost : 0),
            )

            return (
              <div
                key={field.id}
                className="grid gap-2 rounded-lg border p-3 sm:grid-cols-[1fr_6rem_7rem_6rem_auto]"
              >
                <div className="text-sm">
                  <p className="font-medium">
                    {items?.[index]?.product_label || field.product_label}
                  </p>
                  <input
                    type="hidden"
                    {...register(`items.${index}.product_id`)}
                  />
                  <input
                    type="hidden"
                    {...register(`items.${index}.product_label`)}
                  />
                </div>
                <Input
                  type="number"
                  step="0.001"
                  min="0"
                  disabled={disabled}
                  aria-label="Quantity"
                  {...register(`items.${index}.qty`, { valueAsNumber: true })}
                />
                <Input
                  type="number"
                  step="0.01"
                  min="0"
                  disabled={disabled}
                  aria-label="Unit cost"
                  {...register(`items.${index}.unit_cost`, {
                    valueAsNumber: true,
                  })}
                />
                <div className="flex items-center justify-end text-sm font-medium">
                  {formatMoney(lineTotal)}
                </div>
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  disabled={disabled}
                  onClick={() => remove(index)}
                >
                  Remove
                </Button>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
