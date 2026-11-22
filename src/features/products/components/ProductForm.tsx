import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import {
  productFormSchema,
  type ProductFormValues,
} from '@/features/products/schemas'
import type { Product } from '@/features/products/types'

type ProductFormProps = {
  initial?: Product | null
  submitting?: boolean
  error?: string | null
  onSubmit: (values: ProductFormValues) => void
  onCancel: () => void
}

export function ProductForm({
  initial,
  submitting,
  error,
  onSubmit,
  onCancel,
}: ProductFormProps) {
  const {
    register,
    handleSubmit,
    setValue,
    watch,
    formState: { errors },
  } = useForm<ProductFormValues>({
    resolver: zodResolver(productFormSchema),
    defaultValues: {
      sku: initial?.sku ?? '',
      name: initial?.name ?? '',
      unit: initial?.unit ?? 'ea',
      sale_price: initial?.sale_price ?? 0,
      reorder_level: initial?.reorder_level ?? 0,
      is_active: initial?.is_active ?? true,
    },
  })

  const isActive = watch('is_active')

  return (
    <form className="space-y-4" onSubmit={handleSubmit(onSubmit)} noValidate>
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="space-y-1.5">
          <Label htmlFor="sku">SKU</Label>
          <Input id="sku" disabled={submitting} {...register('sku')} />
          {errors.sku ? (
            <p className="text-xs text-destructive">{errors.sku.message}</p>
          ) : null}
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="unit">Unit</Label>
          <Input id="unit" disabled={submitting} {...register('unit')} />
          {errors.unit ? (
            <p className="text-xs text-destructive">{errors.unit.message}</p>
          ) : null}
        </div>
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="name">Name</Label>
        <Input id="name" disabled={submitting} {...register('name')} />
        {errors.name ? (
          <p className="text-xs text-destructive">{errors.name.message}</p>
        ) : null}
      </div>

      <div className="grid gap-3 sm:grid-cols-2">
        <div className="space-y-1.5">
          <Label htmlFor="sale_price">Sale price</Label>
          <Input
            id="sale_price"
            type="number"
            step="0.01"
            disabled={submitting}
            {...register('sale_price', { valueAsNumber: true })}
          />
          {errors.sale_price ? (
            <p className="text-xs text-destructive">
              {errors.sale_price.message}
            </p>
          ) : null}
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="reorder_level">Reorder level</Label>
          <Input
            id="reorder_level"
            type="number"
            step="0.001"
            disabled={submitting}
            {...register('reorder_level', { valueAsNumber: true })}
          />
          {errors.reorder_level ? (
            <p className="text-xs text-destructive">
              {errors.reorder_level.message}
            </p>
          ) : null}
        </div>
      </div>

      <div className="flex items-center justify-between rounded-lg border px-3 py-2">
        <Label htmlFor="is_active">Active</Label>
        <Switch
          id="is_active"
          checked={isActive}
          disabled={submitting}
          onCheckedChange={(v) => setValue('is_active', v)}
        />
      </div>

      {error ? (
        <p className="rounded-md bg-destructive/10 px-3 py-2 text-xs text-destructive">
          {error}
        </p>
      ) : null}

      <div className="flex justify-end gap-2">
        <Button
          type="button"
          variant="outline"
          disabled={submitting}
          onClick={onCancel}
        >
          Cancel
        </Button>
        <Button type="submit" disabled={submitting}>
          {submitting ? 'Saving…' : 'Save'}
        </Button>
      </div>
    </form>
  )
}
