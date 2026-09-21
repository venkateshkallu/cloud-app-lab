# excel-api
 
Read-only Node.js/Express service that exposes rows from `stg.Assignments_Raw` (Postgres database `aq_cor_stg`) to the Tracker grid in the Cred Frontend UI.
 
This service **never writes** to the database. The 3 existing Flask APIs (ports 8001, 5001, 5002) are completely unchanged.
 
## Running
 
```bash
cd excel-api
npm install
npm start
```
 
The server listens on port **8002** by default.
 
## Environment variables
 
The service loads the repo-root `.env` automatically (via `dotenv`). The variables it needs:
 
| Variable | Alias | Default | Description |
|---|---|---|---|
| `DB_HOST` | `DB_SERVER` | *(required)* | Postgres host/IP |
| `DB_NAME` | `DB_DATABASE` | `aq_cor_stg` | Database name |
| `DB_USER` | `DB_UID` | *(required)* | Postgres login username |
| `DB_PASSWORD` | `DB_PASS` | `""` | Postgres login password |
| `DB_PORT` | — | `5432` | Postgres TCP port |
| `DB_SSL` | — | `false` | Encrypt the DB connection (TLS, cert validation skipped). Set `true` if the server requires it |
| `PORT` | — | `8002` | HTTP port for this service |
| `COCKPIT_API_BASE` | — | `http://localhost:8001` | Cockpit API the `/cred-tracker/sync` pulls agent data from |
| `CRED_TRACKER_TOKEN` | — | *(unset)* | Shared token guarding the Cred Tracker write endpoints. Unset = unauthenticated (warns) |
| `CRED_TRACKER_ALLOWED_ORIGINS` | — | local Vite | Comma-separated CORS origin allowlist |
 
> The repo-root `.env` is the loaded file. `excel-api/.env` is **not** auto-loaded.
 
See `.env.example` for a reference template.
 
## Auth
 
`GET` routes are read-only and open. The **state-changing** routes —
`POST /cred-tracker/sync`, `PATCH /cred-tracker/:id`, `DELETE /cred-tracker/:id` —
require an `X-Cred-Tracker-Token` header matching `CRED_TRACKER_TOKEN` (a 401 is
returned otherwise). CORS is restricted to `CRED_TRACKER_ALLOWED_ORIGINS`.
 
If `CRED_TRACKER_TOKEN` is unset, the writes are allowed (a one-time warning is
logged) so local dev works out of the box — set it to enforce.
 
**Caveat:** the UI sends this token from `VITE_CRED_TRACKER_TOKEN`, which ships
to the browser and is therefore not a true secret. It raises the bar against
casual/cross-origin abuse together with the CORS allowlist; for real per-user
authorization, validate the app's own session/JWT in `auth.js` instead.
 
## TLS / DB security
 
The database connection is **plaintext by default** (`DB_SSL=false`), suitable for
a local/same-box Postgres connection. Set `DB_SSL=true` if the Postgres server
requires an encrypted connection (certificate validation is skipped, matching
the old `DB_TRUST_CERT=true` behavior — internal servers often lack a valid cert).
 
**Never use plaintext (`DB_SSL=false`) over an untrusted network.**
 
## Endpoints
 
### `GET /health`
 
Returns `{ ok: true, db: "up" }` when the DB connection succeeds, or `{ ok: true, db: "down", error: "..." }` when it fails. Always returns HTTP 200 — useful for uptime checks.
 
### `GET /tracker[?limit=N&offset=M]`
 
Returns all assignment rows from `stg.Assignments_Raw`, ordered by `Assignment_Id DESC`.
 
- `limit` — max rows to return (default 5000, capped at 20000)
- `offset` — skip N rows for pagination (default 0)
 
Response shape:
```json
{ "rows": [ { "assignment_id": 149036, "candidate_name": "Jane", ... } ] }
```
 
Column names are normalized from DB Pascal-case (`Assignment_Id`, `Facility_Name`, ...) to snake_case (`assignment_id`, `hospital`, ...). See `normalize.js` for the full mapping.
 
### `GET /tracker/:id`
 
Returns a single normalized row by `Assignment_Id`. Returns HTTP 404 if not found, HTTP 503 if the DB is unreachable.
 
### Dashboard history
 
- `GET /dashboard?start=YYYY-MM-DD&end=YYYY-MM-DD` — read persisted dashboard snapshots
  in a date range. Returns `{ aggregates: [...daily rows...], detail: [...per-assignment rows...] }`.
  Auto-creates `stg.Cred_Dashboard` and `stg.Cred_Dashboard_Detail` on first call.
- `POST /dashboard/snapshot` *(requires `X-Cred-Tracker-Token`)* — upsert today's snapshot.
  Body: `{ date: "YYYY-MM-DD", aggregate: { total, red, yellow, green, ready, cost, missing, flags },
  detail: [ { assignment_id, candidate, district, tier, ready, cost, cost_by_agent, valid, expiring,
  expired, missing, unreadable, auditor_flags } ] }`. Idempotent per date (delete-then-insert).
 
## Notes
 
- This service is **read-only** — it issues only `SELECT` queries.
- The 3 existing Flask APIs (ports 8001, 5001, 5002) are **not modified**.
- `node_modules/` is gitignored; run `npm install` before first use.