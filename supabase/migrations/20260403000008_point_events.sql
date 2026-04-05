-- =============================================================
-- Migration: 0008 — point_events table
-- =============================================================
-- Immutable audit log of all gamification point transactions.
-- users.total_points is a cached aggregate — kept in sync via
-- a trigger on this table (see below).
--
-- event_type values:
--   'discovery'        — first time a user plays a station
--   'distance_bonus'   — bonus for geographic distance
--   'obscurity_bonus'  — bonus for low-vote/click stations
--   'share'            — sharing a station with a friend
--   'vote'             — voting on a station
--   'streak'           — daily listening streak bonus
--   'achievement'      — P1 badge/achievement unlock
-- =============================================================

create table public.point_events (
  id           uuid         primary key default gen_random_uuid(),
  user_id      uuid         not null references public.users(id) on delete cascade,
  event_type   text         not null,
  points       integer      not null,               -- positive = award, negative = deduction
  metadata     jsonb,                               -- e.g. {"station_id":"…","distance_km":4200}
  reference_id uuid,                               -- optional FK to triggering entity
  created_at   timestamptz  not null default now(),

  constraint point_events_event_type_check
    check (event_type in (
      'discovery', 'distance_bonus', 'obscurity_bonus',
      'share', 'vote', 'streak', 'achievement'
    ))
);

-- ── Indexes ──────────────────────────────────────────────────

-- User's point history timeline (dashboard, profile)
create index idx_point_events_user_created
  on public.point_events (user_id, created_at desc);

-- Filter/aggregate by event type (stats, debug)
create index idx_point_events_event_type
  on public.point_events (event_type);

-- ── Trigger: keep users.total_points in sync ─────────────────
-- Fires after each INSERT on point_events and atomically
-- increments/decrements the cached total on the user row.
-- Using a trigger (rather than recomputing on every read)
-- keeps leaderboard queries cheap.

create or replace function public.sync_user_total_points()
returns trigger
language plpgsql
security definer                                   -- runs as owner, bypasses RLS
set search_path = public
as $$
begin
  update public.users
  set total_points = total_points + new.points
  where id = new.user_id;
  return new;
end;
$$;

create trigger trg_point_events_sync_total
  after insert on public.point_events
  for each row execute function public.sync_user_total_points();

-- ── Row Level Security ────────────────────────────────────────
alter table public.point_events enable row level security;

-- Users can read their own point history
create policy "Users can read their own point events"
  on public.point_events for select
  to authenticated
  using (auth.uid() = user_id);

-- Points are awarded only by server-side Edge Functions (service role)
create policy "Service role can insert point events"
  on public.point_events for insert
  to service_role
  with check (true);

-- Point events are immutable — no updates or deletes by anyone
-- (corrections are made by issuing a new negative point event)
