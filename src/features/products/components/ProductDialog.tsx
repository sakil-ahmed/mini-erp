import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { ProductForm } from '@/features/products/components/ProductForm'
import type { ProductFormValues } from '@/features/products/schemas'
import type { Product } from '@/features/products/types'

type ProductDialogProps = {
  open: boolean
  product: Product | null
  submitting?: boolean
  error?: string | null
  onOpenChange: (open: boolean) => void
  onSubmit: (values: ProductFormValues) => void
}

export function ProductDialog({
  open,
  product,
  submitting,
  error,
  onOpenChange,
  onSubmit,
}: ProductDialogProps) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{product ? 'Edit product' : 'New product'}</DialogTitle>
        </DialogHeader>
        <ProductForm
          key={product?.id ?? 'new'}
          initial={product}
          submitting={submitting}
          error={error}
          onSubmit={onSubmit}
          onCancel={() => onOpenChange(false)}
        />
      </DialogContent>
    </Dialog>
  )
}
