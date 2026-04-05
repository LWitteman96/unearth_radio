-- =============================================================
-- Migration: 0012 — PGMQ: song recognition queue
-- =============================================================
-- Creates the durable PGMQ message queue used by the async
-- song recognition pipeline.
--
-- Flow:
--   Flutter client → pgmq.send('song_recognition', message)
--   Recognition worker → pgmq.read() → process → pgmq.delete()
--   On failure: message reappears after visibility timeout → retry
--
-- The queue is created in the pgmq schema (installed in migration 0001).
-- pgmq_public is the Supabase-managed public-facing schema that allows
-- the Flutter client (anon/authenticated roles) to enqueue safely.
-- =============================================================

-- Create the queue (idempotent — does nothing if it already exists)
select pgmq.create('song_recognition');

-- Grant Flutter clients (authenticated role) the ability to enqueue messages.
-- Reading and deleting messages is reserved for the worker (service role).
grant execute
  on function pgmq.send(text, jsonb, integer)
  to authenticated;

grant execute
  on function pgmq.send(text, jsonb)
  to authenticated;
