-- =============================================================
-- Migration: 0006 — recognized_songs table
-- =============================================================
-- Stores the result of a successful AudD recognition.
-- One-to-one with recognition_requests (request_id is UNIQUE).
-- Written exclusively by the recognition worker (service role).
-- =============================================================

create table public.recognized_songs (
  id              uuid         primary key default gen_random_uuid(),
  request_id      uuid         not null unique references public.recognition_requests(id) on delete cascade,
  station_id      uuid         not null references public.stations(id) on delete cascade,
  title           text         not null,
  artist          text         not null,
  album           text,
  album_art_url   text,
  genres          text[]       not null default '{}',
  isrc            text,                                -- International Standard Recording Code
  release_year    integer,
  audd_song_link  text         not null,               -- AudD/lis.tn song page URL
  spotify_uri     text,                                -- e.g. 'spotify:track:4uLU6hMCjMI75M1A2tKUQC'
  apple_music_url text,
  deezer_url      text,
  preview_url     text,                                -- ~30s audio preview clip
  lyrics_snippet  text,
  raw_response    jsonb,                               -- Full AudD API response (forward compatibility)
  recognized_at   timestamptz  not null default now()
);

-- ── Indexes ──────────────────────────────────────────────────

-- Find all songs recognized on a given station
create index idx_recognized_songs_station_id
  on public.recognized_songs (station_id, recognized_at desc);

-- Look up by AudD song link for result caching / deduplication
create index idx_recognized_songs_audd_song_link
  on public.recognized_songs (audd_song_link);

-- Artist search / "most recognized artists" aggregations
create index idx_recognized_songs_artist
  on public.recognized_songs (artist);

-- ISRC-based deduplication (same recording across multiple recognitions)
create index idx_recognized_songs_isrc
  on public.recognized_songs (isrc)
  where isrc is not null;

-- ── Row Level Security ────────────────────────────────────────
alter table public.recognized_songs enable row level security;

-- A user can read songs that came from their own recognition requests
create policy "Users can read their own recognized songs"
  on public.recognized_songs for select
  to authenticated
  using (
    exists (
      select 1
      from public.recognition_requests rr
      where rr.id = recognized_songs.request_id
        and rr.user_id = auth.uid()
    )
  );

-- Only the recognition worker (service role) writes song results
create policy "Service role can insert recognized songs"
  on public.recognized_songs for insert
  to service_role
  with check (true);

create policy "Service role can update recognized songs"
  on public.recognized_songs for update
  to service_role
  using (true);

create policy "Service role can delete recognized songs"
  on public.recognized_songs for delete
  to service_role
  using (true);
