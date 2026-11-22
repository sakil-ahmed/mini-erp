# Mini ERP

Vite + React 18 + TypeScript (strict) scaffold for Sales, Purchase, Inventory, and Accounts.

## Stack

- Vite, React 18, TypeScript strict, Tailwind CSS, shadcn/ui
- TanStack Query, react-router, react-hook-form + zod
- Supabase (`@supabase/supabase-js`) — Auth, Postgres, RLS (schema later)

## Setup

```bash
cp .env.example .env
# Fill VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY
npm install
npm run dev
```

`VITE_AUTH_BYPASS=true` skips the protected-route session check so you can preview the shell before Auth is wired.

## Structure

```
src/app          # shell, router, providers, layout
src/lib          # supabase client, utils
src/shared       # cross-feature UI helpers
src/features/*   # auth, products, parties, purchases, sales, inventory, accounts, dashboard
supabase/migrations
```
