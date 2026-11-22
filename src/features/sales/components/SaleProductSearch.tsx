import { useEffect, useRef, useState } from 'react'
import { Input } from '@/components/ui/input'
import { useProductSearchQuery } from '@/features/sales/api'
import type { ProductOption } from '@/features/sales/types'
import { useDebouncedValue } from '@/shared/hooks/useDebouncedValue'
import { formatQty } from '@/shared/lib/money'

type SaleProductSearchProps = {
  disabled?: boolean
  onSelect: (product: ProductOption) => void
}

export function SaleProductSearch({
  disabled,
  onSelect,
}: SaleProductSearchProps) {
  const [open, setOpen] = useState(false)
  const [text, setText] = useState('')
  const debounced = useDebouncedValue(text, 250)
  const rootRef = useRef<HTMLDivElement>(null)
  const search = useProductSearchQuery(debounced, open)

  useEffect(() => {
    const onDocClick = (e: MouseEvent) => {
      if (!rootRef.current?.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', onDocClick)
    return () => document.removeEventListener('mousedown', onDocClick)
  }, [])

  return (
    <div ref={rootRef} className="relative space-y-1.5">
      <p className="text-sm font-medium">Add product</p>
      <Input
        value={text}
        disabled={disabled}
        placeholder="Search SKU or name…"
        onFocus={() => setOpen(true)}
        onChange={(e) => {
          setText(e.target.value)
          setOpen(true)
        }}
      />
      {open ? (
        <div className="absolute z-20 mt-1 max-h-48 w-full overflow-auto rounded-lg border bg-popover p-1 shadow-md">
          {search.isLoading ? (
            <p className="px-2 py-1.5 text-xs text-muted-foreground">
              Searching…
            </p>
          ) : (search.data?.length ?? 0) === 0 ? (
            <p className="px-2 py-1.5 text-xs text-muted-foreground">
              No products in stock
            </p>
          ) : (
            search.data?.map((p) => (
              <button
                key={p.id}
                type="button"
                className="flex w-full flex-col rounded-md px-2 py-1.5 text-left text-sm hover:bg-muted"
                onClick={() => {
                  onSelect(p)
                  setText('')
                  setOpen(false)
                }}
              >
                <span className="font-medium">
                  {p.sku} · {p.name}
                </span>
                <span className="text-xs text-muted-foreground">
                  stock {formatQty(p.stock_qty)} · price {p.sale_price.toFixed(2)}
                </span>
              </button>
            ))
          )}
        </div>
      ) : null}
    </div>
  )
}
