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

Option A (best): if you already used the mapping table `public.business_categories (business_id, category_id)`, promote one mapping row to be the "primary" category:

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

## Admin-only category management

We use `public.categories` as the global category list. Public read is enabled, but **writes are blocked** by default due to RLS (good).

To allow only application admins to create/edit/delete categories, run:

```sql
create table if not exists public.app_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.app_admins enable row level security;

-- Add your admin user(s) manually (run as postgres):
-- insert into public.app_admins (user_id)
-- values ('<YOUR_USER_UUID>')
-- on conflict do nothing;

create or replace function public.is_app_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (select 1 from public.app_admins a where a.user_id = auth.uid());
$$;

drop policy if exists "App admins manage categories" on public.categories;
create policy "App admins manage categories"
  on public.categories
  for all
  to authenticated
  using (public.is_app_admin())
  with check (public.is_app_admin());
```

Tip: a full local script is available at `app/_supabase_sql/admin_manage_categories.sql` (ignored by Git).

## Business delete (archive / soft-delete)

To add a safe “delete business” action (actually archives it to avoid breaking orders/products FKs), run:
- `app/_supabase_sql/delete_business.sql`

What it does:
- Adds `businesses.deleted_at` if missing
- Creates `public.delete_business(_business_id uuid)` (SECURITY DEFINER)
- Only allows **business owner/admin** (or **app admin**) to archive
- Sets `businesses.is_active=false` and `deleted_at=now()`
- Appends a suffix to `businesses.slug` to free the original slug
- Removes all `business_members` rows for that business (so it disappears from dashboards)

## Product media (photos/videos/PDF)

The app uses:
- Table: `public.product_media (id, product_id, media_type, storage_path, created_at)`
- Storage bucket: `product_media`

Important: Storage RLS expects the object path to start with the business id as the first segment:
`<business_uuid>/products/<product_uuid>/...`

### Cover + ordering (recommended)

To allow business users to choose a cover image + reorder media, run:
- `app/_supabase_sql/product_media_cover_ordering.sql` (local, ignored by Git)

This migration adds:
- `public.product_media.sort_order int not null default 0`
- `public.products.primary_media_id uuid null` (FK → `public.product_media.id`, `on delete set null`)
- An UPDATE RLS policy so business members can reorder `product_media`.

### RLS policies

If upload/delete/reorder doesn’t work, verify:
- `public.product_media` has select/insert/update/delete policies for business members:
  - `app/_supabase_sql/product_media_policies.sql` (only affects `public.product_media`)
- Storage policies exist for bucket `product_media`:
  - `app/_supabase_sql/storage_product_media_policies.sql` (touches `storage.objects`, may require privileged project role)

If you see `ERROR: 42501: must be owner of table objects`, it means the SQL role you used can’t modify `storage.objects`.
In that case, configure Storage rules in Supabase Dashboard (Storage → Policies) or ask the project owner to run the Storage script.

## Inventory pro (low-stock threshold)

To enable “low stock” alerts per variant, run:
- `app/_supabase_sql/variant_low_stock_threshold.sql` (adds `product_variants.low_stock_threshold`)

## B3 Orders: admin grant + stock reservation

To allow a business to receive orders either via subscription OR an admin grant, and to automatically reserve/release
stock when a request is accepted/cancelled:

1) Run admin entitlements setup:
- `app/_supabase_sql/admin_manage_entitlements.sql`
  - Adds `entitlements.orders_grant_until`
  - Allows app admins to read all businesses and update entitlements (RLS)

2) Run B3 stock reservation:
- `app/_supabase_sql/b3_stock_reservation.sql`
  - Adds `service_request_items.variant_id`
  - Adds `service_requests.stock_reserved_at / stock_released_at`
  - Updates `requests_insert_customer` policy to allow order creation if subscribed OR granted
  - Adds RPC: `set_request_status(request_id, next_status)` which reserves/releases stock automatically

## B3 Subscriptions (real payments): paid-until + providers

The app can enable "receive orders" using **paid subscription validity** + an optional **admin grant**:
- Paid subscription validity: `entitlements.orders_paid_until`
- Admin manual override: `entitlements.orders_grant_until`

Recommended migration (idempotent):
- `app/_supabase_sql/billing_subscription_v1.sql`
  - Adds `orders_paid_until`
  - Extends `subscription_provider` enum with `paydunya` + `stripe` (for `payments` / `subscriptions`)
  - Updates the `service_requests` insert RLS policy accordingly

## B3 Customer UX: cancel flow

To allow a customer to cancel their order safely (only while `status='new'`):
- `app/_supabase_sql/b3_customer_order_ux.sql`
  - Adds RPC: `customer_cancel_request(request_id)`

## Extracted reference (local)

If you keep a long "all-in-one" schema / SQL history file (like `docs/Summary_Of_All_done.txt`), you can extract useful slices into this folder so you don’t have to scroll/search every time.

Local files created from `docs/Summary_Of_All_done.txt`:
- `app/_supabase_sql/schema_349-882_from_Summary_Of_All_done.txt`
- `app/_supabase_sql/sql_904-6381_from_Summary_Of_All_done.sql`
- `app/_supabase_sql/EXTRACTED_FROM_Summary_Of_All_done.md`

Reminder: everything in `_supabase_sql/` is ignored by Git except this README + `.gitkeep`.
