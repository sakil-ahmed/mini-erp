import { Link, Navigate, useNavigate } from 'react-router-dom'
import { useFieldArray, useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { Button } from '@/components/ui/button'
import { DatePicker } from '@/components/ui/date-picker'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { useRole } from '@/features/auth'
import {
  useCreateSaleMutation,
  useCustomersQuery,
} from '@/features/sales/api'
import { SaleLineRows } from '@/features/sales/components/SaleLineRows'
import { SaleTotals } from '@/features/sales/components/SaleTotals'
import {
  calcSaleTotals,
  saleFormSchema,
  type SaleFormValues,
} from '@/features/sales/schemas'

function todayIso() {
  return new Date().toISOString().slice(0, 10)
}

export function SaleCreatePage() {
  const navigate = useNavigate()
  const { hasRole, isLoading } = useRole()
  const customers = useCustomersQuery()
  const create = useCreateSaleMutation()

  const {
    register,
    control,
    handleSubmit,
    watch,
    setValue,
    formState: { errors },
  } = useForm<SaleFormValues>({
    resolver: zodResolver(saleFormSchema),
    defaultValues: {
      customer_id: '',
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
  const totals = calcSaleTotals(
    items ?? [],
    Number.isFinite(discount) ? discount : 0,
    Number.isFinite(amountPaid) ? amountPaid : 0,
  )

  const onSubmit = handleSubmit(async (values) => {
    try {
      const id = await create.mutateAsync(values)
      navigate(`/sales/${id}`)
    } catch {
      // mutation error UI
    }
  })

  if (!isLoading && !hasRole('sales')) {
    return <Navigate to="/sales" replace />
  }

  return (
    <div className="mx-auto max-w-3xl space-y-4">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">New sale</h1>
          <p className="text-sm text-muted-foreground">
            Qty cannot exceed on-hand stock (DB still enforces).
          </p>
        </div>
        <Button type="button" variant="outline" asChild>
          <Link to="/sales">Back</Link>
        </Button>
      </div>

      <form className="space-y-4" onSubmit={onSubmit} noValidate>
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="customer_id">Customer</Label>
            <select
              id="customer_id"
              className="border-input bg-background h-8 w-full rounded-lg border px-2.5 text-sm"
              disabled={create.isPending}
              {...register('customer_id')}
            >
              <option value="">Select customer…</option>
              {(customers.data ?? []).map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
            {errors.customer_id ? (
              <p className="text-xs text-destructive">
                {errors.customer_id.message}
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

        <SaleLineRows
          fields={fields}
          register={register}
          watch={watch}
          setValue={setValue}
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

          <SaleTotals
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
              : 'Failed to create sale'}
          </p>
        ) : null}

        <div className="flex justify-end gap-2">
          <Button
            type="button"
            variant="outline"
            disabled={create.isPending}
            asChild
          >
            <Link to="/sales">Cancel</Link>
          </Button>
          <Button type="submit" disabled={create.isPending}>
            {create.isPending ? 'Posting…' : 'Post sale'}
          </Button>
        </div>
      </form>
    </div>
  )
}
