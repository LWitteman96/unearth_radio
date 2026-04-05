-- =============================================================
-- Migration: 0014 — PGMQ public wrapper functions
-- =============================================================
-- PostgREST only exposes functions in the `public` schema via RPC.
-- PGMQ's native functions live in the `pgmq` schema. These thin
-- wrapper functions bridge the gap so that:
--   • Flutter clients (authenticated role) can call pgmq_send
--   • The Python worker (service role) can call pgmq_read / pgmq_delete
-- =============================================================

-- -------------------------
-- pgmq_send (Flutter → queue)
-- -------------------------
create or replace function public.pgmq_send(
  queue_name text,
  msg        jsonb
) returns bigint
  language sql
  security definer
  set search_path = public, pgmq
as $$
  select pgmq.send(queue_name, msg);
$$;

-- Only authenticated users may enqueue
revoke all on function public.pgmq_send(text, jsonb) from public;
grant execute on function public.pgmq_send(text, jsonb) to authenticated;


-- -------------------------
-- pgmq_read (worker → dequeue with visibility timeout)
-- -------------------------
create or replace function public.pgmq_read(
  queue_name text,
  vt         integer,
  qty        integer
) returns setof pgmq.message_record
  language sql
  security definer
  set search_path = public, pgmq
as $$
  select * from pgmq.read(queue_name, vt, qty);
$$;

-- Only service role (worker) may read messages
revoke all on function public.pgmq_read(text, integer, integer) from public;
grant execute on function public.pgmq_read(text, integer, integer) to service_role;


-- -------------------------
-- pgmq_delete (worker → acknowledge processed message)
-- -------------------------
create or replace function public.pgmq_delete(
  queue_name text,
  msg_id     bigint
) returns boolean
  language sql
  security definer
  set search_path = public, pgmq
as $$
  select pgmq.delete(queue_name, msg_id);
$$;

-- Only service role (worker) may delete messages
revoke all on function public.pgmq_delete(text, bigint) from public;
grant execute on function public.pgmq_delete(text, bigint) to service_role;
