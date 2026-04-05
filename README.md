# Unearth Radio

Radio discovery app with gamification. Find stations globally, recognize songs via Shazam, earn points.

## Services

### Flutter App
```bash
cd app
flutter run
```

### Sync Service (RadioBrowser → Supabase)
```bash
docker run --rm --env-file sync/.env unearth-sync
```
Requires: `.env` with `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`

### Worker Service (Song recognition queue)
```bash
docker run --rm --env-file worker/.env unearth-worker
```
Requires: `.env` with `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `AUDD_API_KEY`

### Supabase Local
```bash
cd supabase
supabase start
```
Ports: Studio (55323), DB (55322), Mailpit (55324)
