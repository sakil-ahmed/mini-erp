type PlaceholderPageProps = {
  title: string
  description?: string
}

export function PlaceholderPage({
  title,
  description = 'Coming soon — no business logic yet.',
}: PlaceholderPageProps) {
  return (
    <div className="space-y-2">
      <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
      <p className="text-sm text-muted-foreground">{description}</p>
    </div>
  )
}
