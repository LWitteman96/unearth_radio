-- =============================================================
-- Migration: 0009 — social tables
-- =============================================================
-- Three tables covering the social graph:
--   • friendships    — directional friend requests with status
--   • station_shares — users sharing stations with friends
--   • station_votes  — upvote/downvote per user per station
-- =============================================================

-- ── friendships ───────────────────────────────────────────────

create table public.friendships (
  id             uuid         primary key default gen_random_uuid(),
  requester_id   uuid         not null references public.users(id) on delete cascade,
  addressee_id   uuid         not null references public.users(id) on delete cascade,
  status         text         not null default 'pending',
                              -- 'pending' | 'accepted' | 'declined' | 'blocked'
  created_at     timestamptz  not null default now(),
  updated_at     timestamptz  not null default now(),

  -- One request per direction per pair
  constraint friendships_unique unique (requester_id, addressee_id),
  -- Prevent self-friending
  constraint friendships_no_self_friend check (requester_id != addressee_id),
  constraint friendships_status_check
    check (status in ('pending', 'accepted', 'declined', 'blocked'))
);

-- Find incoming requests for a user (requester_id is covered by the UNIQUE index)
create index idx_friendships_addressee_id
  on public.friendships (addressee_id, status);

-- Find all accepted friends of a user (bidirectional lookup)
create index idx_friendships_requester_accepted
  on public.friendships (requester_id)
  where status = 'accepted';

create trigger trg_friendships_updated_at
  before update on public.friendships
  for each row execute function public.set_updated_at();

alter table public.friendships enable row level security;

create policy "Both parties can read friendship records"
  on public.friendships for select
  to authenticated
  using (auth.uid() in (requester_id, addressee_id));

create policy "Authenticated users can send friend requests"
  on public.friendships for insert
  to authenticated
  with check (auth.uid() = requester_id);

-- Addressee can accept/decline; requester can cancel their own pending request
create policy "Parties can update friendship status"
  on public.friendships for update
  to authenticated
  using (auth.uid() in (requester_id, addressee_id))
  with check (auth.uid() in (requester_id, addressee_id));

-- Either party can unfriend (delete the record)
create policy "Either party can delete a friendship"
  on public.friendships for delete
  to authenticated
  using (auth.uid() in (requester_id, addressee_id));

-- ── station_shares ────────────────────────────────────────────

create table public.station_shares (
  id            uuid         primary key default gen_random_uuid(),
  sharer_id     uuid         not null references public.users(id) on delete cascade,
  recipient_id  uuid         not null references public.users(id) on delete cascade,
  station_id    uuid         not null references public.stations(id) on delete cascade,
  message       text,
  created_at    timestamptz  not null default now()
);

create index idx_station_shares_recipient_id
  on public.station_shares (recipient_id, created_at desc);

create index idx_station_shares_sharer_id
  on public.station_shares (sharer_id, created_at desc);

alter table public.station_shares enable row level security;

create policy "Sharer and recipient can read shares"
  on public.station_shares for select
  to authenticated
  using (auth.uid() in (sharer_id, recipient_id));

create policy "Authenticated users can send shares"
  on public.station_shares for insert
  to authenticated
  with check (auth.uid() = sharer_id);

create policy "Sharer can delete their own shares"
  on public.station_shares for delete
  to authenticated
  using (auth.uid() = sharer_id);

-- ── station_votes ─────────────────────────────────────────────

create table public.station_votes (
  user_id     uuid         not null references public.users(id) on delete cascade,
  station_id  uuid         not null references public.stations(id) on delete cascade,
  vote        smallint     not null,      -- 1 = upvote, -1 = downvote
  created_at  timestamptz  not null default now(),

  -- Composite PK ensures one vote per user per station
  primary key (user_id, station_id),

  constraint station_votes_value_check check (vote in (1, -1))
);

-- Aggregate vote counts per station (for display + obscurity scoring)
create index idx_station_votes_station_id
  on public.station_votes (station_id);

alter table public.station_votes enable row level security;

-- Users can see their own votes; aggregate counts exposed via a view (see migration 0011)
create policy "Users can read their own votes"
  on public.station_votes for select
  to authenticated
  using (auth.uid() = user_id);

create policy "Users can vote on stations"
  on public.station_votes for insert
  to authenticated
  with check (auth.uid() = user_id);

-- Allow changing vote (upsert pattern: insert + on conflict update)
create policy "Users can update their own votes"
  on public.station_votes for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can remove their own votes"
  on public.station_votes for delete
  to authenticated
  using (auth.uid() = user_id);
