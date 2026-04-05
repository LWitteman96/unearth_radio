-- =============================================================
-- Migration: 0004 — listening_sessions table
-- =============================================================
-- Tracks when users listen to stations and for how long.
-- Created before recognition_requests because recognition_requests
-- has a nullable FK → listening_sessions(id).
-- Powers the analytics dashboard (time listened, stations explored).
-- =============================================================

create table public.listening_sessions (
  id               uuid         primary key default gen_random_uuid(),
  user_id          uuid         not null references public.users(id) on delete cascade,
  station_id       uuid         not null references public.stations(id) on delete cascade,
  started_at       timestamptz  not null default now(),
  ended_at         timestamptz,                    -- null while session is active
  duration_seconds integer                         -- computed on session end (ended_at - started_at)
);

-- ── Indexes ──────────────────────────────────────────────────

-- User's listening history sorted by time (dashboard, stats)
create index idx_listening_sessions_user_started
  on public.listening_sessions (user_id, started_at desc);

-- Active session lookup (find open sessions to close them)
create index idx_listening_sessions_active
  on public.listening_sessions (user_id, station_id)
  where ended_at is null;

-- Station-level analytics (total listens per station)
create index idx_listening_sessions_station_id
  on public.listening_sessions (station_id);

-- ── Row Level Security ────────────────────────────────────────
alter table public.listening_sessions enable row level security;

create policy "Users can read their own sessions"
  on public.listening_sessions for select
  to authenticated
  using (auth.uid() = user_id);

create policy "Users can insert their own sessions"
  on public.listening_sessions for insert
  to authenticated
  with check (auth.uid() = user_id);

-- Users can close their own active sessions (set ended_at / duration_seconds)
create policy "Users can update their own sessions"
  on public.listening_sessions for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Service role can delete sessions"
  on public.listening_sessions for delete
  to service_role
  using (true);
