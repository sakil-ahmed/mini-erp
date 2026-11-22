import { Button } from '@/components/ui/button'
import { totalPages } from '@/shared/lib/pagination'

type PaginationBarProps = {
  page: number
  total: number
  pageSize?: number
  onPageChange: (page: number) => void
}

export function PaginationBar({
  page,
  total,
  pageSize,
  onPageChange,
}: PaginationBarProps) {
  const pages = totalPages(total, pageSize)

  return (
    <div className="flex items-center justify-between gap-3 text-sm text-muted-foreground">
      <span>
        {total} total · page {page} of {pages}
      </span>
      <div className="flex gap-2">
        <Button
          type="button"
          variant="outline"
          size="sm"
          disabled={page <= 1}
          onClick={() => onPageChange(page - 1)}
        >
          Previous
        </Button>
        <Button
          type="button"
          variant="outline"
          size="sm"
          disabled={page >= pages}
          onClick={() => onPageChange(page + 1)}
        >
          Next
        </Button>
      </div>
    </div>
  )
}
