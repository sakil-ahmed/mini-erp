/** Turn PostgREST / Postgres RPC errors into short UI messages. */
export function friendlyRpcError(err: unknown): string {
  const raw =
    err instanceof Error
      ? err.message
      : typeof err === 'string'
        ? err
        : 'Something went wrong'

  const message = raw.replace(/^.*error:\s*/i, '').trim()

  if (/permission denied/i.test(message)) {
    return 'You do not have permission to perform this action.'
  }
  if (/not authenticated/i.test(message)) {
    return 'Please sign in again and retry.'
  }
  if (/insufficient stock/i.test(message)) {
    return message
  }
  if (/stock would go negative/i.test(message)) {
    return message
  }
  if (/already void/i.test(message)) {
    return 'This document is already voided.'
  }
  if (/paid.*cannot exceed total|overpayment/i.test(message)) {
    return message
  }
  if (/qty must be > 0/i.test(message)) {
    return 'Each line quantity must be greater than zero.'
  }
  if (/unit_cost must be >= 0/i.test(message)) {
    return 'Unit cost cannot be negative.'
  }
  if (/supplier .* not found|not an active supplier/i.test(message)) {
    return 'Choose an active supplier.'
  }
  if (/product .* not found or inactive/i.test(message)) {
    return 'One or more products are missing or inactive.'
  }
  if (/p_items must be a non-empty/i.test(message)) {
    return 'Add at least one purchase line.'
  }
  if (/discount.*cannot exceed|total must be > 0/i.test(message)) {
    return message
  }

  return message || 'Request failed. Please try again.'
}
