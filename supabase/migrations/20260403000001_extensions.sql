-- =============================================================
-- Migration: 0001 — Enable required PostgreSQL extensions
-- =============================================================
-- PostGIS: geographic types (geography, geometry) and spatial
--          functions (ST_Distance, ST_DWithin) for distance-based
--          gamification scoring and "stations near me" queries.
-- pgmq:    Postgres-native durable message queue used for the
--          async song recognition pipeline.
-- =============================================================

create extension if not exists postgis  with schema extensions;
create schema if not exists pgmq;
create extension if not exists pgmq     with schema pgmq;
