# Supabase SQL (local scratchpad)

This folder is **ignored by Git** (except this README + `.gitkeep`), so you can drop any `.sql` scripts here for manual execution in Supabase without committing them.

## Business categories (DB-driven)

Use `business_categories.sql` (or copy/paste the SQL below) in Supabase SQL Editor (or via `psql`) to add real categories for businesses.

```sql
-- Required for gen_random_uuid()
create extension if not exists pgcrypto;

-- IMPORTANT
-- Your schema already contains a table named `public.business_categories`, but it is a *mapping table*
-- (business_id, category_id) referencing `public.categories`.
-- So we use `public.categories` as the category list, and store the "primary" category on `public.businesses`.

-- 1) Category list: ensure `public.categories` has the extra fields we want
alter table public.categories add column if not exists slug text;
alter table public.categories add column if not exists sort_order int not null default 0;

create unique index if not exists categories_slug_unique
  on public.categories (slug)
  where slug is not null;

-- 2) Add FK column on businesses (single "primary" category)
alter table public.businesses
  add column if not exists business_category_id uuid null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'businesses_business_category_fk'
      and conrelid = 'public.businesses'::regclass
  ) then
    alter table public.businesses
      add constraint businesses_business_category_fk
      foreign key (business_category_id)
      references public.categories (id)
      on delete set null;
  end if;
end $$;

create index if not exists businesses_business_category_id_idx
  on public.businesses (business_category_id);

-- 3) RLS: categories are safe to be publicly readable
alter table public.categories enable row level security;

drop policy if exists "Public read categories" on public.categories;
create policy "Public read categories"
  on public.categories
  for select
  using (true);

-- 4) Seed examples (edit to your needs)
insert into public.categories (name, slug, sort_order)
values
  ('Beauté', 'beaute', 10),
  ('Restauration', 'restauration', 20),
  ('BTP', 'btp', 30),
  ('Transport', 'transport', 40),
  ('Commerce', 'commerce', 50),
  ('Santé', 'sante', 60),
  ('Éducation', 'education', 70),
  ('Tech', 'tech', 80)
on conflict (name) do update
set
  slug = excluded.slug,
  sort_order = excluded.sort_order;
```

Notes:
- The app uses `businesses.business_category_id` to filter and show categories on `/explore`, and in the business settings page.
- Your existing `public.business_categories` mapping table can still be used later if you want multiple categories per business.

## Extracted reference (local)

If you keep a long “all-in-one” schema / SQL history file (like `docs/Summary_Of_All_done.txt`), you can extract useful slices into this folder so you don’t have to scroll/search every time.

Local files created from `docs/Summary_Of_All_done.txt`:
- `app/_supabase_sql/schema_349-882_from_Summary_Of_All_done.txt`
- `app/_supabase_sql/sql_904-6381_from_Summary_Of_All_done.sql`
- `app/_supabase_sql/EXTRACTED_FROM_Summary_Of_All_done.md`

Reminder: everything in `_supabase_sql/` is ignored by Git except this README + `.gitkeep`.
