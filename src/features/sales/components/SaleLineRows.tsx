import type {
  FieldArrayWithId,
  UseFieldArrayAppend,
  UseFieldArrayRemove,
  UseFormRegister,
  UseFormSetValue,
  UseFormWatch,
} from 'react-hook-form'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { SaleProductSearch } from '@/features/sales/components/SaleProductSearch'
import {
  roundMoney,
  type SaleFormValues,
  type SaleLineValues,
} from '@/features/sales/schemas'
import { formatMoney, formatQty } from '@/shared/lib/money'

type SaleLineRowsProps = {
  fields: FieldArrayWithId<SaleFormValues, 'items', 'id'>[]
  register: UseFormRegister<SaleFormValues>
  watch: UseFormWatch<SaleFormValues>
  setValue: UseFormSetValue<SaleFormValues>
  append: UseFieldArrayAppend<SaleFormValues, 'items'>
  remove: UseFieldArrayRemove
  disabled?: boolean
}

export function SaleLineRows({
  fields,
  register,
  watch,
  setValue,
  append,
  remove,
  disabled,
}: SaleLineRowsProps) {
  const items = watch('items')

  return (
    <div className="space-y-3">
      <SaleProductSearch
        disabled={disabled}
        onSelect={(product) => {
          const line: SaleLineValues = {
            product_id: product.id,
            product_label: `${product.sku} · ${product.name}`,
            stock_qty: product.stock_qty,
            qty: Math.min(1, product.stock_qty),
            unit_price: product.sale_price,
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
            const price = items?.[index]?.unit_price ?? 0
            const stock = items?.[index]?.stock_qty ?? field.stock_qty
            const lineTotal = roundMoney(
              (Number.isFinite(qty) ? qty : 0) *
                (Number.isFinite(price) ? price : 0),
            )
            const overStock =
              Number.isFinite(qty) && Number.isFinite(stock) && qty > stock

            const qtyReg = register(`items.${index}.qty`, {
              valueAsNumber: true,
            })

            return (
              <div
                key={field.id}
                className="grid gap-2 rounded-lg border p-3 sm:grid-cols-[1fr_5.5rem_5.5rem_7rem_6rem_auto]"
              >
                <div className="text-sm">
                  <p className="font-medium">
                    {items?.[index]?.product_label || field.product_label}
                  </p>
                  <p className="text-xs text-muted-foreground">
                    In stock: {formatQty(stock)}
                  </p>
                  <input
                    type="hidden"
                    {...register(`items.${index}.product_id`)}
                  />
                  <input
                    type="hidden"
                    {...register(`items.${index}.product_label`)}
                  />
                  <input
                    type="hidden"
                    {...register(`items.${index}.stock_qty`, {
                      valueAsNumber: true,
                    })}
                  />
                </div>
                <Input
                  type="number"
                  step="0.001"
                  min="0"
                  max={stock}
                  disabled={disabled}
                  aria-label="Quantity"
                  className={overStock ? 'border-destructive' : undefined}
                  name={qtyReg.name}
                  ref={qtyReg.ref}
                  onBlur={qtyReg.onBlur}
                  onChange={(e) => {
                    void qtyReg.onChange(e)
                    const next = Number(e.target.value)
                    if (Number.isFinite(next) && next > stock) {
                      setValue(`items.${index}.qty`, stock, {
                        shouldValidate: true,
                        shouldDirty: true,
                      })
                    }
                  }}
                />
                <div className="flex items-center text-xs text-muted-foreground">
                  max {formatQty(stock)}
                </div>
                <Input
                  type="number"
                  step="0.01"
                  min="0"
                  disabled={disabled}
                  aria-label="Unit price"
                  {...register(`items.${index}.unit_price`, {
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
                {overStock ? (
                  <p className="text-xs text-destructive sm:col-span-full">
                    Quantity cannot exceed stock ({formatQty(stock)}).
                  </p>
                ) : null}
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
