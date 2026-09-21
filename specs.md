# Dual-Mode (Test / Live) Credentialing Console — Design

**Date:** 2026-06-09
**Status:** Approved (design); pending spec review

## Goal

Extend the Aequor Credentialing HITL Cockpit frontend from a single-backend
(Cockpit/test) app into a **dual-mode console** with a top-level **Test / Live**
switch:

- **Test mode** — the existing Cockpit/test API (`http://52.9.132.43:8001`). The
  test/review tool: run the pipeline on a fixed set of test assignment IDs,
  review candidates, apply HITL overrides, inspect audit logs. Behavior is
  exactly today's app.
- **Live mode** — the production **Pipeline API** (Bullhorn + scheduler) on the
  same host, a different port. Adds a live Bullhorn connection panel and an
  auto-poll scheduler that ingests EDU placements and runs the full pipeline,
  on top of the same per-assignment review/agent/audit workspace.

Both modes share one per-assignment workspace (Review + agent override tabs +
Email preview + Audit), so the only mode-specific UI is the Live landing view
(Bullhorn + scheduler + live feed + manual controls).

## Non-Goals

- No backend changes. The two APIs already exist and are described in the
  endpoint references.
- No new brand colors or fonts — reuse existing ACAP tokens in
  `src/styles/theme.css`.
- No changes to auth (email-picker, sessionStorage) beyond what mode-switching
  requires.

## Architecture — data layer

The central change: the **active backend is a runtime value**, not a hardcoded
constant, so existing hooks/components work unchanged in both modes.

### Config

`src/config.js` gains a second base URL:

```js
export const COCKPIT_API_BASE  = import.meta.env.VITE_API_BASE          ?? 'http://52.9.132.43:8001'
export const PIPELINE_API_BASE = import.meta.env.VITE_PIPELINE_API_BASE ?? 'http://52.9.132.43:<PIPELINE_PORT>'
```

- `COCKPIT_API_BASE` = Test mode (unchanged default, port 8001).
- `PIPELINE_API_BASE` = Live mode. **`<PIPELINE_PORT>` is a config value the user
  supplies** (same host `52.9.132.43`, different port). Until set, Live mode
  renders but its network calls fail gracefully (see Error handling).
- `API_BASE` is kept as an alias of `COCKPIT_API_BASE` for backward-compat with
  any current import, then migrated.

### Mode context

New `src/console/ConsoleModeProvider.jsx` exposes:

```js
{ mode: 'test' | 'live', setMode(m), apiBase: string }
```

- Persists `mode` to `sessionStorage` (key `acap.consoleMode`, default `test`).
- On change, calls `setActiveApiBase(apiBase)` (below) and clears no caches —
  caches are namespaced instead.

### Mode-aware apiClient

`src/lib/apiClient.js` stops importing a constant base. Instead:

```js
let activeBase = COCKPIT_API_BASE
export function setActiveApiBase(b) { activeBase = b }
```

`request()`, `documentUrl()`, and the SSE helper read `activeBase`. The
`ConsoleModeProvider` is the single writer via `setActiveApiBase`. This keeps
every existing hook (`api/*.js`) and component working without edits to their
fetch calls.

> Trade-off considered: passing `apiBase` through every hook as an argument
> (explicit but touches ~8 files and all call sites) vs. a module-level setter
> driven by context (one writer, zero hook edits). Chosen the setter: the active
> backend is genuinely global per render tree, and the provider guarantees a
> single writer synchronized with React state.

### Query cache namespacing

To stop the two backends' caches colliding, query keys are prefixed with mode.
A small helper wraps key construction:

```js
// keys are ['test', 'review', aid] vs ['live', 'review', aid]
```

Hooks gain the active mode prefix from context (via a `useModeKey()` helper) so
switching modes shows that backend's data, and React Query refetches per mode.
SSE `EventSource` URLs are built from `activeBase` at attach time.

## Architecture — UI

### Top-level mode switch (TopBar)

A segmented control in `TopBar`: `[ 🧪 Test | 🛰 Live ]`. The active segment is a
cyan pill that slides via Framer Motion `layoutId`. Live segment shows a status
dot: pulsing green when Bullhorn connected, red when down/unreachable, grey
while checking. Switching mode updates `ConsoleModeProvider` and re-scopes the
sidebar + assignment rail.

### Mode-aware Sidebar

- **Test:** Dashboard · Run · Assignments · Review (current nav).
- **Live:** Live Feed · Assignments · Review.

### AssignmentRail (unified, mode-aware)

Left rail listing assignments for the active mode:

- **Test:** union of `/test_ids` and `/assignments`, each row badged `TEST`.
- **Live:** `/assignments` from the pipeline backend, badged `LIVE`.
- Row content: candidate name, district, tier chip (🔴🟡🟢), ready state.
- Top search/filter box. Hover lift + cyan topline (existing card aesthetic).
- Selecting a row opens the per-assignment workspace.

### Live landing — `LiveFeedPage` (Live mode only)

Stacked glass panels mirroring the production demo:

1. **Bullhorn connection** — `GET /bullhorn/status`: CONNECTED/DOWN badge, user,
   REST endpoint, ping ms, token age; re-check button; animated connection orb.
2. **Auto-poll loop** — `GET /scheduler` + `POST /scheduler/start|stop|poll-now`:
   RUNNING/POLLING/STOPPED chip, animated countdown ring to next poll, stat
   tiles (next poll, last poll, polls run, total processed, new last cycle),
   new-EDU-ID pills, last-error banner. Polls `/scheduler` on a 1s tick for the
   countdown.
3. **Live SSE feed** — agent chips lighting up per agent-complete event (✓/⚠),
   terminal console (reuse `TerminalLog`), attach/detach/clear. Auto-attaches to
   the running scheduler job (`SCH.job_id`) on load.
4. **Manual controls** (collapsible) — process-one (`/process/<aid>`), force-poll
   (`/poll`), rerun (`/rerun/<aid>`), wipe (`/wipe`) with wipe/reread/backup
   toggles. Labeled as operator override.

### Per-assignment workspace (shared by both modes)

Horizontally-scrollable animated tab bar (sliding underline via `layoutId`),
collapsing to a dropdown on narrow screens:

`[📋 Review] [② Intake] [③ Assignment] [④ Requirements] [⑤ Docs] [⑤·⑤ Gate] [⑥ Email] [✉ Preview] [🧩 Audit]`

- **Review** → existing `Checklist`, `ChecklistRow`, `CorrectItemPanel`,
  unmatched-docs list, `FixAgentPanel`.
- **②–⑥ agent tabs** → existing per-agent override panels + `AgentOutputPanel`,
  with override-count badge dots (●N) on the tab.
- **✉ Preview** → existing `EmailPreview`.
- **🧩 Audit** → **new** `AuditPanel`: `GET /assignment/<aid>` → animated vertical
  stepper of the timeline (agent · verdict · duration · errors) + summary (final
  status, total duration, agents run) + raw agent-JSON fetcher
  (`/assignment/<aid>/agent/<n>`) and cost (`/assignment/<aid>/cost`). Audit data
  comes from the backend only — no client-side reconstruction.

## Data flow

1. App boot → `ConsoleModeProvider` reads `sessionStorage` mode, sets
   `activeApiBase`.
2. User toggles Test/Live → provider updates mode + base; sidebar/rail re-scope;
   React Query refetches under the new mode-prefixed keys.
3. Selecting an assignment → workspace tabs lazy-load their data from the active
   backend via existing hooks.
4. Live mode: `LiveFeedPage` polls `/scheduler` (1s), `/bullhorn/status` (30s),
   attaches `EventSource` to the live job for the SSE feed.

## Error handling

- **Pipeline URL unset / unreachable:** Live mode renders, but connection +
  scheduler panels show a clear "Pipeline API not configured/unreachable" state
  (red dot, explanatory copy) instead of throwing. Assignment rail shows an
  empty/error state. Test mode is unaffected.
- **SSE drop:** existing `useSSE` error path (console shows "stream error /
  closed"); attach/detach buttons let the user reconnect.
- **Override rejected (4xx):** existing toast with status + error message.
- **Mode switch mid-stream:** detach any open `EventSource` on mode change.

## Motion & polish (frontend-design pass)

Mode-switch crossfade; tab underline slide (`layoutId`); staggered card
entrance; countdown ring animation; agent chips pop-in on SSE events; status
orbs pulse; skeleton loaders during fetch. All within existing ACAP tokens.

## Components — new vs reused

**New:**
- `src/console/ConsoleModeProvider.jsx` — mode context + base switching.
- `src/console/useModeKey.js` — query-key namespacing helper.
- `src/components/shell/ModeSwitch.jsx` — TopBar segmented control.
- `src/components/live/BullhornStatusCard.jsx`
- `src/components/live/SchedulerPanel.jsx`
- `src/components/live/ManualControls.jsx`
- `src/pages/LiveFeedPage.jsx`
- `src/components/workspace/AssignmentRail.jsx`
- `src/components/workspace/WorkspaceTabs.jsx`
- `src/components/review/AuditPanel.jsx`
- `src/api/bullhorn.js`, `src/api/scheduler.js` (pipeline-only endpoints).

**Reused unchanged (work in both modes via active base):**
- `Checklist`, `ChecklistRow`, `CorrectItemPanel`, `FixAgentPanel`,
  `AgentOutputPanel`, `EmailPreview`, `TerminalLog`, `AgentTicker`,
  `LiveStream`, `RunControls`, all `common/*`.
- `api/{agents,assignments,cost,email,overrides,review,runs}.js`, `useSSE`,
  `apiClient` (after the active-base refactor).

## Testing

- Mode context: switching updates `activeApiBase` and persists to
  sessionStorage; query keys are mode-prefixed.
- `apiClient`: requests hit the active base; `documentUrl`/SSE use active base.
- Graceful degradation: Live mode with unset/unreachable pipeline base shows
  error states, never crashes, and does not affect Test mode.
- `AuditPanel`: renders timeline from `/assignment/<aid>` payload; handles
  missing audit log.
- Manual / visual verification of the Live landing against the production
  pipeline once the port is supplied.

## Open config value

- **Pipeline API port** — same host `52.9.132.43`, port supplied by user; set via
  `VITE_PIPELINE_API_BASE` (or default in `config.js`). Everything else is
  designed to be port-agnostic.

# Cockpit in the Assignments Tab — Design

**Date:** 2026-06-15
**Status:** Approved (pending written-spec review)

## Goal

Replicate the standalone `:8001/ui` cockpit (AEQUOR Credential OS) **inside the React app's Assignments tab**, styled to match the existing ACAP design system. All data comes from live API calls — no previously stored / hard-coded data. Add a new Excel-style spreadsheet section as a 4th cockpit tab.

This is additive to the existing app and intentionally scoped to **test mode only**.

## Scope decisions (locked with user)

| Decision | Choice |
| --- | --- |
| Layout | **A — Cockpit takeover**: two-pane (left = live list, right = sub-tabs) |
| Visual style | **Match the ACAP app** (reuse `useTokens()` theme + existing components), NOT the neon cockpit look |
| Excel placement | **4th tab** in the cockpit: `Step Run / Batch / Mail / Excel` |
| Backend mode | **Test mode only (`:8001`)**. Live mode (`:5001`) keeps its current Assignments list unchanged |
| Excel data source | **Assembled from multiple endpoints** (`/bullhorn_assignments` + per-row `/review/<id>`) |
| Excel loading | **Paginate, 25 rows/page** (core columns instant; `/review` only for the current page) |

## Out of scope

- No changes to live mode (`:5001`) Assignments behavior.
- No new backend endpoints. We build strictly against endpoints `:8001` already exposes. Tracker-only columns the API does not produce (AM, Recruiter, Lead, Date Confirmed, Initial Start Date, New/Rebook/Ext) are omitted.
- Sending emails (no send endpoint exists; Mail is preview-only / "held").
- The neon cockpit aesthetic.

## Architecture

`src/pages/AssignmentsPage.jsx` becomes a thin **mode router**:

```
mode === 'live'  →  <AssignmentsList/>   // current page content, extracted verbatim
mode === 'test'  →  <CockpitView/>       // new
```

- The current page body (filters + tier counts + `AssignmentRow` list + `useAssignments`/`useTestIds`/`useQueries`) is extracted **unchanged** into `src/components/assignments/AssignmentsList.jsx`. Live mode renders exactly as today.
- The cockpit only mounts in test mode, where the active API base is `:8001` (per `ConsoleModeProvider`), which is where `/step_run`, `/bullhorn_assignments`, `/pending_emails`, `/credentialers` live.
- New code lives in `src/components/cockpit/`. Reuse `review/`, `run/`, and `common/` components wherever possible.
- All styling via the existing `useTokens()` tokens (blue `#005280` / `#1DAEEF`, Fraunces + Geist, light + dark).

### Component tree

```
AssignmentsPage (mode router)
├── AssignmentsList                 (live mode — extracted, unchanged)
└── CockpitView                     (test mode — new)
    ├── AssignmentRail              left: /bullhorn_assignments + search + state tags + cost
    │                               single-select (Step Run) / multi-select (Batch)
    ├── CockpitTabs                 [Step Run | Batch | Mail | Excel]
    │   ├── StepRunPanel
    │   │   ├── PipelineTracker      7 nodes: done / wait / run
    │   │   ├── GatePanel            branches by agent (see below)
    │   │   └── TerminalLog          (reused) live telemetry
    │   ├── BatchPanel               multi-select + wipe + /run + LiveStream (reused)
    │   ├── MailPanel                /pending_emails list + PendingEmailPreview
    │   └── ExcelGrid                paginated spreadsheet (25/page)
    └── DocumentDrawer               Drawer (reused) + DocumentViewer (reused), resizable
```

## Components

### AssignmentRail (left pane)
- Source: `useBullhornAssignments()` → `/bullhorn_assignments`.
- Per row: candidate, `#id · school · status`, cost (`cost_usd`), state tag derived from `state`/`processed` (`new` → NEW, `partial` → IN-PROGRESS, `done` → DONE, `failed`/`aborted` → FAILED).
- Search filter over candidate + school.
- Selection model: a single `selectedId` (Step Run, Mail focus) and a `Set` of `batchIds` (Batch). The active tab decides which click behavior applies (mirrors the cockpit's `tab==='step'` vs multi logic).
- `[REDACTED]`/empty candidate names fall back to the agent-2 real name (`realCandidateName`, already used by `AssignmentsList`).

### StepRunPanel
- Start: `useStartStepRun(aid)` → `POST /step_run/<aid>` returns `{ job_id }`.
- Drive: `useStepStatus(jobId)` polls `GET /step_run/<job>/status` (~2.5s) and exposes `{ status, awaiting, steps }`. Also opens `openSSE(jobId, …)` for terminal log lines + event ticker.
- `PipelineTracker` renders the 7 agents from `steps[].agent` (done), `awaiting.agent` (wait), and running state.
- `GatePanel` renders only when `status === 'paused' && awaiting`. Re-render is gated on the gate key (`paused:<agent>`) so open rows / dropdowns don't reset on every poll tick (mirrors cockpit `lastGate`).
- Resume: on mount, read `localStorage['cockpit.stepJob']`; if a job is still alive, reconnect to its gate; if gone (server restart / 404), show a "re-run #aid" affordance. Cleared on complete/abort/fail.

### GatePanel (branch by agent)
- **Generic (1, 2, 4):** `AgentOutputView` (readable key/value, not raw JSON) + `VerifierView` (verdict badge + PASS/WARN/FAIL checks). Agents 1/2 are view-only. Agent 4 allows scalar field corrections.
- **Agent 3 (Assign):** show AI-assigned credentialer; `useCredentialers()` → `/credentialers` populates a reassign dropdown (`credentialer_name` + `credentialer_email`).
- **Agent 5 (Doc Recon):** `OigBanner` (CLEAR / POSSIBLE / CONFIRMED / UNAVAILABLE) + reuse `Checklist` showing each requirement, confidence, status, evidence files → clicking a file opens `DocumentDrawer`. Per-item override of `status` and `matched_file(s)`.
- **Agent 6 (Comms):** `PendingEmailPreview` for the held candidate email.
- **Controls:** Approve (`POST /step_run/<job>/approve` with `{ by, overrides? }`) and Abort (`POST /step_run/<job>/abort` with `{ by }`). Queued overrides accumulate client-side and require the operator email (`by`) before Approve is allowed.

### BatchPanel
- Multi-select from `AssignmentRail` + "wipe previous outputs" checkbox.
- `useRun()` → `POST /run { ids, wipe }` (existing hook) → drive with existing `useSSE`/`LiveStream`.

### MailPanel
- `usePendingEmails()` → `/pending_emails` list (assignment_id, candidate, subject, to, cc, attachments_count, built_at).
- On select: `usePendingEmail(aid)` → `/pending_email/<aid>` → `PendingEmailPreview` (to/cc/subject, attachment chips, sandboxed `html_body` iframe, forms manifest of attached vs skipped files).
- Note: this is **distinct** from the existing `EmailPreview` (which uses `/assignment/<aid>/email`). Existing `EmailPreview` is left untouched for the Review workspace.

### ExcelGrid
- Page 1 loads `useBullhornAssignments()` once → core columns: `# · Candidate · District/School · Bullhorn Status · Run State · Cost`.
- For the 25 rows of the current page, fan out `/review/<id>` (react-query, cached) → enrich: `Tier · Ready · Valid/Expired/Missing · Cred. Coordinator · License/Cert`.
- Rendered as a spreadsheet-style table (sticky header, zebra rows, monospace numerics) using theme tokens. Pager: Prev / Next / page N of M, page size 25.
- Columns with no API source (AM, Recruiter, Lead, Date Confirmed, Initial Start Date, New/Rebook/Ext) are **not** rendered; a small note documents that they are tracker-only.

### DocumentDrawer
- Reuse `common/Drawer.jsx` + `review/DocumentViewer.jsx`. Opened from Agent-5 checklist evidence. Resizable left edge (drag), close button. Document bytes via `documentUrl(aid, file)` → `/review/<aid>/document?file=…`.

## New / changed API modules (`src/api/`)

- `stepRun.js` — `useStartStepRun(aid)`, `useStepStatus(jobId)`, `useApproveStep(jobId)`, `useAbortStep(jobId)`.
- `bullhorn.js` — add `useBullhornAssignments()` → `/bullhorn_assignments`.
- `email.js` — add `usePendingEmails()` → `/pending_emails`, `usePendingEmail(aid)` → `/pending_email/<aid>`.
- `credentialers.js` — `useCredentialers()` → `/credentialers`.
- `lib/sse.js` — extend the `EVENTS` array with `step_paused`, `step_resumed`, `assignment_aborted`, `assignment_complete`, `stream_idle` so EventSource registers listeners for them.

All hooks use the existing `apiClient` (mode-aware base) and `mk()` query keys so they namespace per console mode and never read cached/stored data across modes.

## Data flow

1. CockpitView mounts (test mode) → `AssignmentRail` fetches `/bullhorn_assignments`.
2. Operator selects a candidate → **Step Run**: `POST /step_run/<aid>` → poll `/status` + SSE stream → gate appears → operator approves/overrides/aborts → next agent → completion shows review + held email.
3. **Batch**: multi-select → `POST /run` → SSE live stream until job complete.
4. **Mail**: `/pending_emails` → select → `/pending_email/<aid>` preview.
5. **Excel**: `/bullhorn_assignments` (core) + per-page `/review/<id>` (enrich) → paged table.

## Error handling & edge cases

- **Endpoint missing (404):** each panel shows a clear empty-state ("this backend doesn't expose `/x`") rather than crashing — same fallback pattern as `useBullhornStatus`.
- **Step-run resume:** reconnect to an in-flight gate from `localStorage`; if the job is gone, offer re-run. Clear storage on terminal states.
- **SSE drops / idle gates:** EventSource auto-reconnects; `stream_idle` during a paused gate is normal, never surfaced as an error.
- **Overrides:** require operator email (`by`) before Approve; enforced client-side, consistent with `ALLOWED_EMAILS`.
- **Names:** `[REDACTED]`/empty candidate → agent-2 real name fallback.
- **Large lists:** Excel is paginated; AssignmentRail renders the full `/bullhorn_assignments` list with client-side search (single fetch).

## Testing

Vitest unit tests under `src/**/__tests__` (matching existing setup), logic kept in hooks/helpers so tests need no backend:
- `stepRun` status reducer: pending→paused→approved→complete transitions; gate-key change detection.
- SSE step-event parsing: `step_paused` / `step_resumed` / `assignment_aborted` dispatch.
- Excel: row-assembly merge (bullhorn + review) and pagination math.
- Gate override builder: queued overrides → approve payload `{ by, overrides }`; Approve blocked without `by`.

## Component boundaries (isolation check)

- **Hooks** own all I/O and state shape; components are presentational and thin.
- `AssignmentRail`, `PipelineTracker`, `GatePanel`, `BatchPanel`, `MailPanel`, `ExcelGrid`, `DocumentDrawer` each have one purpose, communicate via props, and are independently understandable/testable.
- `CockpitView` wires selection state + active tab; it holds no business logic beyond orchestration.

# End-to-End Flow + DB-backed Tracker — Architecture Update

**Date:** 2026-06-16
**Supersedes/extends:** `architectur.md`, `2026-06-15-cockpit-assignments-tab-design.md`
**Status:** Approved (decisions confirmed with user)

## 1. The corrected flow (what actually happens)

```
 Bullhorn (EDU placements)
        │  GET /bullhorn_assignments  (already EDU-branch filtered, carries processed/state)
        ▼
 ┌─────────────────────────────────────────────────────────────────┐
 │ ASSIGNMENTS tab (test mode = cockpit)                            │
 │  • lists ALL Education candidates, each tagged new | processed   │
 │  • click NEW/unprocessed  → select → Step Run (guided HITL)      │
 │  • click PROCESSED        → open /review/:id (review + override) │
 └─────────────────────────────────────────────────────────────────┘
        │ run (Step Run per-agent, or Batch via Run Pipeline page)
        ▼
 6-agent pipeline (Flask cockpit :8001)  →  audit_logs/<aid>/ , overrides/ , pending_emails/
        │                                   └─ Agent 6b upserts → SQL Server stg.Assignments_Raw
        ▼
 assignment is now PROCESSED
        │
        ├──▶ /review/:id  works (checklist, documents, Correct/Fix overrides, re-run)
        └──▶ appears in the TRACKER (Excel), which reads stg.Assignments_Raw
```

**Run modes** (unchanged backend):
- **Step Run** (`/step_run/<aid>` → status/approve/abort): per-agent human gate. Used for an individual new candidate.
- **Batch** (`/run`, `/rerun/<aid>`): all 6 agents straight through. Used from the **Run Pipeline** nav page (bulk) and for re-runs after overrides.

Both mark the assignment processed and trigger the Agent-6b DB upsert.

## 2. New component: Node.js Excel/DB service

The Flask APIs are file-based and intentionally **do not expose the SQL DB** to the browser, and their addresses (8001 cockpit / 5001 pipeline / 5002 test) must not change. The Tracker must be **populated from the database** (`stg.Assignments_Raw`). So we add a small, separate read-only service.

- **Location:** `excel-api/` (Node 18+, Express + `mssql`).
- **Port:** `8002` (configurable via `PORT`). Frontend points at it via `VITE_EXCEL_API_BASE` (default `http://localhost:8002`).
- **DB creds from env** (never hard-coded; supports both naming styles): `DB_SERVER`, `DB_DATABASE` (default `AQ_COR_STG`), `DB_USER`/`DB_UID`, `DB_PASSWORD`/`DB_PASS`, `DB_PORT` (default 1433). Reuses the same `.env` the pipeline uses.
- **Endpoints (read-only; never writes the DB):**
  - `GET /health` → `{ ok, db: 'up'|'down' }`.
  - `GET /tracker` → `{ rows: [ ...normalized assignment rows... ] }` from `stg.Assignments_Raw`. Every row here is already an Education + processed assignment (the pipeline only runs EDU placements and only writes a row after processing), so no extra filter is required. Supports optional `?limit`/`?offset`.
  - `GET /tracker/:id` → one row (or 404).
- **Row shape:** normalized to snake_case data keys matching the pipeline (`assignment_id, candidate_name, recruiter, account_manager, start_date, end_date, hospital, discipline, specialty, status, row_status, date_added, job_title, pay_rate, bill_rate, critic_notes, …`) by aliasing the DB columns in the SQL `SELECT`.
- **Resilience:** if the DB is unreachable, endpoints return `503` with a clear message (mirrors the pipeline's graceful DB fallback). Frontend shows an empty/error state, never crashes.
- CORS open (browser on another origin).

> The frontend still uses the **Flask cockpit (8001)** for everything else (assignments list, run, review, overrides, documents, email, dashboard). Only the Tracker grid talks to **:8002**.

## 3. Tracker (Excel) — columns

Order: **ID → screenshot layout → important DB extras.** Source = the Node `/tracker` rows (`stg.Assignments_Raw`). Mapping:

| # | Column (screenshot) | DB source (`Assignments_Raw`) |
|---|---|---|
| 0 | ID | `Assignment_Id` |
| 1 | Start date | `Start_Date` |
| 2 | Name | `Candidate_Name` |
| 3 | Cred. Cord. | — (not in DB; blank — credentialer is agent-3/`credentialers.xlsx`) |
| 4 | Date Confirmed | — (blank) |
| 5 | Initial start date | `Start_Date` (fallback) |
| 6 | District | `Facility_Name` |
| 7 | State | — (blank; `client_state` not persisted) |
| 8 | License/Cert | `Discipline` (e.g. "Paraprofessional (PARA)") |
| 9 | New/Rebook/Ext | — (blank; `Deal_Type` if meaningful) |
| 10 | Last update | `Date_Added` |
| 11 | Onboarding Status | `Rec_Status` (VERIFIED / NEEDS HUMAN REVIEW …) |
| 12 | AM | `Acct_Manager` |
| 13 | Recruiter | `Recruiter_Name` |
| 14 | Lead | — (blank) |
| 15 | Email | — (blank) |

**Important DB extras appended** (by importance): `Assign_Status`, `Job_Title`, `Splty_Unit` (Specialty), `Pay_Rate`, `Bill_Rate`, `End_Date`, `Emp_Type`, `Critic_Notes`.

- AG Grid, every column **sortable + filterable** (floating filters), resizable.
- **Row click → `/review/:id`** (the processed candidate's review/override page).
- Blank-mapped columns (Cred.Cord./State/Lead/Email/etc.) stay until those fields are persisted to the DB; the mapping lives in one place (`src/lib/tracker.js`).

## 4. Frontend changes

- `src/config.js`: add `EXCEL_API_BASE` from `VITE_EXCEL_API_BASE` (default `http://localhost:8002`).
- `src/api/tracker.js`: `useTrackerRows()` → fetch `${EXCEL_API_BASE}/tracker` (its own base, not the mode-switched cockpit base).
- `src/lib/tracker.js`: rewrite `buildTrackerRow(dbRow)` + `TRACKER_COLUMNS` per §3.
- `src/pages/TrackerPage.jsx`: data from `useTrackerRows()` (no more per-row `/review` fan-out), AG Grid, row-click → `/review/:id`, DB-down empty state.
- **Conditional click** (`CockpitView`/`AssignmentRail`): a candidate is "processed" when `assignmentState(a) !== 'new'`. New → select (Step Run). Processed → `navigate('/review/'+id)`. The "Review ↗" button remains for explicit navigation.
- **Dashboard** (`DashboardPage`): real-time via react-query `refetchInterval` (~15s) on the assignments/review aggregation, so tiles/donut/needs-review reflect live runs.
- **Email/`by`**: already defaults to `useAuth().user.email`; keep.
- **Smooth document viewing**: add **Lenis** (`lenis` npm). Wrap the scroll container (review page / document drawer) so long checklists + PDFs scroll smoothly. Keep it tasteful and off for `prefers-reduced-motion`.

## 5. Error handling / edge cases

- Tracker when `:8002` down or DB down → clear "Tracker DB unavailable" empty state (not a crash).
- Clicking a processed candidate whose `/review` 404s → review page already shows its own empty state.
- Node service missing DB env → logs a clear startup warning, `/health` reports `db:'down'`, `/tracker` returns 503.

## 6. Testing

- Node service: unit-test the row-normalizer (DB column → data-key) with a fixture; a `/health` smoke test. (DB integration is manual — can't reach the internal SQL Server from CI.)
- Frontend: `buildTrackerRow(dbRow)` mapper unit tests; TrackerPage renders rows from a mocked `useTrackerRows`; conditional-click logic unit-tested (new→select, processed→navigate).

## 7. Run order (the step-by-step, also in RUN.md)

1. **Flask cockpit** (pipeline + review + run): `python -m api.cockpit_api` → `:8001`. (Needs `.env` with Bullhorn + OpenAI keys.)
2. **Node Excel/DB service**: `cd excel-api && npm install && npm start` → `:8002`. (Reads DB creds from the same `.env`.)
3. **Frontend**: `npm install && npm run dev`. Optionally set `VITE_API_BASE=http://localhost:8001` and `VITE_EXCEL_API_BASE=http://localhost:8002` in the frontend `.env`.
4. Sign in (allow-listed email) → **Assignments**: click a new candidate → **Step Run**; click a processed one → **Review/override**. **Tracker** shows processed rows from the DB. **Dashboard** updates live.

# Cred Tracker — DB-backed, editable onboarding tracker

**Date:** 2026-06-17
**Branch:** feat/cockpit-assignments-tab
**Status:** Approved design → implementation

## Problem

The current Tracker (`src/pages/TrackerPage.jsx`) is a read-only AG-Grid view that reads
`stg.Assignments_Raw` directly. We need a Tracker that:

1. Reads from its **own** dedicated DB table, `stg.Cred_Tracker`.
2. Has some columns populated from the agent pipeline (via API), and some columns
   owned and edited by the credentialer.
3. Supports full CRUD on the editable columns, implemented in the `excel-api` Node/Express service.
4. Has a professional, on-brand, redesigned UI (dark + light), Excel-like per-column
   sort/filter, pagination, smooth scroll (Lenis), micro-interactions (framer-motion),
   and inline single-row editing.

## Architecture & data flow

```
Cockpit API (:8001)                  excel-api (:8002)                 Frontend (TrackerPage)
  GET /assignments       ──┐          ┌─ POST /cred-tracker/sync  ◄──── auto-run on page load
  GET /review/:id         ─┼─fetched─►│    map agent data, UPSERT
  GET /assignment/:id/agent/2 ───────►│    into stg.Cred_Tracker
   (intake agent, real name)          │
                                       │
  stg.Cred_Tracker (SQL Server) ◄──────┤  GET    /cred-tracker      ──► render table (DB only)
                                       │  PATCH  /cred-tracker/:id   ──► save edited row
                                       └─ DELETE /cred-tracker/:id   ──► remove row
```

- The Tracker UI **only reads `stg.Cred_Tracker`**. It never reads `Assignments_Raw`.
- `POST /cred-tracker/sync` is the only bridge to agent data. It calls the cockpit API,
  transforms the output to `Cred_Tracker` columns, and upserts.
- **Sync preserves credentialer edits:** agent-owned columns are refreshed on every sync;
  the 7 credentialer-owned columns are written only on first INSERT, never on re-sync.
- Sync trigger: **auto-run once on every Tracker page load** (fire POST /cred-tracker/sync,
  then GET /cred-tracker). A manual "Sync" button is also provided as a convenience.

## DB table: `stg.Cred_Tracker`

| Column | Type | Source | Editable |
|---|---|---|---|
| `Assignment_Id` | INT, PK | /assignments | no |
| `Candidate_Name` | NVARCHAR(200) | intake agent (real name) | no |
| `Start_Date` | DATE | intake (seed only) | **yes** |
| `Credentialer` | NVARCHAR(200) | assignment agent | **yes** |
| `Date_Confirmed` | DATE | credentialer | **yes** |
| `Initial_Start_Date` | DATE | intake (snapshot at first seed) | no |
| `District` | NVARCHAR(300) | intake | no |
| `State` | NVARCHAR(100) | intake | no |
| `License_Cert` | NVARCHAR(300) | intake | no |
| `New_Rebook_Ext` | NVARCHAR(50) | intake (parsed job-title prefix, e.g. ESY→EXT) | **yes** |
| `Last_Updated` | DATE | credentialer | **yes** |
| `Onboarding_Status` | NVARCHAR(MAX) | credentialer (note) | **yes** |
| `AM` | NVARCHAR(200) | intake | no |
| `Recruiter` | NVARCHAR(200) | intake | no |
| `Lead` | NVARCHAR(200) | credentialer | **yes** |
| `Updated_By` | NVARCHAR(200) | audit (user email) | auto |
| `Updated_At` | DATETIME2 | audit | auto |
| `Synced_At` | DATETIME2 | last agent sync timestamp | auto |

**Editable columns (7):** `Start_Date`, `Credentialer`, `Date_Confirmed`,
`New_Rebook_Ext`, `Last_Updated`, `Onboarding_Status`, `Lead`.

**Non-editable agent columns (8):** `Candidate_Name`, `Initial_Start_Date`, `District`,
`State`, `License_Cert`, `AM`, `Recruiter`, plus `Assignment_Id` (PK).

### Upsert rule (in `POST /cred-tracker/sync`)
- For each assignment id returned by the cockpit API:
  - **If the row does not exist:** INSERT all mapped columns. `Initial_Start_Date` = mapped `Start_Date`.
    Credentialer-owned columns get their seed defaults (Start_Date from intake, Credentialer
    from assignment agent, New_Rebook_Ext from parsed prefix; Date_Confirmed / Last_Updated /
    Onboarding_Status / Lead start NULL/empty).
  - **If the row exists:** UPDATE only the 8 non-editable agent columns + `Synced_At`.
    Never overwrite the 7 editable columns.

## Backend (excel-api)

New module `excel-api/credTracker.js`:
- `ensureCredTrackerTable(pool)` — idempotent `IF NOT EXISTS ... CREATE TABLE stg.Cred_Tracker` DDL. Run on first request.
- `mapAgentToRow(assignment, review, intake)` — pure function mapping cockpit API payloads
  → `Cred_Tracker` column object. Includes `parseNewRebookExt(jobTitle)` helper
  (prefix tokens like `ESY` → `EXT`; default `New`). **Unit tested.**
- `upsertRows(pool, rows)` — INSERT-or-refresh preserving editable columns. **Unit tested** for
  the preserve-edits behavior (logic-level test against the SQL builder / a fake).
- `EDITABLE_COLUMNS` whitelist used by PATCH so non-editable columns can never be written.

Routes added to `excel-api/index.js`:
- `GET /cred-tracker` → `{ rows: [...] }` (normalized snake_case keys, consistent with existing `/tracker`).
- `GET /cred-tracker/:id` → single row or 404.
- `POST /cred-tracker/sync` → fetches cockpit API (`COCKPIT_API_BASE`, default `http://localhost:8001`),
  maps, upserts, returns `{ synced: <count> }`. Uses Node global `fetch` (no new dep). On cockpit-API
  failure, returns 502 with detail but does not corrupt existing rows.
- `PATCH /cred-tracker/:id` body `{ fields: {...}, updated_by }` → updates only whitelisted editable
  columns + `Updated_By`/`Updated_At`. Returns the updated row.
- `DELETE /cred-tracker/:id` → deletes the row, returns `{ deleted: true }`.

Env: add `COCKPIT_API_BASE` to `.env` handling (default `http://localhost:8001`).

### Cockpit field mapping (finalized against live agent-2 / agent-3 payloads)
Sync calls, per id: `GET /assignment/:id/agent/2` (Intake) and `GET /assignment/:id/agent/3` (Assignment).
Id list from `GET /assignments` (live) — for Test mode, `GET /test_ids`.

From **Intake (agent 2)** — real name from `output.verifier.checks[name="field_candidate_name"].actual`
(port `realCandidateName`/`isRedacted` from `src/lib/redact.js`); other fields from `output`:
- `Assignment_Id` ← `output.assignment_id`
- `Candidate_Name` ← verifier real name (NULL if still redacted)
- `Start_Date` / `Initial_Start_Date` ← `output.start_date`
- `District` ← `output.hospital`
- `State` ← `output.client_state`
- `License_Cert` ← `output.discipline`
- `AM` ← `output.account_manager`
- `Recruiter` ← `output.recruiter`
- `New_Rebook_Ext` ← `parseNewRebookExt(output.job_title)`

From **Assignment (agent 3)** `output`:
- `Credentialer` ← `output.credentialer_name` (NULL if redacted/empty)

**Value cleaning:** any value matching `/^MISSING:/i` or `/REDACT/i` (or null/empty) maps to NULL/blank
(reuse the `clean`/`isRedacted` idea). Example: `account_manager: "MISSING: account_manager"` → blank AM.

**`parseNewRebookExt(jobTitle)`** (case-insensitive, editable afterward):
- contains `ESY` → `EXT`
- contains `Renewal` or `Rebook` → `Rebook`
- otherwise → `New`

## Frontend

Replace `src/pages/TrackerPage.jsx` with a custom Tailwind table.

- **Lib:** add `@tanstack/react-table` (headless) for sort/filter/pagination state. All visuals Tailwind.
- **Theme:** two looks via existing `useTokens()` — dark (`#0C111D` bg, `#5BA8FF` accent) and
  light (`#1E6FE0` accent). Geist font, JetBrains Mono for ids/dates.
- **Columns:** the 15 data columns above + an Actions column (Review / Edit / Remove).
  Per-column header click = sort; header input = filter. Pagination 25/page (selector 25/50/100).
- **Smooth scroll:** Lenis on the horizontal/vertical table scroll container (respect existing
  `data-lenis-prevent` patterns used elsewhere).
- **Micro-interactions (framer-motion):** row mount stagger, edit-row highlight/expand,
  button press/hover states.
- **Inline edit:** click ✏️ on a row → only that row's **editable** cells turn into inputs
  (native date input for dates, text/textarea for others). Save/Cancel appear in the Actions cell.
  Non-editable cells remain static text. Save → `PATCH` with optimistic react-query update;
  Cancel → revert.
- **Review** action → `navigate('/review/:id')`.
- **Remove** action → confirm dialog → `DELETE`, optimistic removal.
- **States:** loading skeletons (reuse `Skeleton`), error ("Tracker DB unavailable — is :8002 running?"),
  empty ("No tracked assignments yet — run a sync").

New `src/api/credTracker.js` (react-query, against `EXCEL_API_BASE`):
- `useCredTracker()` — GET list.
- `useSyncCredTracker()` — POST sync (called on mount, then invalidates list).
- `useUpdateCredRow()` — PATCH, optimistic.
- `useDeleteCredRow()` — DELETE, optimistic.

The pure row/column mapping moves into `src/lib/credTracker.js` (replacing the
`Assignments_Raw`-based `src/lib/tracker.js` usage for this page), keeping React-free,
unit-testable helpers (`buildCredRow`, `CRED_COLUMNS`, `EDITABLE_FIELDS`).

## Testing

- **Backend (node:test, alongside `normalize.test.js`):**
  - `parseNewRebookExt` prefix parsing (ESY→EXT, plain→New, etc.).
  - `mapAgentToRow` produces correct column object incl. redaction skips.
  - Upsert preserves editable columns on re-sync (logic-level).
- **Frontend (vitest, adapt `TrackerPage.test.jsx`):**
  - Renders rows from mocked `useCredTracker`.
  - Edit toggles only that row's editable cells into inputs; non-editable stay static.
  - Save calls the update mutation with whitelisted fields only.
  - Remove triggers confirm + delete mutation.
  - Review action navigates to `/review/:id`.

## Out of scope (YAGNI)

- Full per-field audit log table (using lightweight `Updated_By`/`Updated_At` only).
- Changing the cockpit/pipeline (8001/5001) backends.
- Bulk edit / multi-row select.
- Server-side pagination (client-side is fine at current row volume).

# Background Batch Pipeline Runs + Tracker scroll fix

**Date:** 2026-06-22
**Branch:** feat/cockpit-assignments-tab
**Status:** Approved design → implementation

## Problem

The Run Pipeline page (`src/pages/RunPage.jsx`) starts a run (`POST /run`) and watches it via
`useSSE`, but the SSE state lives *inside the page component*. Navigating away unmounts it, the
stream closes, and the live view is lost. We need:

1. A picker on Run Pipeline that lists assignments (NEW + DONE), lets the user select **1–10**,
   and on Confirm runs the full agent pipeline for exactly those ids.
2. The run to **keep going in the background** across page navigation, with the live flow shown
   again when the user returns — and to **survive a full browser refresh**.
3. An **Abort** ("Stop watching") control.
4. On completion, the processed candidates **saved to the DB and shown in the Tracker** automatically.
5. Polished UI (Tailwind, dark/light, framer-motion micro-interactions, Lenis).
6. Fix the **Tracker vertical scroll** which currently doesn't work.

## Architecture & data flow

```
main.jsx
  └─ RunProvider (ABOVE the router — never unmounts on navigation)
       owns: jobId, sse state (status/agentsByAid/logLines/results), selectedIds
       actions: startRun(ids,opts) → POST /run ; stopWatching() ; resume-on-load via GET /jobs
       │
       ├─ AppShell / TopBar  → "pipeline running" pill (visible everywhere while running)
       ├─ RunPage            → picker (idle) OR live view (running) — a VIEW of provider state
       └─ on job_complete    → POST /cred-tracker/sync (+ invalidate tracker query)
```

- The cockpit (`:8001`, currently the only mode — live is disabled) exposes `POST /run` (`{ ids, wipe,
  reread, backup }` → `{ job_id }`), SSE per job, and `GET /jobs` (`{ jobs: [{ job_id, last_event,
  metadata: { assignment_ids } }] }`).
- There is **no batch-cancel endpoint** on the cockpit (verified: all `/abort` routes 404). Abort is
  therefore a frontend "stop watching", not a server cancel.

## Components & responsibilities

### `src/run/RunProvider.jsx` (NEW) — global run state
- React context mounted in `main.jsx` wrapping the router.
- Holds: `jobId`, `status` (`idle|running|done|failed`), `agentsByAid`, `logLines`, `results`,
  `selectedIds`, `startedAt`, `error`.
- Internally runs the SSE subscription (the logic currently in `useSSE`) so it lives at app scope.
  `useSSE` is refactored: its event-reduction logic is reused by the provider (extract a pure
  `reduceSseEvent(state, type, data)` reducer so it is unit-testable without a live socket).
- Actions:
  - `startRun(ids, opts)` → `POST /run` `{ ids, wipe:false, reread:false, backup:true, ...opts }`,
    store `job_id`, persist `{ job_id, ids }` to `localStorage['acap.activeRun']`, open SSE.
  - `stopWatching()` → close SSE, clear state + localStorage. Does NOT call the backend.
  - On mount: read `localStorage['acap.activeRun']`; also `GET /jobs` and adopt the most recent job
    whose `last_event` ∉ {`job_complete`,`job_failed`} (prefer the localStorage job_id if it's still
    running). Re-open its SSE and seed `selectedIds` from `metadata.assignment_ids`.
  - On `job_complete`: set status `done`, fire `POST /cred-tracker/sync` (best-effort, ignore failure),
    invalidate the `['cred-tracker','rows']` query, keep the completed summary visible until dismissed,
    clear localStorage active run.
- Exposes `useRunState()` hook. Throws if used outside the provider.

### `src/pages/RunPage.jsx` (REWRITE) — picker + live view
- Reads `useRunState()`. If `status === 'idle'` (no active run) → **Picker**; else → **Live view**.
- **Picker** (`src/components/run/AssignmentPicker.jsx`, NEW):
  - Loads ids via `useAssignments()` (live ids) and per-id `useReview` (status/tier/name) — same data
    path as `AssignmentsList`. Shows NEW vs DONE via a badge (DONE = has a review/processed).
  - Checkbox per row; **hard cap 10**: once 10 are selected, unchecked rows are disabled with a hint;
    a "N / 10 selected" counter. Search box (candidate/district/id).
  - **Confirm & Run** (disabled until ≥1 selected) → `startRun(selectedIds)`.
- **Live view** (`src/components/run/RunLiveView.jsx`, NEW):
  - Overall batch progress (done / total from `results` vs `selectedIds`).
  - Per-assignment rows showing the 7-agent pipeline advancing (reuse `LiveStream` / `agentsByAid`).
  - Streaming log (reuse existing log rendering).
  - **Stop watching** button → `stopWatching()`, with tooltip explaining no server-side cancel.
  - On `done`: success summary + a link/CTA to the Tracker; **Run another batch** resets to picker.

### `src/components/shell/TopBar.jsx` (MODIFY) — running pill
- When `useRunState().status === 'running'`, show a small animated "Pipeline running · X/N" pill that
  navigates to `/run` on click. Hidden otherwise.

### Tracker scroll fix (`src/pages/TrackerPage.jsx`, MODIFY)
- Root currently `className="flex flex-col h-full …"`. `h-full` doesn't resolve (AppShell's `<main>`
  content wrapper is auto-height), so the inner `overflow-auto` container is content-tall and never
  scrolls; the scoped Lenis then swallows wheel events. Fix: bound the page to the viewport —
  set the root height to `calc(100vh - 54px)` (TopBar is 54px) so `flex-1 min-h-0` bounds the scroll
  container and Lenis drives internal scrolling. No other behavior changes.

## UI / animation
- Tailwind + `useTokens()` tokens (dark/light), Geist / JetBrains Mono, brand accents.
- framer-motion: picker row mount stagger + selection pop/scale, picker→live `AnimatePresence`
  transition, per-agent step fill, TopBar pill entrance.
- Lenis on the picker scroll list (via existing `useLenisScroll`).
- No GSAP (framer-motion + Lenis cover the needs; keep deps lean).

## Testing
- **`reduceSseEvent`** (pure): agent events accumulate per aid; `assignment_done` appends results;
  `job_complete`/`job_failed` set terminal status. (vitest)
- **RunProvider**: `startRun` posts ids and opens a (mocked) stream; resume-on-load adopts a running
  job from a mocked `GET /jobs`; `job_complete` triggers the cred-tracker sync mutation. (vitest, mocked fetch/SSE)
- **AssignmentPicker**: selection cap (cannot select an 11th; counter shows N/10); Confirm calls
  `startRun` with the selected ids. (vitest)
- **TrackerPage**: existing tests still pass (scroll fix is a style-only change).

## Out of scope (YAGNI)
- Server-side run cancellation (no cockpit endpoint; Abort is stop-watching).
- Re-enabling live mode (remains disabled).
- Per-assignment retry/queue management beyond the single batch.
- Persisting full stream history across refresh (we re-attach the live stream; past log lines before
  re-attach are not back-filled).

# Design: Historical Dashboard, Realtime Activity Feed, and Agent-3 Verify

Date: 2026-07-06
Status: Approved (pending final spec review)

Three independent features, implemented in this order:

1. **Historical dashboard** — persist a daily snapshot of dashboard metrics to SQL Server
   (`stg.Cred_Dashboard` + `stg.Cred_Dashboard_Detail`) and let the user view any date
   range, with preset tabs for the last 30 / 60 / 90 days.
2. **Realtime activity feed** — remove the raw "Live telemetry" terminal from the Cockpit
   step-run and the Run-Pipeline batch views; replace it with a polished loading state and a
   live activity feed (which assignment is processing, which agent finished, which documents
   were handled).
3. **Agent-3 credentialer button** — verify the existing "Reassign credentialer" control at
   the Agent-3 gate works correctly; add coverage if missing.

---

## Background / current state

- **Dashboard** ([src/pages/DashboardPage.jsx](../../../src/pages/DashboardPage.jsx)) fetches all
  live assignment IDs, then `/review/{id}` per ID, and aggregates client-side into tiles, a tier
  donut, a needs-review list, a status breakdown, and a cost-by-agent bar. Nothing is persisted —
  it always shows "right now."
- **Backends**: Cockpit API (`:8001`) and Live Pipeline API (`:5001`) are external (Python, not in
  this repo). **excel-api** (`:8002`, in this repo — Node + Express + `mssql`, schema `stg`) is the
  only service here with DB access; it already owns `stg.Cred_Tracker`. `stg.Cred_Dashboard` belongs
  here.
- **"Live telemetry"** renders the raw `TerminalLog` in two places:
  - [src/components/cockpit/StepRunPanel.jsx](../../../src/components/cockpit/StepRunPanel.jsx) (Cockpit step-run)
  - [src/components/run/LiveStream.jsx](../../../src/components/run/LiveStream.jsx) (Run-Pipeline batch)
- **SSE event vocabulary** (from [src/lib/sse.js](../../../src/lib/sse.js) and
  [src/run/sseReducer.js](../../../src/run/sseReducer.js)): `batch_start`, `assignment_start`,
  `agent_1_complete`…`agent_6_complete`, `agent_5_5_complete` (each with `assignment_id`,
  `duration_s`), `assignment_done` (carries the full review payload), `assignment_failed`,
  `assignment_aborted`, `job_complete`, `job_failed`, and raw text `log` lines. **There is no
  structured document-download event** — documents are knowable reliably only from a completed
  review payload, or heuristically by scanning `log` text.
- **Agent-3 reassign** already exists in
  [src/components/cockpit/GatePanel.jsx](../../../src/components/cockpit/GatePanel.jsx) (`Agent3Reassign`,
  rendered when `awaiting.agent === '3'`), backed by `useCredentialers()`.

---

## Feature 1 — Historical dashboard

### Data model (excel-api, schema `stg`, auto-created idempotently like `Cred_Tracker`)

**`stg.Cred_Dashboard`** — one row per snapshot date (daily aggregate):

| Column | Type | Notes |
|---|---|---|
| `Snapshot_Date` | `DATE` | PRIMARY KEY |
| `Total_Candidates` | `INT` | triaged set (RED+YELLOW+GREEN), matches current tile logic |
| `Red` / `Yellow` / `Green` | `INT` | tier counts |
| `Ready` | `INT` | placement-ready |
| `Total_Cost_USD` | `DECIMAL(12,4)` | sum of `cost.total_usd` |
| `Docs_Missing` | `INT` | sum of `counts.missing` |
| `Auditor_Flags` | `INT` | sum of `counts.auditor_flags` |
| `Updated_At` | `DATETIME2` | last upsert time |

**`stg.Cred_Dashboard_Detail`** — one row per assignment per snapshot date:

| Column | Type | Notes |
|---|---|---|
| `Snapshot_Date` | `DATE` | part of PK |
| `Assignment_Id` | `INT` | part of PK |
| `Candidate_Name` | `NVARCHAR(200)` | |
| `Tier` | `NVARCHAR(10)` | RED / YELLOW / GREEN / NULL |
| `Ready` | `BIT` | |
| `Cost_USD` | `DECIMAL(12,4)` | `review.cost.total_usd` |
| `Cost_By_Agent` | `NVARCHAR(MAX)` | JSON, `review.cost.by_agent` (drives cost-by-agent chart) |
| `Valid` / `Expired` / `Missing` / `Auditor_Flags` | `INT` | `review.counts.*` |
| `District` | `NVARCHAR(300)` | |

PK on `(Snapshot_Date, Assignment_Id)`. The detail table gives full fidelity so every existing
chart (Needs-Review list, cost-by-agent, status breakdown, donut) is reproducible for past dates.

> Note: `Cost_By_Agent` will store whatever shape `review.cost.by_agent` has today; the
> implementation plan must confirm the exact key before wiring the historical cost chart. If the
> live payload does not expose per-agent cost, the historical cost-by-agent chart degrades to using
> `Cost_USD` totals only, and this is called out in the plan.

### Snapshot write — auto-upsert on dashboard load

- The dashboard already computes the aggregate and holds every per-assignment review. When **all**
  review queries have loaded (`loadedCount === ids.length`, i.e. not `anyLoading`) **and** the
  active view is "Today (Live)", the page POSTs one payload to excel-api:

  ```
  POST /dashboard/snapshot        (guarded by the cred-tracker write token)
  { date: "YYYY-MM-DD",
    aggregate: { total, red, yellow, green, ready, cost, missing, flags },
    detail: [ { assignment_id, candidate, tier, ready, cost, cost_by_agent, valid, expired, missing, auditor_flags, district }, … ] }
  ```

- excel-api MERGE-upserts: replaces today's aggregate row and today's detail rows (delete-then-insert
  by `Snapshot_Date`, or `MERGE`). Idempotent — revisiting the dashboard the same day just refreshes
  today's snapshot.
- The frontend sends the data (it already has it); excel-api does **not** re-fetch from the cockpit.
  This avoids duplicating aggregation logic server-side. The write is fire-and-forget and best-effort
  (a failed snapshot must never break the dashboard render). Fire it at most once per page mount
  (guarded by a ref) to avoid a write on every 15s refetch.

### Snapshot read — date range + presets

- New endpoint: `GET /dashboard?start=YYYY-MM-DD&end=YYYY-MM-DD`
  → `{ aggregates: [ …daily rows… ], detail: [ …per-assignment rows for the range… ] }`.
- Dashboard gains a control bar with tabs:
  **Today (Live)** · **Last 30 days** · **Last 60 days** · **Last 90 days** · **Custom**.
  - **Today (Live)** = current behavior (live fetch + snapshot write on load).
  - Presets/Custom = read from excel-api; **Custom** reveals two date inputs (start, end).
- **Reuse the existing charts unchanged**: detail rows are reshaped into the same
  `{ assignment_id, review: { hitl_tier, ready, cost: { total_usd, by_agent }, counts: { valid, expired, missing, auditor_flags }, candidate, district } }`
  shape the chart components already consume. For a multi-day range, the reshaped set is the union of
  detail rows across the range (each day's assignments), so tiles/donut/breakdowns aggregate exactly
  as they do live. A small mapping helper (pure, unit-tested) does this reshape.
- **Empty-state caveat**: presets show nothing until snapshots accumulate — past dates were never
  stored and cannot be backfilled. When a historical range returns no rows, show an explicit empty
  state ("Historical data starts accumulating from <first-snapshot-date>. Check back after a few
  days of runs."). The page header's "date" line reflects the selected range instead of only today.

### excel-api module layout

- New `excel-api/dashboard.js`: `ensureDashboardTables(pool)`, `upsertSnapshot(pool, payload)`,
  `getRange(pool, start, end)`. Mirrors the structure/style of `credTracker.js`.
- New routes in `excel-api/index.js`: `POST /dashboard/snapshot` (token-guarded), `GET /dashboard`.
- Frontend `src/api/dashboardHistory.js`: `useDashboardRange(start, end)` (react-query) and a
  `postSnapshot(payload)` helper, both hitting `EXCEL_API_BASE` with `NGROK_SKIP_HEADER` (and the
  write token on POST), matching [src/api/tracker.js](../../../src/api/tracker.js).

---

## Feature 2 — Realtime activity feed (replaces raw telemetry)

### Scope

- Remove the raw `TerminalLog` rendering from **both** `StepRunPanel` and `LiveStream`. The raw log
  is removed from the UI entirely (no toggle). `logLines` are still **accumulated in state** so the
  document parser can mine them; they are simply not rendered as a terminal.
- `TerminalLog.jsx` may remain in the repo unused, or be deleted if nothing else imports it (the plan
  checks importers).

### New shared component: `src/components/run/ActivityFeed.jsx`

Props: `{ status, events, agentsByAid, results, logLines }` (same data both views already have).

- **Loading state** (before the first meaningful event): a polished animated placeholder —
  shimmer/skeleton rows + spinner + a "Waiting for the pipeline…" / current-phase label. Uses the
  existing token/theme system and animation classes already in the codebase.
- **Activity timeline**: newest-last vertical feed, one entry per structured event, animated in:
  - `assignment_start` → "▶ Assignment #<id> — processing started"
  - `agent_N_complete` → "✓ Agent N · <name> — <duration>s" (names from the existing
    `AGENT_LOG_LABELS` map)
  - `assignment_done` → "✓ Assignment #<id> complete — <tier emoji> <TIER> · <valid> valid, <missing> missing"
  - `assignment_failed` / `assignment_aborted` → error/aborted entry
- **Documents per assignment**:
  - **Reliable (on completion)**: from the `assignment_done` review payload — union of checklist
    `matched_files` and `unmatched_documents` — shown as "Documents processed (<n>)" under the
    completed entry.
  - **Best-effort (live)**: a pure helper `parseDocsFromLog(logLines)` scans lines for filename-like
    tokens (`.pdf`, `.png`, `.jpg`, `.jpeg`, `.docx`, `.doc`, `.tif`, `.tiff`) and/or the words
    `download`/`downloaded`/`saved`, de-duplicated, attributed to the current in-flight assignment
    when an id is present. Surfaced as a live "Documents" sub-list. Heuristic — documented as
    depending on what the backend logs; the reliable completion list is the source of truth.

### Wiring

- `LiveStream` / `RunLiveView` already have `events`, `agentsByAid`, `results`, `logLines` from
  `RunProvider` — swap `TerminalLog` for `ActivityFeed`. The candidate-card section may stay; the
  feed replaces the terminal block at the bottom.
- `StepRunPanel` uses `useStepRun`, which today only accumulates `logLines`. **Extend `useStepRun`**
  to also reduce structured events into `events` / `agentsByAid` / `results` by reusing
  `reduceSseEvent` (the same reducer `RunProvider` uses), then pass those into `ActivityFeed`. This
  unifies both views on one data model. The `STATUS_META.failed.sub` copy in `StepRunPanel`
  ("Check the live telemetry below") is updated to reference the activity feed.

### Non-goals

- No backend changes to emit document-download events (out of our repo). If the backend later emits a
  structured `document_downloaded` event, the feed can consume it with a small addition.

---

## Feature 3 — Agent-3 credentialer button (verify)

- Confirm `Agent3Reassign` renders only at the Agent-3 gate (`awaiting.agent === '3'`), the roster
  loads via `useCredentialers()` (`{ credentialers: [{ name, email, workload }] }`), and selecting a
  credentialer queues overrides `credentialer_name` + `credentialer_email` that flow through
  `approvePayload` to `POST /step_run/<job>/approve`.
- Verify by exercising the gate (drive an assignment to the Agent-3 pause, or a targeted test) and
  confirming the override reaches `onApprove`. Add a focused test in
  [src/components/cockpit/__tests__/GatePanel.test.jsx](../../../src/components/cockpit/__tests__/GatePanel.test.jsx)
  asserting an Agent-3 gate renders the reassign select and that choosing an option sends
  `credentialer_name`/`credentialer_email` on approve. Fix only if a defect is found; otherwise this
  is confirmation + coverage.

---

## Testing

- **excel-api**: unit tests for `dashboard.js` upsert/range SQL builders and payload validation
  (mirroring `test/credTrackerMap.test.js` style); a shape test for `GET /dashboard`.
- **Frontend**:
  - Pure reshape helper (detail rows → chart `{ assignment_id, review }`) — unit-tested.
  - `parseDocsFromLog` — unit-tested against sample log lines (hits and misses).
  - Date-range control: renders tabs, Custom reveals inputs, selecting a preset triggers the range
    query with correct start/end.
  - `ActivityFeed`: renders loading state with no events, renders entries for a scripted event
    sequence, lists documents from a completed review payload.
  - `useStepRun`: accumulates structured events (feeding a scripted SSE sequence through the reducer).
  - `GatePanel`: Agent-3 reassign coverage (Feature 3).

## Rollout / ordering

1. Feature 1 (DB tables + endpoints + date-range UI).
2. Feature 2 (activity feed + `useStepRun` extension + remove raw log).
3. Feature 3 (verify + test).

Each feature is independently shippable and testable.

# Cockpit: Run + Review, Batch, Watchdog — and existing-feature drift repair

**Date:** 2026-07-30
**Status:** Approved design, pending spec review
**Reference:** `src/context.html` (self-contained HTML/JS cockpit demo — the behavioral source of truth)

## 1. Goal

Bring the React cockpit (`src/components/cockpit/*`, reached via `AssignmentsPage` → `CockpitView` in Test mode) to
functional parity with `context.html`. That means:

1. **Add three new tabs** — RUN + REVIEW, BATCH, WATCHDOG.
2. **Repair drift** in the two existing tabs (STEP RUN, MAIL) where `context.html` has behavior the React app dropped.

The `.env` file and its backend base URLs (`VITE_API_BASE`, `VITE_PIPELINE_API_BASE`, `VITE_EXCEL_API_BASE`) are **not**
to be changed. All backend calls go through the existing `apiClient` + `config.js` base-URL selection.

## 2. Constraints

- **Component-based.** Each feature is a small tree of focused components with clear props; no monolith files.
- **Pure Tailwind classes for styling.** No `useTokens()`, no inline `style={{}}` color objects in new/edited code.
  Use the theme-aware Tailwind color utilities defined in `src/styles/globals.css` `@theme` (backed by CSS vars in
  `src/styles/theme.css` that flip on `[data-theme="dark"]`): `brand-*` (primary, sky, ink, mid, accent, bg, bg-2,
  surface), `status-*` (valid, expiring, expired, wrong, missing, unread), `tier-*` (red, yellow, green),
  `text-strong` / `text` / `text-muted`, `tok-*`, plus fonts `font-display` / `font-mono`. Arbitrary values
  (`bg-[#0b1220]`, `border-brand-ink/15`) are allowed — they are still Tailwind. This keeps light/dark working.
- **Reuse before building.** The existing reusable components and API hooks are used as-is where possible.
- **Existing STEP RUN / MAIL behavior is only added to, never regressed.** Their current tests must keep passing.
- **Tests** (Vitest, colocated `__tests__/`) for the new logic and the drift repairs.

## 3. What already exists and is reused unchanged

- Components: `PipelineTracker`, `VerifierView`, `AgentOutputView`, `OigBanner`, `DocumentDrawer`, `CockpitTabs`
  (extended), `PendingEmailPreview` (extended, see §6.5).
- API hooks: `useRun`, `useJobs` (`api/runs.js`), `useReview` (`api/review.js`), `useOverrides` / `useSetOverride`
  (`api/overrides.js`), `useCredentialers`, `usePendingEmails` / `usePendingEmail` (`api/email.js`),
  `useAgentOutput` (`api/agents.js`), `useBullhornAssignments` (`api/bullhorn.js`).
- Infra: `openSSE` / `sseLine` (`lib/sse.js`), `reduceSseEvent` / `INITIAL_SSE_STATE` (`run/sseReducer.js`),
  `useSessionState`, `apiClient` (`get`/`post`/`del`, `documentUrl`), `mk()` query-key namespacing.
- The `/run` + `/stream` SSE events used by Batch and Run+Review (`batch_start`, `assignment_start`,
  `assignment_done`, `agent_*_complete`, `job_complete`, `job_failed`, `log`) are **already registered** in
  `sse.js`'s `EVENTS` array — **no SSE changes required**.

## 4. New API hooks

| File | Hook | Method + path | Notes |
|---|---|---|---|
| `api/watchdog.js` | `useWatchdogStatus()` | `GET /watchdog/status` | `{ scanner_thread_alive, interval_min, last_scan_at }`; `refetchInterval` ~30s |
| | `useWatchdogResults()` | `GET /watchdog/results` | `{ results: [...] }` |
| | `useWatchdogResult(aid)` | `GET /watchdog/results/{aid}` | `enabled: !!aid` |
| | `useWatchdogScan()` | `POST /watchdog/scan` | mutation; invalidates results + status on success |
| `api/lookup.js` | `useLookupId()` | `GET /lookup/{id}` | mutation (imperative, fires on button); returns `{ kind:'placement'\|'candidate', placement?, candidate?, placements? }` |
| `api/requirements.js` | `useRequirements(aid)` | `GET /requirements/{aid}` | `enabled: !!aid`; district requirements payload for the Agent-4 table |
| `api/runs.js` (extend) | `useJob(jobId)` | `GET /jobs/{id}` | polls (`refetchInterval` 3s) until `status ∈ {complete, failed}`; `enabled: !!jobId` |
| `api/bullhorn.js` (or new `api/bullhornNotes.js`) | `usePendingBullhorn()` | `GET /pending_bullhorn` | held Bullhorn notes list |
| | `usePendingBullhornNote(aid)` | `GET /pending_bullhorn/{aid}` | `enabled: !!aid`; `{ found, candidate_name, candidate_id, hospital, comments }` |
| | `useApproveBullhorn(aid)` | `POST /pending_bullhorn/{aid}/approve` | mutation; invalidates the list |
| | `useRejectBullhorn(aid)` | `POST /pending_bullhorn/{aid}/reject` | mutation, body `{ reason }`; invalidates the list |

All query keys namespaced with `mk(...)`.

## 5. New orchestration hook — `hooks/useRunJob.js`

A single hook that drives a full-pipeline `/run` job (no gates) and tracks it to completion. Shared by **BATCH** and
**RUN + REVIEW** (and reusable anywhere a non-gated run is launched).

```
useRunJob() → {
  start(ids: (number|string)[], wipe: boolean),  // POST /run { ids, wipe } → sets jobId, opens SSE
  jobId,
  status,          // 'idle' | 'running' | 'complete' | 'failed'  (derived from useJob + SSE)
  logLines,        // string[] from SSE 'log' events (via sseLine), capped
  agentsByAid,     // { [aid]: [events] } via reduceSseEvent
  results,         // assignment_done payloads
  job,             // useJob(jobId) data (has result.ok / result.total for batch summary)
  reset(),
}
```

Implementation: `start` calls `useRun().mutateAsync`, stores `job_id`, connects `openSSE(jobId, handlers)` feeding
`reduceSseEvent` (same pattern as `useStepRun`), and enables `useJob(jobId)` polling. Terminal when
`useJob` reports `complete`/`failed` **or** a `job_complete`/`job_failed` SSE arrives; on terminal it closes the
stream and invalidates `mk('bullhorn_assignments')`. Unmount closes the stream.

## 6. Components

### 6.1 Shared building blocks (also heal STEP-RUN drift — §7)

- **`cockpit/RequirementsTable.jsx`** — `props: { data }`. Renders the Agent-4 "District Requirements (from DB)"
  table: matched district + match-confidence/fuzzy-score badge, HITL flags, `NO_CLIENT_MATCH` /
  `FALLBACK_CHECKLIST` banners, and per-requirement rows (title, category, concept, validity window, and — when
  present — the Agent-5 doc-status badge). Mirrors `context.html` `reqTable`.
- **`cockpit/ChecklistReview.jsx`** — `props: { review, aid, mode: 'view' | 'correct', onOpenDoc, corrections,
  onQueue }`. Renders the Agent-5 evidence checklist: per item a confidence ring, requirement, status badge,
  matched-file chip, reason, holder/expiration/auditor-concern meta, `confidence_breakdown` score line, and
  document preview buttons (open in `DocumentDrawer`). In `correct` mode it adds the per-item status dropdown +
  multi-file checkbox picker + "queue fix". Mirrors `context.html` `gateAgent5` / `rGateAgent5`.
- **`cockpit/UnmatchedDocsPanel.jsx`** — `props: { review, aid, onOpenDoc }`. The "N documents read · N matched a
  requirement · N matched nothing · M/K still missing" explainer, REVIEW vs not-required buckets, eye-to-open.
  Mirrors `context.html` `unmatchedPanel`. (Rendered by `ChecklistReview`.)
- **`cockpit/CostTierSummary.jsx`** — `props: { review }`. Tier badge (RED/YELLOW/GREEN from `hitl_tier`), total
  cost badge, and the per-agent cost breakdown line from `review.cost.by_agent`. Mirrors `context.html` showReview
  header + cost line.

### 6.2 RUN + REVIEW — `cockpit/review/`

- **`RunReviewPanel.jsx`** — tab container. Holds the manual ID lookup, the pipeline tracker, the "Run all agents"
  button, the full-review area, and the telemetry feed. Uses `useRunJob`. Two entry paths: (a) the rail-selected
  `selectedId`; (b) `IdLookup` resolving an arbitrary id. On completion renders `FullReview`.
- **`IdLookup.jsx`** — `props: { onRun(aid, label) }`. Text box + "Look up" using `useLookupId`. Renders:
  placement result (single assignment, EDU/non-EDU + ended warnings, Run button) or candidate result (list of their
  placements, each with an EDU badge + Run button), or a not-found error. Mirrors `context.html` `lookupId`.
- **`FullReview.jsx`** — `props: { aid, by }`. The one-page review of a completed run: `CostTierSummary`, an
  "applied overrides" panel (`useOverrides`), then a card per agent (1-6): agents 1/2 view-only
  (`AgentOutputView` + `VerifierView`), agent 3 credentialer reassign, agent 4 `RequirementsTable`, agent 5
  `ChecklistReview mode="correct"`, agent 6 `PendingEmailPreview`, plus a generic scalar editor where
  `context.html` `SCALAR` defines fields (5_5 tier/route, 6 recipient/subject). Queued corrections aggregate into
  `rfixes[agentId][field]`. "Apply Corrections & Re-run" saves each via `useSetOverride` then re-runs
  (`useRunJob.start([aid], false)`). Mirrors `context.html` `renderFullReview` + `applyCorrectionsAndRerun`.

### 6.3 BATCH — `cockpit/batch/BatchPanel.jsx`

`props: { selectedIds, by }`. A "wipe previous outputs first" checkbox, a "Launch batch" button (disabled until
`selectedIds.size > 0`), a status line ("job … launched on N candidates", then "batch COMPLETE — ok/total"), the
pipeline tracker, and the shared telemetry feed. Uses `useRunJob.start([...selectedIds], wipe)` and reads
`job.result.ok / job.result.total` for the summary. Mirrors `context.html` `startBatch`.

### 6.4 WATCHDOG — `cockpit/watchdog/`

- **`WatchdogPanel.jsx`** — status line (`useWatchdogStatus`: scanner running/idle · interval · last scan) +
  "Scan now" button (`useWatchdogScan`) + results list (`useWatchdogResults`). Clicking a result shows
  `WatchdogResult`. Mirrors `context.html` `loadWatch` / `watchScan`.
- **`WatchdogResult.jsx`** — `props: { aid, onOpenFullReview }`. `useWatchdogResult(aid)`: new/updated document
  list, requirement-status delta table (was → now), stale-override warning, and an "Open full credentialing view"
  button that deep-links into RUN + REVIEW for that assignment. Mirrors `context.html` `watchPreview` / `watchOpen`.

### 6.5 Shared telemetry + email manifest

- **`cockpit/Telemetry.jsx`** — `props: { lines, title }`. The `▸`-prefixed monospace log terminal (dark, fixed
  height, auto-scroll). Extracted so Batch/Review reuse the StepRun activity-feed look without duplication.
- **`PendingEmailPreview.jsx` (extend)** — additionally render `forms_manifest` (each district-forms file as
  ✅ attached / 🚫 skipped-with-reason) below the attachments, when present. Mirrors `context.html` `emailPreview`
  manifest block. Purely additive — existing To/Cc/Subject/body/iframe rendering unchanged.

## 7. Existing-feature drift repairs (STEP RUN + MAIL)

### 7.1 MAIL — add Held Bullhorn Notes (`MailPanel.jsx`)
Add a second section under the held-emails list: `BullhornNotesPanel.jsx` (`cockpit/mail/`) driven by
`usePendingBullhorn` → list; clicking a note previews it (`usePendingBullhornNote`) with the note `comments` in a
mono block, plus **Approve & write to Bullhorn** (`useApproveBullhorn`) and **Reject** (`useRejectBullhorn`, with a
reason). Mirrors `context.html` `loadBh` / `bhPreview` / `bhApprove` / `bhReject`.

### 7.2 STEP RUN completion — rich review (`StepRunPanel.jsx`)
When the run reaches `complete`, replace the one-line `StatusCard('complete')` with a completion review built from
the shared components: `CostTierSummary` + `RequirementsTable` (`useRequirements`) + `ChecklistReview mode="view"`
(`useReview`) + `PendingEmailPreview`. The `aborted`/`failed` status cards are unchanged. Mirrors `context.html`
`showReview`.

### 7.3 Agent-4 gate — requirements table (`GatePanel.jsx`)
Add an `awaiting.agent === '4'` branch that renders `RequirementsTable` (from `awaiting.output`) alongside the
`VerifierView`, instead of falling through to the generic two-column view.

### 7.4 Agent-5 gate — evidence richness (`GatePanel.jsx`)
Replace the current `Agent5Gate` internals with the shared `ChecklistReview mode="correct"` (confidence rings,
holder/expiry/auditor meta, `confidence_breakdown`, `UnmatchedDocsPanel`). The correction-queue → approve-overrides
wiring is preserved (same `onApprove(overrides)` contract).

### 7.5 Lost-session re-run affordance (`useStepRun.js` / `StepRunPanel.jsx`)
When a step job is gone after a server restart (`status.isError` path), surface a "re-run #{aid}" button instead of
silently dropping state. Minor, additive.

## 8. Wiring

- **`CockpitTabs.jsx`** — append `['review','🔁 Run + Review']`, `['batch','▦ Batch']`, `['watch','🐕 Watchdog']`
  to `TABS`. (Uses the existing gradient-active-pill styling.)
- **`CockpitView.jsx`** — add `cockpit.batchIds` session state (a Set serialized as array). Render the three new
  panels for their tab keys. When `tab === 'batch'`, pass multi-select props to the rail; otherwise single-select.
  Provide an `openReview(aid)` used by Watchdog's "open full review" (switches to the review tab with that aid).
- **`AssignmentRail.jsx`** — add an **optional** multi-select mode: new props `multi` (bool),
  `selectedIds` (array/Set), `onToggle(id)`. When `multi`, rows render a selected state for ids in `selectedIds`
  and click calls `onToggle`; the "Review →" button is hidden. Default (no `multi`) is the current single-select
  behavior, byte-for-byte — existing props (`selectedId`, `onPick`, `onOpenReview`) and tests untouched.

## 9. Testing

Vitest, colocated `__tests__/`, using `renderWithProviders` (QueryClient + ThemeProvider) and `vi.mock` for hooks
(pattern from `StepRunPanel.test.jsx`). New/updated tests:

- `api/__tests__/watchdog.test.js` — the four watchdog hooks call the right paths.
- `hooks/__tests__/useRunJob.test.jsx` — start → running → complete transition; results/logLines accumulate.
- `components/cockpit/__tests__/AssignmentRail.test.jsx` (extend) — multi mode toggles ids; single mode unchanged.
- `components/cockpit/__tests__/BatchPanel.test.jsx` — launch disabled with no selection; enabled with selection;
  calls `start` with the selected ids + wipe flag.
- `components/cockpit/__tests__/IdLookup.test.jsx` — placement result shows Run; candidate result lists placements;
  not-found shows error.
- `components/cockpit/__tests__/WatchdogPanel.test.jsx` — status line + results render; empty state; Scan triggers.
- `components/cockpit/__tests__/RequirementsTable.test.jsx` — rows, banners, match-confidence badge.
- `components/cockpit/__tests__/ChecklistReview.test.jsx` — view vs correct mode; queue fix callback.
- `components/cockpit/__tests__/CostTierSummary.test.jsx` — tier badge + per-agent cost line.
- `components/cockpit/__tests__/BullhornNotesPanel.test.jsx` — list + approve/reject actions.
- `components/cockpit/__tests__/CockpitTabs.test.jsx` — all five tabs render and switch.
- `components/cockpit/__tests__/PendingEmailPreview.test.jsx` (extend) — forms manifest renders when present.
- `components/cockpit/__tests__/StepRunPanel.test.jsx` (extend) — completion renders CostTier/Requirements/Checklist.

Full suite (`npm test`) must stay green.

## 10. Out of scope / explicitly not doing

- Not changing `.env` or the base-URL selection in `config.js`.
- Not adding the generic scalar field-override control at non-checklist step-run gates (a `context.html`
  affordance judged an intentional simplification; per-agent corrections already cover the real cases).
- Not touching Live mode (`ConsoleModeProvider` keeps Live disabled) or the non-cockpit `AssignmentsList`.
- No backend changes — every endpoint above is assumed to exist on the configured backends (same ones
  `context.html` targets).

## 11. File-change summary

**New:** `api/watchdog.js`, `api/lookup.js`, `api/requirements.js`, `api/bullhornNotes.js`, `hooks/useRunJob.js`,
`cockpit/RequirementsTable.jsx`, `cockpit/ChecklistReview.jsx`, `cockpit/UnmatchedDocsPanel.jsx`,
`cockpit/CostTierSummary.jsx`, `cockpit/Telemetry.jsx`, `cockpit/review/RunReviewPanel.jsx`,
`cockpit/review/IdLookup.jsx`, `cockpit/review/FullReview.jsx`, `cockpit/batch/BatchPanel.jsx`,
`cockpit/watchdog/WatchdogPanel.jsx`, `cockpit/watchdog/WatchdogResult.jsx`, `cockpit/mail/BullhornNotesPanel.jsx`,
plus the colocated tests in §9.

**Edited:** `api/runs.js` (add `useJob`), `components/cockpit/CockpitTabs.jsx`, `components/cockpit/CockpitView.jsx`,
`components/cockpit/AssignmentRail.jsx` (multi mode), `components/cockpit/StepRunPanel.jsx` (completion review +
re-run affordance), `components/cockpit/GatePanel.jsx` (agent-4 table + agent-5 richness),
`components/cockpit/MailPanel.jsx` (notes section), `components/cockpit/PendingEmailPreview.jsx` (forms manifest),
`hooks/useStepRun.js` (lost-session re-run affordance).

# Dashboard + Shell Reference Redesign

**Date:** 2026-08-03
**Branch base:** `feat/cockpit-run-review-batch-watchdog` (or a fresh `feat/dashboard-reference-redesign`)
**Status:** Approved design — ready for implementation plan

## Goal

Re-skin the **app shell** (sidebar, topbar) and the **Dashboard page** (page header, Portfolio
Summary, Tier Distribution, Act Now / Needs Review table) to match the UI/UX team's HTML reference,
by introducing the reference's **exact class names and color scales** as a new theme-aware token
layer. This is a **presentational change only** — every hook, query, pagination path, tier
calculation, snapshot, and route stays byte-for-byte functional.

## Non-negotiable constraints

1. **Zero functional regression, with ONE intentional data-correctness change.** No changes to
   `api/*`, `console/*`, `auth/*`, `run/*`, routing, or any data hook. Live/history modes, 15s
   refetch, per-`/review/{id}` queries, snapshot POST, `paginate`, and all `Link → /review/{id}`
   navigation behave exactly as today. **Exception (explicitly requested):** `lib/dashboardHistory.js`
   gains an `effectiveTier` helper so **processed-but-untriaged** assignments (a real review —
   `candidate` or populated `counts` — but `hitl_tier: null`) are treated as **RED / Must Review**.
   Rationale: live API testing showed 7 of 21 done assignments carry `hitl_tier: null` and were
   silently dropped by the RED/YELLOW/GREEN filter in `tierCounts` / `buildCandidateRows`. Genuinely
   empty reviews (`{}`, no counts, no candidate) remain excluded.
2. **Theme-aware (light + dark).** The reference is light-only; we reproduce its look in light mode
   and supply dark-mode equivalents wired to CSS variables so the existing theme toggle keeps working
   on every restyled surface.
3. **Reproduce the reference class names exactly.** `.card`, `.stat-card`, `.stat-card-primary`,
   `.tier-bar`, `.data-table`, `.badge-live`, `.sidebar-link`, `.page-header`, etc. are defined as
   real classes, backed by theme-aware variables — not approximated with ad-hoc utilities.
4. **Keep the flag + arrow elements.** The auditor-flag badge and the row → review chevron stay.
5. **Keep cartoon + small fun elements.** `ThinkingCharacter` appears in loading/empty states;
   pulsing LIVE dot, tier-bar grow-in, stat-card hover-lift, and staggered row entry are retained.
6. **Tailwind CSS only** for the new styling (Tailwind v4 `@theme` + `@layer components`); no new
   inline per-theme JS style objects in the restyled files.
7. **No live API testing.** Tests mock the data hooks (as existing tests already do). We never stand
   up a backend; "does it connect" is out of scope for verification.

## Architecture

```
src/styles/
  theme.css        (unchanged brand tokens; dark block extended with --ref-* dark values)
  reference.css    (NEW) — @theme color scales + @layer components class layer + dark overrides
  globals.css      (adds `@import "./reference.css";` and Plus Jakarta Sans @fontsource imports)

src/components/shell/   Sidebar.jsx, TopBar.jsx, AppShell.jsx  → consume new classes
src/components/dashboard/
  DashboardPage.jsx (page)   PortfolioSummary.jsx   StatCard.jsx
  TierDistribution.jsx       NeedsReviewTable.jsx   DateRangeControl.jsx  → consume new classes
```

The data layer (`src/pages/DashboardPage.jsx`'s query wiring) is preserved; only its returned JSX
markup changes. Where convenient, the page's query logic may be extracted into a small
`useDashboardData()` hook to keep the presentational component clean, but this is optional and must
not change behavior.

## Section 1 — Token & class layer (`src/styles/reference.css`)

### 1a. Color scales (`@theme`, backed by CSS vars)

Defined on `:root` and overridden under `[data-theme="dark"]`. Base hexes reuse the existing `SEM`
palette so the redesign stays on-brand:

| Token family        | Light value(s)                                  | Maps to (existing)      |
|---------------------|-------------------------------------------------|-------------------------|
| `primary-600/700`   | `#1b74c4` / `#005280`                            | `SEM.accent` / brand    |
| `primary-50/100`    | `#eff5ff` / `#dbe6ff`                            | active-nav tints        |
| `success` + `-100/200` | `#1f8a5b` / `#e7f4ee` / `#c7e8d5`            | `SEM.green` / `--tier-green` |
| `warning` + `-100/200` | `#e8930c` / `#fdf3e2` / `#f8e2bd`            | `SEM.yellow`            |
| `danger`  + `-100/200` | `#e5484d` / `#fdeaea` / `#f8cfd0`            | `SEM.red`               |
| `info`               | `#2f6fed`                                       | `SEM.blue`              |
| `ink-600`            | `#5b6b85`                                        | `SEM.gray`              |
| `heading` / `muted`  | `#16233a` / `#93a1b5`                            | dashboard neutrals      |
| slate canvas / surface / border | `#f1f5f9` / `#ffffff` / `#e6ebf2`    | page bg / card / border |

Dark overrides (representative): canvas `#071525`, card surface `rgba(19,26,43,0.7)`, border
`rgba(124,164,255,0.12)`, heading `#EAF1FF`, muted `#6B7A98`; semantic hues unchanged, their `-100/200`
tint backgrounds swapped for low-alpha versions of the hue.

Each becomes a Tailwind color token, e.g. `--color-primary-600: var(--ref-primary-600);` so both the
class layer and any utility usage (`text-primary-600`, `bg-success-100`) resolve correctly.

### 1b. Component classes (`@layer components`)

Exact reference names, each theme-aware via the vars above. Grouped:

- **Cards:** `.card`, `.card-header`, `.card-title`
- **Stat cards:** `.stat-card` + variants `.stat-card-primary|info|success|warning|danger`,
  `.stat-icon`, `.stat-label`, `.stat-sub`, `.stat-value` (left accent border + tinted icon chip)
- **Tier bars:** `.tier-col`, `.tier-stack`, `.tier-value`, `.tier-bar` (+ modifiers like
  `.border-success-200 .bg-success-100`), `.tier-label`
- **Table:** `.table-responsive`, `.data-table` (thead/tbody/tfoot/th/td rules)
- **Badges:** `.badge`, `.badge-danger`, `.badge-live`, `.badge-live-dot` (ping), `.badge-live-text`
- **Page head:** `.page-header`, `.page-title`, `.page-subtitle`
- **Buttons/menus:** `.btn`, `.btn-light`, `.dropdown-menu`, `.dropdown-item`, `.dropdown-caret`
- **Shell:** `.sidebar`, `.sidebar-link`, `.nav-icon`, `.section-label`, `.avatar`, `.header`
- **Cells/misc:** `.cell-index`, `.cell-title`, `.cell-sub`, `.dot`, `.page-backdrop`

### 1c. Typography

Install `@fontsource/plus-jakarta-sans` (self-hosted, CSP-safe). Import weights 400–800 in
`globals.css`. Apply Plus Jakarta Sans through the new classes (page titles, nav, cards); the rest of
the app keeps Geist. Add `--font-jakarta` to `@theme`.

## Section 2 — Shell restyle

**Sidebar.jsx / TopBar.jsx / AppShell.jsx** replace their `isDark ? {...} : {...}` inline style
objects with the new classes:

- Sidebar → `.sidebar`, brand block, `.section-label`, `.sidebar-link` (active state = reference
  active style + retained left-bar + active chevron), footer logout + `.avatar` user card.
- TopBar → `.header`, breadcrumb (`ACAP › {title}`), `ModeSwitch`, running pill, **theme toggle
  preserved**, live clock.
- AppShell → `.page-backdrop` for the ambient backdrop; layout/scroll structure unchanged.

Preserved behaviors: collapse toggle (72/256px), live-vs-test nav switch, active-route highlight,
logout, user identity, clock tick, theme toggle, running pill → `/run`.

## Section 3 — Dashboard page + panels

All logic identical; only markup/classes change.

- **DashboardPage.jsx** — `.page-header` / `.page-title` / `.page-subtitle`; the LIVE badge becomes
  `.badge-live` (+ ping dot), the history badge a subdued `.badge`. `DateRangeControl` unchanged in
  behavior, restyled to `.btn-light` + `.dropdown-menu` / `.dropdown-item`. Loading/error/empty
  branches keep their logic (see Section 4 for cartoon).
- **PortfolioSummary.jsx / StatCard.jsx** — `.card` + `.card-header` wrapping a 2×2 grid of
  `.stat-card` variants (`primary` Total, `info` Placement Ready, `success` Auto Approved, `warning`
  Needs Verification) and a full-width `.stat-card-danger` "Must Review". Count-up animation retained.
- **TierDistribution.jsx** — `.tier-col/.tier-stack/.tier-value/.tier-bar/.tier-label`; keep the
  grow-on-mount transition and half-height floor; caption preserved.
- **NeedsReviewTable.jsx** — `.card` header with `.dot` + title + `.badge-danger` count; body becomes
  `.table-responsive` + `.data-table`. **Stays dynamic:** flag badge, `.cell-index/.cell-title/.cell-sub`,
  the six semantic numeric columns, `Link → /review/{id}`, hover, totals row, and the `Pager` all
  preserved. The reference's static rows are illustrative only.

## Section 4 — Fun elements & cartoon

- Keep the **flag** badge (auditor flags) and the row **arrow** chevron.
- `ThinkingCharacter` cartoon in the **loading** state ("Connecting to backend…") and the **all-clear
  empty** state ("Nothing processed yet" → celebratory robot copy). Reuses the existing component.
- Retain micro-delights: pulsing LIVE dot, tier-bar grow-in, `.stat-card` hover-lift, staggered row
  entry (`.stagger-item`).

## Section 5 — Testing & safety

- Existing `NeedsReviewTable.test.jsx` and `DateRangeControl.test.jsx` must stay green. They query by
  text/role/label, so class changes should not break them; fix any assertion that couples to a
  removed inline style.
- Add light render tests for the restyled `PortfolioSummary` and `TierDistribution` (mocked props):
  assert labels/values render and the reference classes are present.
- Add a render test for the restyled `Sidebar`/`TopBar` (mock `useAuth`, `useConsoleMode`,
  `useRunState`, `useTheme`): nav items, theme-toggle button, and user identity present.
- All hooks are mocked; **no live API** is exercised.
- Gate: `npm test` fully green before completion; manual light/dark visual pass.

## Out of scope

- Backend/API changes; connecting to real services in tests.
- Restyling non-shell pages' inner content (Run Pipeline, Assignments, Tracker, Review) beyond what
  the shared shell restyle inherently changes.
- Replacing Geist globally (only the redesigned surfaces adopt Plus Jakarta Sans).

## Risks & mitigations

- **Shell restyle touches every page** (via `AppShell`). Mitigation: shell classes are theme-aware and
  layout-preserving; smoke-check each route renders.
- **Dark-mode drift** in the new class layer. Mitigation: every color resolves through a `[data-theme]`
  variable; no hardcoded slate hexes inside component classes.
- **Tailwind v4 `@layer components` + `@theme` interplay.** Mitigation: keep the layer in one imported
  file; verify a production `npm run build` compiles the classes.

# Tracker Page Reference Redesign

**Date:** 2026-08-04
**Branch:** `feat/tracker-reference-redesign` (off `main`)
**Status:** Approved design — ready for implementation plan

## Goal

Re-skin the **Tracker page** (`src/pages/TrackerPage.jsx`) to the UI/UX reference, reusing the
theme-aware token/class layer shipped in the dashboard redesign (`src/styles/reference.css`) and
adding the few new classes the reference needs. Default the initial view to **latest pipeline run
first**, and add **fun cartoon + sync animation + micro-interactions**. No functionality changes.

## Non-negotiable constraints

1. **Zero functional regression.** No changes to `api/credTracker.js`, `lib/credTracker.js`,
   `hooks/useLenisScroll.js`, routing, or query behavior. Preserve: react-table sort / column-filter /
   pagination, inline edit (Edit→inputs, Save→update editable fields only, Cancel), Review
   (`navigate('/review/{id}')`), Remove (confirm→delete), and auto-sync-once-on-mount.
2. **Preserve the existing test contract** (`src/pages/__tests__/TrackerPage.test.jsx` stays green,
   unedited): the text `Onboarding Tracker` must still be findable (kept as the `.card-title`
   "ONBOARDING TRACKER" — matches the case-insensitive query); action buttons keep their `title`
   attributes `Edit`/`Save`/`Cancel`/`Review`/`Remove`; editable cells still render inputs
   (`getByDisplayValue`); sync still fires on mount.
3. **Theme-aware (light + dark).** Every new class resolves colors through `--ref-*` variables with
   both `:root` and `[data-theme="dark"]` values. No hardcoded neutrals inside component classes
   (brand-gradient accents excepted, consistent with the existing layer).
4. **Reproduce the reference class names.** Add: `.badge-light`, `.btn-outline-primary`, `.btn-xs`,
   `.btn-sm`, `.btn-rounded-lg`, `.grid-scroll`, `.grid-table`, `.grid-footer`, `.grid-select`,
   `.grid-sync-icon`, `.text-heading-soft`, and a `--color-muted` token so `text-muted` resolves.
5. **Default sort:** initial `sorting = [{ id: 'pipeline_ran_at', desc: true }]` (latest run first);
   users can still change sort/filter/page.
6. **Tailwind only** for new styling; no new inline per-theme JS style objects in the restyled file
   beyond genuinely data-driven values (e.g. edit-input accent).
7. **No live API in tests.** Mock the credTracker hooks (as the existing test already does).

## Architecture

```
src/styles/reference.css        (+ new classes/tokens, theme-aware)
src/components/tracker/TrackerSyncCartoon.jsx   (NEW) — sync banner + loading/empty cartoon
src/pages/TrackerPage.jsx       (restyle to reference; wire cartoon; default sort)
```

The data layer is untouched; only presentation + a new presentational cartoon component are added.

## Section 1 — New reference classes (`src/styles/reference.css`)

Theme-aware via `--ref-*`. New tokens: `--color-muted: var(--ref-muted)` (so `text-muted` works);
`--ref-heading-soft` (`:root` + dark) for `.text-heading-soft`.

- `.badge-light` — neutral count badge (surface-2 bg, muted text, hairline border).
- Button variants extending the existing `.btn`: `.btn-outline-primary` (primary-600 text + border,
  primary-50 hover), `.btn-xs` / `.btn-sm` (size overrides), `.btn-rounded-lg` (radius override).
- `.grid-scroll` — `flex: 1; min-height: 0; overflow: auto;` scroll viewport.
- `.grid-table` — full-width collapse table: sticky lifted header band (accent-tinted, uppercase bold
  labels, bottom rule), a second filter row, sortable header cells (pointer/select-none), zebra-free
  body with per-row bottom rule and hover highlight — all via `--ref-*` vars.
- `.grid-footer` — top-bordered footer bar (flex, space-between).
- `.grid-select` — styled `<select>` (surface bg, hairline border, muted text).
- `.grid-sync-icon` — sync icon; spins (`animation`) when combined with a `.is-syncing`/`animate-spin`
  state.
- `.text-heading-soft` — subtitle text color (`var(--ref-heading-soft)`).

## Section 2 — `TrackerSyncCartoon` (new component)

`src/components/tracker/TrackerSyncCartoon.jsx`, pure presentational, reuses the ThinkingCharacter
robot family for brand consistency:

- `<TrackerSyncCartoon state="syncing" />` → compact banner "Syncing from Bullhorn…" with the animated
  robot (bobbing/blinking) — shown while `sync.isPending`.
- `state="loading"` / `state="empty"` → the robot with a friendly caption for the initial load and the
  no-rows state.
- A brief success pop (✓ / 😄) is handled in the page when a sync transitions pending→done, then
  auto-dismisses.

## Section 3 — TrackerPage restyle

Preserve ALL behavior; change presentation:

- `<main>` shell: `.page-header` + `.page-title` "Tracker" + `.badge-live`; subtitle in
  `.text-heading-soft`.
- `.card` → `.card-header` with `.card-title` **"ONBOARDING TRACKER"** (satisfies the existing test),
  `.badge.badge-light` "{n} tracked", and the Sync control as
  `.btn.btn-outline-primary.btn-xs.btn-rounded-lg` containing the `.grid-sync-icon` (spins while
  pending) — same `sync.mutate()` handler and disabled/`isPending` behavior.
- `.grid-scroll` viewport (keeps the Lenis `scrollRef`) wrapping the react-table restyled as
  `.grid-table` with the reference's **two header rows** (labels+sort arrows, then per-column filter
  inputs). Keep the framer-motion row entry animation, skeleton loading rows, inline-edit inputs, and
  the action buttons (Review/Edit/Remove, Save/Cancel) with their `title`s.
- `.grid-footer`: left = row-count info (`text-muted`) + `.grid-select` rows-per-page (10/25/50/100);
  right = Prev / page-info / Next as `.btn.btn-sm.btn-rounded-lg`.
- `useReactTable`: `initialState: { sorting: [{ id: 'pipeline_ran_at', desc: true }], pagination: {
  pageSize: 25 } }`.
- Wire the cartoon: banner while `sync.isPending`; cartoon for loading (no rows yet) and empty states.
- Micro-interactions: spinning sync icon, row hover-lift + accent highlight, button press-scale,
  sort-arrow rotate/opacity, filter-input focus ring, staggered row entry.
- Drop `useTokens` inline plumbing where classes replace it; keep it only for genuinely data-driven
  bits (edit-input accent, action-button semantic colors) — or tokenize them.

## Section 4 — Testing & safety

- Existing `TrackerPage.test.jsx` stays green, unedited.
- New `src/pages/__tests__/TrackerPage.sort.test.jsx` (own mock, ≥2 rows with distinct
  `pipeline_ran_at`): asserts the first rendered data row is the latest run, and that the reference
  markup renders (`.card`, `.grid-table`, `.page-title` "Tracker", a Sync button).
- New `TrackerSyncCartoon` render test (states render, `role="status"`).
- All hooks mocked; no live API. `npm test` + `npm run build` green.

## Out of scope

- Backend/API changes; column model changes; new editable fields.
- Restyling other pages (shell already restyled).
