import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import {
  partyFormSchema,
  type PartyFormValues,
} from '@/features/parties/schemas'
import type { Party } from '@/features/parties/types'

type PartyFormProps = {
  initial?: Party | null
  submitting?: boolean
  error?: string | null
  onSubmit: (values: PartyFormValues) => void
  onCancel: () => void
}

export function PartyForm({
  initial,
  submitting,
  error,
  onSubmit,
  onCancel,
}: PartyFormProps) {
  const {
    register,
    handleSubmit,
    setValue,
    watch,
    formState: { errors },
  } = useForm<PartyFormValues>({
    resolver: zodResolver(partyFormSchema),
    defaultValues: {
      name: initial?.name ?? '',
      email: initial?.email ?? '',
      phone: initial?.phone ?? '',
      is_active: initial?.is_active ?? true,
    },
  })

  const isActive = watch('is_active')

  return (
    <form className="space-y-4" onSubmit={handleSubmit(onSubmit)} noValidate>
      <div className="space-y-1.5">
        <Label htmlFor="party-name">Name</Label>
        <Input id="party-name" disabled={submitting} {...register('name')} />
        {errors.name ? (
          <p className="text-xs text-destructive">{errors.name.message}</p>
        ) : null}
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="party-email">Email</Label>
        <Input
          id="party-email"
          type="email"
          disabled={submitting}
          {...register('email')}
        />
        {errors.email ? (
          <p className="text-xs text-destructive">{errors.email.message}</p>
        ) : null}
      </div>

      <div className="space-y-1.5">
        <Label htmlFor="party-phone">Phone</Label>
        <Input id="party-phone" disabled={submitting} {...register('phone')} />
        {errors.phone ? (
          <p className="text-xs text-destructive">{errors.phone.message}</p>
        ) : null}
      </div>

      <div className="flex items-center justify-between rounded-lg border px-3 py-2">
        <Label htmlFor="party-active">Active</Label>
        <Switch
          id="party-active"
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
