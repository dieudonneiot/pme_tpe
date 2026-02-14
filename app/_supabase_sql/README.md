# Supabase SQL (local scratchpad)

This folder is **ignored by Git** (except this README + `.gitkeep`), so you can drop any `.sql` scripts here for manual execution in Supabase without committing them.

## Business categories (DB-driven)

Use `business_categories.sql` (or copy/paste the SQL below) in Supabase SQL Editor (or via `psql`) to add real categories for businesses.

```sql
-- Required for gen_random_uuid()
create extension if not exists pgcrypto;

-- 1) Categories table
create table if not exists public.business_categories (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

-- 2) Add FK column on businesses (single "primary" category)
alter table public.businesses
  add column if not exists business_category_id uuid null;

alter table public.businesses
  add constraint if not exists businesses_business_category_fk
  foreign key (business_category_id)
  references public.business_categories (id)
  on delete set null;

create index if not exists businesses_business_category_id_idx
  on public.businesses (business_category_id);

-- 3) RLS: categories are safe to be publicly readable
alter table public.business_categories enable row level security;

drop policy if exists "Public read business categories" on public.business_categories;
create policy "Public read business categories"
  on public.business_categories
  for select
  using (true);

-- Optional: allow authenticated users to manage categories (adjust as needed)
drop policy if exists "Authenticated manage business categories" on public.business_categories;
create policy "Authenticated manage business categories"
  on public.business_categories
  for all
  to authenticated
  using (true)
  with check (true);

-- 4) Seed examples (edit to your needs)
insert into public.business_categories (slug, name, sort_order)
values
  ('beaute', 'Beauté', 10),
  ('restauration', 'Restauration', 20),
  ('btp', 'BTP', 30),
  ('transport', 'Transport', 40),
  ('commerce', 'Commerce', 50),
  ('sante', 'Santé', 60),
  ('education', 'Éducation', 70),
  ('tech', 'Tech', 80)
on conflict (slug) do nothing;
```

Notes:
- The app uses `businesses.business_category_id` to filter and show categories on `/explore`, and in the business settings page.
- If you later want **multiple** categories per business, we can switch to a mapping table (`business_categories_map`) instead of a single FK column.

## Extracted reference (local)

If you keep a long “all-in-one” schema / SQL history file (like `docs/Summary_Of_All_done.txt`), you can extract useful slices into this folder so you don’t have to scroll/search every time.

Local files created from `docs/Summary_Of_All_done.txt`:
- `app/_supabase_sql/schema_349-882_from_Summary_Of_All_done.txt`
- `app/_supabase_sql/sql_904-6381_from_Summary_Of_All_done.sql`
- `app/_supabase_sql/EXTRACTED_FROM_Summary_Of_All_done.md`

Reminder: everything in `_supabase_sql/` is ignored by Git except this README + `.gitkeep`.
