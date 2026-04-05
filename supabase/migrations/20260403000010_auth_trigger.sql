-- =============================================================
-- Migration: 0010 — auth trigger: auto-create user profile
-- =============================================================
-- When a new user signs up via Supabase Auth (Google SSO or
-- Magic Link), this trigger creates a matching row in
-- public.users automatically.
--
-- display_name is derived from:
--   1. raw_user_meta_data->>'full_name'  (Google OAuth)
--   2. raw_user_meta_data->>'name'       (some providers)
--   3. email address prefix              (Magic Link fallback)
-- =============================================================

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  derived_display_name text;
begin
  -- Derive best available display name from auth metadata
  derived_display_name := coalesce(
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'name',
    split_part(new.email, '@', 1)   -- e.g. "luuk" from "luuk@example.com"
  );

  insert into public.users (
    id,
    display_name,
    avatar_url,
    created_at,
    updated_at
  ) values (
    new.id,
    derived_display_name,
    new.raw_user_meta_data ->> 'avatar_url',
    now(),
    now()
  )
  on conflict (id) do nothing;     -- idempotent: safe to run multiple times

  return new;
end;
$$;

-- Fires after every new row in auth.users
create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();
