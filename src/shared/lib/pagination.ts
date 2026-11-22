export const PAGE_SIZE = 10

export type PageParams = {
  page: number
  search: string
}

export function pageRange(page: number, pageSize = PAGE_SIZE) {
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1
  return { from, to }
}

export function totalPages(total: number, pageSize = PAGE_SIZE) {
  return Math.max(1, Math.ceil(total / pageSize))
}
