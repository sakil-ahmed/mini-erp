# Demo users for Mini ERP

After migrations (including `0006_seed.sql`), four demo accounts exist with fixed UUIDs and roles.

| Email | Password | Role | User ID |
|---|---|---|---|
| `admin@mini-erp.local` | `password123` | `admin` | `11111111-1111-4111-8111-111111111111` |
| `sales@mini-erp.local` | `password123` | `sales` | `22222222-2222-4222-8222-222222222222` |
| `purchase@mini-erp.local` | `password123` | `purchase` | `33333333-3333-4333-8333-333333333333` |
| `accountant@mini-erp.local` | `password123` | `accountant` | `44444444-4444-4444-8444-444444444444` |

`0006_seed.sql` inserts these into `auth.users` and upserts `public.profiles` with the correct `role`.

## Option A — Local Supabase (`db reset`)

```bash
supabase start
supabase db reset   # applies 0001–0006, including demo users + sample docs
```

Sign in from the app with any email above and password `password123`.

## Option B — Create users via Dashboard / Auth UI

If you prefer not to insert into `auth.users` from SQL (e.g. hosted project):

1. In **Authentication → Users**, create each email with password `password123` (or your own).
2. Copy each user’s UUID from the dashboard.
3. Assign the profile role in SQL:

```sql
-- Replace <uuid> with the Auth user id from the dashboard
insert into public.profiles (id, full_name, role)
values
  ('<admin-uuid>', 'Demo Admin', 'admin'),
  ('<sales-uuid>', 'Demo Sales', 'sales'),
  ('<purchase-uuid>', 'Demo Purchase', 'purchase'),
  ('<accountant-uuid>', 'Demo Accountant', 'accountant')
on conflict (id) do update
  set full_name = excluded.full_name,
      role = excluded.role;
```

Note: signup already creates a `profiles` row via `handle_new_user` (default role `sales`). The upsert above is what sets the real demo roles.

## Option C — Supabase CLI Auth admin

```bash
supabase auth signup --email admin@mini-erp.local --password password123
# repeat for sales / purchase / accountant, then run the profiles upsert from Option B
```

## Verify roles

```sql
select p.id, u.email, p.full_name, p.role
from public.profiles p
join auth.users u on u.id = p.id
order by p.role;
```

## What the seed posts

- **10 products** (`SKU-001` … `SKU-010`)
- **3 suppliers**, **4 customers**
- Several `create_purchase` / `create_sale` / `record_payment` calls
- **`SKU-010` Thermal Paper Roll** ends low-stock (stock **2**, reorder level **50**)

## App env

Point `.env` at your project, then:

```bash
npm run dev
```

Log in as `admin@mini-erp.local` / `password123` to browse all modules.
