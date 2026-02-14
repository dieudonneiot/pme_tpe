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

## Backfill existing businesses

After creating categories + the `businesses.business_category_id` column, existing businesses will usually have `business_category_id = NULL`.

Option A (best): if you already used the mapping table `public.business_categories (business_id, category_id)`, promote one mapping row to be the “primary” category:

```sql
with pick as (
  select distinct on (bc.business_id)
    bc.business_id,
    bc.category_id
  from public.business_categories bc
  join public.categories c on c.id = bc.category_id
  order by bc.business_id, c.sort_order asc, c.name asc
)
update public.businesses b
set business_category_id = pick.category_id
from pick
where b.id = pick.business_id
  and b.business_category_id is null;
```

Option B (quick): keyword-based assignment (edit keywords to your needs):

```sql
with cat as (
  select
    (select id from public.categories where slug = 'beaute' limit 1) as beaute,
    (select id from public.categories where slug = 'restauration' limit 1) as restauration,
    (select id from public.categories where slug = 'btp' limit 1) as btp,
    (select id from public.categories where slug = 'transport' limit 1) as transport,
    (select id from public.categories where slug = 'commerce' limit 1) as commerce,
    (select id from public.categories where slug = 'sante' limit 1) as sante,
    (select id from public.categories where slug = 'education' limit 1) as education,
    (select id from public.categories where slug = 'tech' limit 1) as tech
)
update public.businesses b
set business_category_id = case
  when (coalesce(b.name,'') || ' ' || coalesce(b.description,'') || ' ' || coalesce(b.address_text,'')) ilike any(array['%coiff%','%salon%','%beaute%','%beauté%','%barber%']) then cat.beaute
  when (coalesce(b.name,'') || ' ' || coalesce(b.description,'') || ' ' || coalesce(b.address_text,'')) ilike any(array['%resto%','%restaurant%','%traiteur%','%cuisine%','%bar%','%café%','%cafe%']) then cat.restauration
  when (coalesce(b.name,'') || ' ' || coalesce(b.description,'') || ' ' || coalesce(b.address_text,'')) ilike any(array['%btp%','%construction%','%quincaillerie%','%chantier%']) then cat.btp
  when (coalesce(b.name,'') || ' ' || coalesce(b.description,'') || ' ' || coalesce(b.address_text,'')) ilike any(array['%transport%','%livraison%','%logistique%','%taxi%']) then cat.transport
  when (coalesce(b.name,'') || ' ' || coalesce(b.description,'') || ' ' || coalesce(b.address_text,'')) ilike any(array['%boutique%','%commerce%','%magasin%','%market%','%marché%','%marche%']) then cat.commerce
  when (coalesce(b.name,'') || ' ' || coalesce(b.description,'') || ' ' || coalesce(b.address_text,'')) ilike any(array['%santé%','%sante%','%pharmacie%','%clinique%','%cabinet%','%hopital%','%hôpital%']) then cat.sante
  when (coalesce(b.name,'') || ' ' || coalesce(b.description,'') || ' ' || coalesce(b.address_text,'')) ilike any(array['%école%','%ecole%','%formation%','%cours%','%universit%']) then cat.education
  when (coalesce(b.name,'') || ' ' || coalesce(b.description,'') || ' ' || coalesce(b.address_text,'')) ilike any(array['%tech%','%informatique%','%numérique%','%numerique%','%développement%','%developpement%','%logiciel%','%réseau%','%reseau%']) then cat.tech
  else b.business_category_id
end
from cat
where b.business_category_id is null;
```

Tip: a full script (including reports) is available locally at `app/_supabase_sql/backfill_business_category_id.sql` (ignored by Git).

## Extracted reference (local)

If you keep a long “all-in-one” schema / SQL history file (like `docs/Summary_Of_All_done.txt`), you can extract useful slices into this folder so you don’t have to scroll/search every time.

Local files created from `docs/Summary_Of_All_done.txt`:
- `app/_supabase_sql/schema_349-882_from_Summary_Of_All_done.txt`
- `app/_supabase_sql/sql_904-6381_from_Summary_Of_All_done.sql`
- `app/_supabase_sql/EXTRACTED_FROM_Summary_Of_All_done.md`

Reminder: everything in `_supabase_sql/` is ignored by Git except this README + `.gitkeep`.
