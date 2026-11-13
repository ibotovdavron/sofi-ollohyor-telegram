-- Vaxshivor — Supabase sozlamalari.
-- Supabase → SQL Editor'da bir marta ishga tushiring. Qayta ishga tushirish xavfsiz.

-- 1) Arizalar: kurs va izoh ustunlari.
alter table public.applications add column if not exists course text;
alter table public.applications add column if not exists message text;
alter table public.applications add column if not exists created_at timestamptz not null default now();

-- 2) Administratorlar ro'yxati.
create table if not exists public.admins (
  email text primary key
);
alter table public.admins enable row level security;
-- Quyidagi qatorda o'z admin emailingizni yozing:
-- insert into public.admins (email) values ('SIZNING_EMAIL@example.com') on conflict do nothing;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where lower(email) = lower(auth.jwt() ->> 'email'));
$$;

-- Arizalarni faqat administrator ko'radi; har kim ariza yubora oladi.
alter table public.applications enable row level security;
drop policy if exists "admin_read_applications" on public.applications;
create policy "admin_read_applications" on public.applications
  for select to authenticated using (public.is_admin());
drop policy if exists "anyone_insert_applications" on public.applications;
create policy "anyone_insert_applications" on public.applications
  for insert to anon, authenticated with check (true);

-- 3) Testlar.
create table if not exists public.tests (
  id bigint generated always as identity primary key,
  subject text not null default 'Umumiy',
  question text not null,
  options jsonb not null,          -- masalan: ["2", "3", "4", "5"]
  correct_index int not null,      -- to'g'ri javob tartib raqami, 0 dan boshlanadi
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.tests enable row level security;
drop policy if exists "public_read_tests" on public.tests;
create policy "public_read_tests" on public.tests
  for select to anon, authenticated using (is_active);
drop policy if exists "admin_manage_tests" on public.tests;
create policy "admin_manage_tests" on public.tests
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Namuna savol:
-- insert into public.tests (subject, question, options, correct_index)
-- values ('Matematika', '2 + 2 = ?', '["3","4","5","6"]', 1);
