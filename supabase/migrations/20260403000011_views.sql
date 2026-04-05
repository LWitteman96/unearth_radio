-- =============================================================
-- Migration: 0011 — views
-- =============================================================
-- Read-only views for common aggregations that don't warrant
-- their own tables. These are safe to query without RLS because
-- they expose only aggregated/public data.
-- =============================================================

-- ── station_vote_counts ───────────────────────────────────────
-- Exposes aggregate upvote/downvote counts per station.
-- Used for display (vote badge on station cards) and for
-- obscurity score recalculation during the sync cron.

create or replace view public.station_vote_counts as
select
  station_id,
  count(*) filter (where vote = 1)  as upvotes,
  count(*) filter (where vote = -1) as downvotes,
  sum(vote)                         as net_votes
from public.station_votes
group by station_id;

-- ── leaderboard ───────────────────────────────────────────────
-- Top users by total_points. Exposes only public profile fields.
-- The Flutter client queries this directly for the global leaderboard.
-- Friends leaderboard is handled in the app by filtering to friend IDs.

create or replace view public.leaderboard as
select
  id,
  display_name,
  avatar_url,
  total_points,
  rank() over (order by total_points desc) as rank
from public.users
order by total_points desc;

-- Grant read access to authenticated users
grant select on public.station_vote_counts to authenticated;
grant select on public.leaderboard to authenticated;
