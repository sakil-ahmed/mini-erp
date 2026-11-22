import { Input } from '@/components/ui/input'

type SearchFieldProps = {
  value: string
  onChange: (value: string) => void
  placeholder?: string
}

export function SearchField({
  value,
  onChange,
  placeholder = 'Search…',
}: SearchFieldProps) {
  return (
    <Input
      value={value}
      placeholder={placeholder}
      onChange={(e) => onChange(e.target.value)}
      className="max-w-xs"
    />
  )
}
