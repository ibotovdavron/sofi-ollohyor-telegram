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
