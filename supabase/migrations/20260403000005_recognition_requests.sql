-- =============================================================
-- Migration: 0005 — recognition_requests table
-- =============================================================
-- Tracks each user-initiated AudD song recognition attempt.
-- Acts as the job record for the PGMQ-based recognition pipeline.
-- The Flutter client subscribes to this table via Supabase Realtime
-- to receive results when the worker updates status → 'completed'.
-- =============================================================

create table public.recognition_requests (
  id               uuid         primary key default gen_random_uuid(),
  user_id          uuid         not null references public.users(id) on delete cascade,
  station_id       uuid         not null references public.stations(id) on delete cascade,
  session_id       uuid         references public.listening_sessions(id) on delete set null,
  status           text         not null default 'pending',
                                -- 'pending' | 'processing' | 'completed' | 'failed' | 'no_match'
  duration_seconds integer      not null default 10,
  error_message    text,
  created_at       timestamptz  not null default now(),
  completed_at     timestamptz,

  constraint recognition_requests_status_check
    check (status in ('pending', 'processing', 'completed', 'failed', 'no_match'))
);

-- ── Indexes ──────────────────────────────────────────────────

-- User's recognition history sorted by time
create index idx_recognition_requests_user_created
  on public.recognition_requests (user_id, created_at desc);

-- Worker queue: find pending jobs to pick up
create index idx_recognition_requests_status
  on public.recognition_requests (status)
  where status in ('pending', 'processing');

-- Station-level: find recent recognitions for caching (same station, recent window)
create index idx_recognition_requests_station_created
  on public.recognition_requests (station_id, created_at desc);

-- ── Row Level Security ────────────────────────────────────────
alter table public.recognition_requests enable row level security;

create policy "Users can read their own requests"
  on public.recognition_requests for select
  to authenticated
  using (auth.uid() = user_id);

create policy "Users can insert their own requests"
  on public.recognition_requests for insert
  to authenticated
  with check (auth.uid() = user_id);

-- Status updates are done by the worker (service role)
create policy "Service role can update requests"
  on public.recognition_requests for update
  to service_role
  using (true);

create policy "Service role can delete requests"
  on public.recognition_requests for delete
  to service_role
  using (true);

-- ── Realtime publication ──────────────────────────────────────
-- Enable Realtime change notifications on this table so Flutter clients
-- can subscribe to their recognition result without polling.
-- (In Supabase, tables must be added to the supabase_realtime publication.)
alter publication supabase_realtime add table public.recognition_requests;
