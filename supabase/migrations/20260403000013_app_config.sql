-- app_config: generic key-value store for backend service state
-- Used by the station sync job to persist checkpoint data (last_changeuuid).

create table if not exists public.app_config (
  key        text        primary key,
  value      text        not null,
  updated_at timestamptz not null default now()
);

-- Auto-update updated_at on every write
create or replace function public.set_app_config_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger app_config_updated_at
  before update on public.app_config
  for each row execute procedure public.set_app_config_updated_at();

-- Only the service role can read/write app_config (no anon/user access needed)
alter table public.app_config enable row level security;

-- No RLS policies = service role bypasses RLS, anon/authenticated get nothing
