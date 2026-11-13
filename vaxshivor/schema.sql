-- Vaxshivor qishloq portali — Supabase sozlamalari.
-- Supabase → SQL Editor'da bir marta ishga tushiring. Qayta ishga tushirish xavfsiz.

-- 1) Administratorlar.
create table if not exists public.admins (email text primary key);
alter table public.admins enable row level security;
-- O'z emailingizni yozib, quyidagi qatorni ishga tushiring:
-- insert into public.admins (email) values ('SIZNING_EMAIL@example.com') on conflict do nothing;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where lower(email) = lower(auth.jwt() ->> 'email'));
$$;

-- 2) Barcha e'lonlar bitta jadvalda (do'kon, usta, taksi, e'lon, ish).
create table if not exists public.listings (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('shop', 'master', 'taxi', 'ad', 'job')),
  category text not null,
  title text not null check (char_length(title) between 2 and 100),
  description text check (char_length(description) <= 1500),
  extra jsonb not null default '{}'::jsonb,
  contact_name text not null check (char_length(contact_name) <= 80),
  phone text not null check (char_length(phone) between 9 and 20),
  telegram text check (char_length(telegram) <= 40),
  photo_url text,
  user_id uuid default auth.uid() references auth.users (id) on delete cascade,
  is_approved boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.listings add column if not exists user_id uuid default auth.uid() references auth.users (id) on delete cascade;
create index if not exists listings_kind_idx on public.listings (kind, is_approved, created_at desc);
create index if not exists listings_user_idx on public.listings (user_id);

alter table public.listings enable row level security;

drop policy if exists "read_approved" on public.listings;
create policy "read_approved" on public.listings
  for select to anon, authenticated
  using (is_approved or user_id = auth.uid() or public.is_admin());

-- Google orqali ro'yxatdan o'tgan foydalanuvchi e'lon yuboradi; u tasdiqlanmagan holda tushadi.
drop policy if exists "submit_pending" on public.listings;
create policy "submit_pending" on public.listings
  for insert to authenticated with check (is_approved = false and user_id = auth.uid());

drop policy if exists "admin_update" on public.listings;
create policy "admin_update" on public.listings
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admin_delete" on public.listings;
create policy "admin_delete" on public.listings
  for delete to authenticated using (public.is_admin() or user_id = auth.uid());

-- 3) Rasmlar uchun ombor (3 MB gacha, faqat rasm).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('listing-photos', 'listing-photos', true, 3145728, array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do nothing;

drop policy if exists "listing_photos_upload" on storage.objects;
create policy "listing_photos_upload" on storage.objects
  for insert to authenticated with check (bucket_id = 'listing-photos');

-- 4) Foydalanuvchi profillari (ro'yxatdan o'tish anketasi).
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null check (char_length(full_name) between 2 and 80),
  age int check (age between 12 and 100),
  phone text check (char_length(phone) between 9 and 20),
  role text not null check (role in ('taxi', 'trader', 'master', 'farmer', 'other')),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

-- Profilni faqat egasi va administrator ko'radi.
drop policy if exists "profile_read" on public.profiles;
create policy "profile_read" on public.profiles
  for select to authenticated using (id = auth.uid() or public.is_admin());
drop policy if exists "profile_insert" on public.profiles;
create policy "profile_insert" on public.profiles
  for insert to authenticated with check (id = auth.uid());
drop policy if exists "profile_update" on public.profiles;
create policy "profile_update" on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- 5) Baho va sharhlar. Har bir foydalanuvchi bitta e'longa bitta baho beradi.
create table if not exists public.reviews (
  id bigint generated always as identity primary key,
  listing_id bigint not null references public.listings (id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  author_name text not null check (char_length(author_name) between 1 and 80),
  rating int not null check (rating between 1 and 5),
  comment text check (char_length(comment) <= 600),
  created_at timestamptz not null default now(),
  unique (listing_id, user_id)
);
create index if not exists reviews_listing_idx on public.reviews (listing_id);
alter table public.reviews enable row level security;

drop policy if exists "reviews_read" on public.reviews;
create policy "reviews_read" on public.reviews
  for select to anon, authenticated using (true);

-- O'z e'loniga baho berib bo'lmaydi.
drop policy if exists "reviews_insert" on public.reviews;
create policy "reviews_insert" on public.reviews
  for insert to authenticated with check (
    user_id = auth.uid()
    and not exists (select 1 from public.listings l where l.id = listing_id and l.user_id = auth.uid())
  );

drop policy if exists "reviews_update" on public.reviews;
create policy "reviews_update" on public.reviews
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "reviews_delete" on public.reviews;
create policy "reviews_delete" on public.reviews
  for delete to authenticated using (user_id = auth.uid() or public.is_admin());

-- 6) Onlayn taksilar: haydovchining joriy yo'nalishi va joylashuvi.
create table if not exists public.taxi_live (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  driver_name text not null check (char_length(driver_name) between 1 and 80),
  phone text check (char_length(phone) <= 20),
  car text check (char_length(car) <= 80),
  plate text check (char_length(plate) <= 15),
  from_place text not null check (char_length(from_place) between 1 and 60),
  to_place text not null check (char_length(to_place) between 1 and 60),
  seats int check (seats between 0 and 20),
  lat double precision not null check (lat between -90 and 90),
  lng double precision not null check (lng between -180 and 180),
  is_online boolean not null default true,
  updated_at timestamptz not null default now()
);
alter table public.taxi_live enable row level security;

drop policy if exists "taxi_live_read" on public.taxi_live;
create policy "taxi_live_read" on public.taxi_live
  for select to anon, authenticated using (true);

-- Faqat "taksi haydovchisi" sifatida ro'yxatdan o'tgan foydalanuvchi o'z joylashuvini yozadi.
drop policy if exists "taxi_live_insert" on public.taxi_live;
create policy "taxi_live_insert" on public.taxi_live
  for insert to authenticated with check (
    user_id = auth.uid()
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'taxi')
  );

drop policy if exists "taxi_live_update" on public.taxi_live;
create policy "taxi_live_update" on public.taxi_live
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "taxi_live_delete" on public.taxi_live;
create policy "taxi_live_delete" on public.taxi_live
  for delete to authenticated using (user_id = auth.uid() or public.is_admin());

-- 7) Taksi bo'limi faqat "Taksi haydovchisi" sifatida ro'yxatdan o'tganlar uchun.
-- Haydovchilarning identifikatorlari (shaxsiy ma'lumotsiz) — sayt taksi e'lonlarini shu bo'yicha saralaydi.
create or replace function public.taxi_driver_ids()
returns setof uuid language sql stable security definer set search_path = public as $$
  select id from public.profiles where role = 'taxi';
$$;

-- Taksi e'lonini faqat taksi haydovchisi bera oladi.
drop policy if exists "submit_pending" on public.listings;
create policy "submit_pending" on public.listings
  for insert to authenticated with check (
    is_approved = false
    and user_id = auth.uid()
    and (kind <> 'taxi' or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'taxi'))
  );
