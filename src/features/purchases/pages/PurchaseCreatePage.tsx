import { Link, Navigate, useNavigate } from 'react-router-dom'
import { useFieldArray, useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { Button } from '@/components/ui/button'
import { DatePicker } from '@/components/ui/date-picker'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { useRole } from '@/features/auth'
import {
  useCreatePurchaseMutation,
  useSuppliersQuery,
} from '@/features/purchases/api'
import { PurchaseLineRows } from '@/features/purchases/components/PurchaseLineRows'
import { PurchaseTotals } from '@/features/purchases/components/PurchaseTotals'
import {
  calcPurchaseTotals,
  purchaseFormSchema,
  type PurchaseFormValues,
} from '@/features/purchases/schemas'

function todayIso() {
  return new Date().toISOString().slice(0, 10)
}

export function PurchaseCreatePage() {
  const navigate = useNavigate()
  const { hasRole, isLoading } = useRole()
  const suppliers = useSuppliersQuery()
  const create = useCreatePurchaseMutation()

  const {
    register,
    control,
    handleSubmit,
    watch,
    setValue,
    formState: { errors },
  } = useForm<PurchaseFormValues>({
    resolver: zodResolver(purchaseFormSchema),
    defaultValues: {
      supplier_id: '',
      doc_date: todayIso(),
      discount: 0,
      amount_paid: 0,
      items: [],
    },
  })

  const { fields, append, remove } = useFieldArray({
    control,
    name: 'items',
  })

  const items = watch('items')
  const discount = watch('discount')
  const amountPaid = watch('amount_paid')
  const totals = calcPurchaseTotals(
    items ?? [],
    Number.isFinite(discount) ? discount : 0,
    Number.isFinite(amountPaid) ? amountPaid : 0,
  )

  const onSubmit = handleSubmit(async (values) => {
    try {
      const id = await create.mutateAsync(values)
      navigate(`/purchases/${id}`)
    } catch {
      // error shown from mutation
    }
  })

  if (!isLoading && !hasRole('purchase')) {
    return <Navigate to="/purchases" replace />
  }

  return (
    <div className="mx-auto max-w-3xl space-y-4">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">New purchase</h1>
          <p className="text-sm text-muted-foreground">
            Posts stock, moving average, and journal via RPC.
          </p>
        </div>
        <Button type="button" variant="outline" asChild>
          <Link to="/purchases">Back</Link>
        </Button>
      </div>

      <form className="space-y-4" onSubmit={onSubmit} noValidate>
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="supplier_id">Supplier</Label>
            <select
              id="supplier_id"
              className="border-input bg-background h-8 w-full rounded-lg border px-2.5 text-sm"
              disabled={create.isPending}
              {...register('supplier_id')}
            >
              <option value="">Select supplier…</option>
              {(suppliers.data ?? []).map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
            </select>
            {errors.supplier_id ? (
              <p className="text-xs text-destructive">
                {errors.supplier_id.message}
              </p>
            ) : null}
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="doc_date">Date</Label>
            <DatePicker
              id="doc_date"
              value={watch('doc_date')}
              disabled={create.isPending}
              onChange={(iso) =>
                setValue('doc_date', iso, { shouldValidate: true })
              }
            />
            {errors.doc_date ? (
              <p className="text-xs text-destructive">
                {errors.doc_date.message}
              </p>
            ) : null}
          </div>
        </div>

        <PurchaseLineRows
          fields={fields}
          register={register}
          watch={watch}
          append={append}
          remove={remove}
          disabled={create.isPending}
        />
        {errors.items?.message || errors.items?.root?.message ? (
          <p className="text-xs text-destructive">
            {errors.items.message ?? errors.items.root?.message}
          </p>
        ) : null}

        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-3">
            <div className="space-y-1.5">
              <Label htmlFor="discount">Discount</Label>
              <Input
                id="discount"
                type="number"
                step="0.01"
                min="0"
                disabled={create.isPending}
                {...register('discount', { valueAsNumber: true })}
              />
              {errors.discount ? (
                <p className="text-xs text-destructive">
                  {errors.discount.message}
                </p>
              ) : null}
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="amount_paid">Paid now</Label>
              <Input
                id="amount_paid"
                type="number"
                step="0.01"
                min="0"
                disabled={create.isPending}
                {...register('amount_paid', { valueAsNumber: true })}
              />
              {errors.amount_paid ? (
                <p className="text-xs text-destructive">
                  {errors.amount_paid.message}
                </p>
              ) : null}
            </div>
          </div>

          <PurchaseTotals
            subtotal={totals.subtotal}
            discount={Number.isFinite(discount) ? discount : 0}
            total={totals.total}
            paid={Number.isFinite(amountPaid) ? amountPaid : 0}
            due={totals.due}
          />
        </div>

        {create.isError ? (
          <p className="rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">
            {create.error instanceof Error
              ? create.error.message
              : 'Failed to create purchase'}
          </p>
        ) : null}

        <div className="flex justify-end gap-2">
          <Button
            type="button"
            variant="outline"
            disabled={create.isPending}
            asChild
          >
            <Link to="/purchases">Cancel</Link>
          </Button>
          <Button type="submit" disabled={create.isPending}>
            {create.isPending ? 'Posting…' : 'Post purchase'}
          </Button>
        </div>
      </form>
    </div>
  )
}
