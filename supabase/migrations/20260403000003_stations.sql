-- =============================================================
-- Migration: 0003 — stations table
-- =============================================================
-- Radio station catalog synced from the RadioBrowser API.
-- Enriched with local fields: obscurity_score, geo (PostGIS),
-- and app-specific metadata.
--
-- Upsert key: rb_id (RadioBrowser UUID)
-- Sync strategy: daily cron via incremental lastchangeuuid diff
-- =============================================================

create table public.stations (
  id                  uuid         primary key default gen_random_uuid(),
  rb_id               text         not null unique,        -- RadioBrowser stationuuid
  name                text         not null,
  url                 text         not null,               -- Original stream URL
  url_resolved        text,                                -- Resolved/redirected stream URL
  homepage            text,
  favicon             text,
  country             text,
  country_code        text,                                -- ISO 3166-1 alpha-2
  state               text,
  geo_lat             double precision,                    -- Kept for display / raw value
  geo_lng             double precision,
  geo                 geography(Point, 4326),              -- PostGIS point for spatial queries
  tags                text[]       not null default '{}',  -- Genre tags e.g. ['rock', 'pop']
  language            text[]       not null default '{}',  -- Broadcast languages
  codec               text,                                -- e.g. 'MP3', 'AAC'
  bitrate             integer,                             -- kbps
  hls                 boolean      not null default false, -- HLS streams lack ICY metadata
  votes               integer      not null default 0,     -- RadioBrowser community votes
  click_count         integer      not null default 0,
  click_trend         integer      not null default 0,
  has_extended_info   boolean      not null default false, -- ICY metadata availability hint
  last_check_ok       boolean      not null default true,
  last_check_ok_time  timestamptz,
  obscurity_score     double precision,                    -- Pre-computed gamification score
  synced_at           timestamptz  not null default now(), -- Last RadioBrowser sync
  created_at          timestamptz  not null default now()
);

-- ── Indexes ──────────────────────────────────────────────────

-- GIN index for fast tag filtering: WHERE tags @> '{rock}' or tags && '{jazz,blues}'
create index idx_stations_tags
  on public.stations using gin (tags);

-- btree index for country filtering
create index idx_stations_country_code
  on public.stations (country_code);

-- btree index for obscurity-based sorting in gamification
create index idx_stations_obscurity_score
  on public.stations (obscurity_score desc);

-- GIST spatial index for ST_Distance and ST_DWithin queries (PostGIS)
create index idx_stations_geo
  on public.stations using gist (geo);

-- Partial index: only active stations (saves space, speeds common queries)
create index idx_stations_active
  on public.stations (rb_id)
  where last_check_ok = true;

-- Full-text search on station name (used by station browser search)
create index idx_stations_name_fts
  on public.stations using gin (to_tsvector('english', name));

-- ── Row Level Security ────────────────────────────────────────
alter table public.stations enable row level security;

-- All authenticated users can read all station records
create policy "Authenticated users can read stations"
  on public.stations for select
  to authenticated
  using (true);

-- Only the service role (sync job) can write to stations
create policy "Service role can insert stations"
  on public.stations for insert
  to service_role
  with check (true);

create policy "Service role can update stations"
  on public.stations for update
  to service_role
  using (true);

create policy "Service role can delete stations"
  on public.stations for delete
  to service_role
  using (true);
