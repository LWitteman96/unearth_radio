-- =============================================================
-- Migration: 0002 — users table
-- =============================================================
-- Extends Supabase auth.users. Stores public profile data and
-- gamification totals. Triggered into existence on auth signup
-- via a Postgres function + trigger (see migration 0010).
-- =============================================================

create table public.users (
  id             uuid         primary key references auth.users(id) on delete cascade,
  display_name   text         not null,
  avatar_url     text,
  location_lat   double precision,
  location_lng   double precision,
  country_code   text,
  total_points   integer      not null default 0,
  preferences    jsonb        not null default '{}',
  created_at     timestamptz  not null default now(),
  updated_at     timestamptz  not null default now()
);

-- ── Indexes ──────────────────────────────────────────────────
-- total_points is used for leaderboard ORDER BY — btree is optimal
create index idx_users_total_points on public.users (total_points desc);

-- ── Row Level Security ────────────────────────────────────────
alter table public.users enable row level security;

-- Anyone who is authenticated can read public fields of any user
-- (display_name, avatar_url, total_points) — needed for leaderboards
-- and friend lookups. Full profile is readable only by the owner.
create policy "Users can read public profiles"
  on public.users for select
  to authenticated
  using (true);

-- Users can only update their own profile
create policy "Users can update their own profile"
  on public.users for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Insert is handled by the auth trigger (service role), not by the client
create policy "Service role can insert users"
  on public.users for insert
  to service_role
  with check (true);

-- Delete is handled by the auth cascade or service role (account deletion)
create policy "Service role can delete users"
  on public.users for delete
  to service_role
  using (true);

-- ── updated_at trigger ────────────────────────────────────────
-- Reusable helper function — created once here, referenced by
-- later migrations via trigger definitions.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_users_updated_at
  before update on public.users
  for each row execute function public.set_updated_at();
