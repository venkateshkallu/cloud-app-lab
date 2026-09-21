# Aequor Credentialing HITL Cockpit — Frontend Architecture
 
**Audience:** the engineer/agent building the React frontend.
**Goal:** a modern, branded, Bullhorn‑embeddable UI on top of the **Cockpit API** that lets a credentialer run the pipeline, review each candidate's checklist + agent outputs + documents, correct mistakes (HITL overrides), re‑run, and see analytics.
 
> **Read these first:** `COCKPIT_API.md` (endpoint/field reference) and `FRONTEND_INTEGRATION_GUIDE.md` (the input → output → review → feedback loop). This document is the *build spec* that turns those into a concrete app.
 
> ⚠️ **Sections 1–13 are the original build spec.** The app has since grown a dual-mode
> console, a DB-backed **Cred Tracker** (with its own Node service), and **background
> batch pipeline runs**. **[§14 "Current architecture"](#14-current-architecture-updates-since-the-original-spec) is the
> authoritative, up-to-date description** — read it alongside the originals.
 
---
 
## 0. Critical facts (read before writing code)
 
| Fact | Value | Why it matters |
|---|---|---|
| **API base URL** | `http://localhost:8001` | The docstrings/markdown say `5003`, but the running code (`cockpit_api.py`) binds **8001**. Use **8001**. Make it an env var. |
| **Auth on the backend** | **None today** | The API has no token check. `by` (credentialer email) is **attribution only**, logged to HITL memory. "Session management" on the frontend = client identity + future Bullhorn handoff, not a security boundary. |
| **Bullhorn** | **Read‑only** | Never design a "write to Bullhorn" action. |
| **Emails** | **Never auto‑sent** | Held in a queue. The preview only *shows* them. A "Send" button would need a new backend endpoint — do not assume one exists. |
| **Override semantics** | **Override‑on‑read, propagate‑on‑re‑run** | `/review` reflects an override immediately, but email/triage/audit only change after `POST /rerun`. The whole UX hinges on this. |
| **Multi‑document requirements** | `matched_files` is a **list** (0..N) | A requirement bundle can have many docs. Render all; the "Correct" control is a **multi‑select**. |
| **CORS** | Enabled (`flask_cors.CORS(app)`) | Browser calls work cross‑origin in dev. |
 
---
 
## 1. What we're building
 
A four‑area single‑page app:
 
1. **Analytics Dashboard** — portfolio view: tier distribution, ready/not‑ready, cost, docs found/missing/expired, auditor flags, "needs review" queue.
2. **Run panel** — trigger `POST /run` (or `/rerun`) and watch the **live SSE stream** (agent‑by‑agent + raw terminal lines).
3. **Assignments list** — every assignment with its tier chip, ready flag, cost, counts; click → review.
4. **Candidate Review (the heart of HITL)** — verdict bar, checklist (requirement × document × verdict), inline document viewer, per‑item **Correct** control, per‑agent outputs, "Re‑run to finalize", email preview.
 
All four sit behind a **branded sidebar shell** with a **session‑aware top bar** (logged‑in credentialer email).
 
---
 
## 2. Tech stack
 
| Concern | Choice | Notes |
|---|---|---|
| Language | **JavaScript (JSX)** — no TypeScript | Per requirement. Use **JSDoc** typedefs (Section 9) for editor hints. |
| Build tool | **Vite** | Fast, supports a configurable `base` for iframe embedding. |
| UI library | **React 18** | — |
| Routing | **React Router v6** | `createBrowserRouter`; set `basename` from env for Bullhorn sub‑path embedding. |
| Server state | **TanStack Query (React Query) v5** | Caching, refetch, invalidation. `/review` is invalidated after every override. |
| Styling | **Tailwind CSS v4** with a **CSS‑variable theme layer** | Brand colors live in ONE file (`theme.css`) so Aequor colors swap in one place. See Section 5. |
| Charts | **Recharts** | Donut (tiers), bars (cost by agent), stacked status. |
| Icons | **lucide-react** | Clean, consistent. |
| SSE | Native **`EventSource`** wrapped in a hook | See Section 7. |
| PDF rendering | **react-pdf** (pdfjs) or `<iframe>`/`<img>` | The API returns raw bytes; render images directly, PDFs via react-pdf. |
| Animation | **Framer Motion** (a.k.a. `motion`) | Page transitions, staggered list reveals, the live‑run ticks. Keep it tasteful. |
| HTTP | **fetch** wrapped in a small `apiClient` | No axios needed. |
 
Keep dependencies lean. Do **not** add a heavyweight component kit (MUI/AntD) — it fights the custom brand. Build a small in‑house component set on Tailwind tokens.
 
---
 
## 3. Project structure
 
```
src/
  main.jsx                      # bootstrap, QueryClientProvider, RouterProvider, AuthProvider
  App.jsx                       # <AppShell/> + <Outlet/>
  config.js                     # API_BASE, BASE_PATH, ALLOWED_EMAILS (from env)
 
  styles/
    theme.css                   # ← ALL brand color tokens (the ONE file to edit for Aequor colors)
    globals.css                 # Tailwind layers, base typography, resets
 
  lib/
    apiClient.js                # fetch wrapper, error normalization, base URL
    sse.js                      # EventSource helper (open/parse/close)
    format.js                   # date (ms→YYYY-MM-DD), currency, status helpers
 
  api/                          # one file per resource; thin wrappers + React Query hooks
    assignments.js              # useAssignments, useTestIds
    review.js                   # useReview(aid), documentUrl(aid, file)
    agents.js                   # useAgentOutput(aid, n), useAgentFull(aid)
    cost.js                     # useCost(aid)
    email.js                    # useEmail(aid)
    overrides.js                # useOverrides, useAllowed, useSetOverride, useClearOverride
    runs.js                     # useRun(), useRerun(aid), useWipe(), useJobs
 
  auth/
    AuthProvider.jsx            # context: { user, login, logout }
    useAuth.js
    LoginPage.jsx               # temporary email picker (predefined list)
    bullhornBridge.js           # FUTURE: read identity from Bullhorn (postMessage / URL)
 
  components/
    shell/
      AppShell.jsx              # sidebar + topbar + content area
      Sidebar.jsx               # branded nav
      TopBar.jsx                # logged-in email, district context, actions
    common/
      Button.jsx  Badge.jsx  Card.jsx  Metric.jsx  Drawer.jsx
      StatusPill.jsx  TierChip.jsx  Spinner.jsx  EmptyState.jsx
    run/
      RunControls.jsx           # ids picker, wipe/reread toggles, Start
      LiveStream.jsx            # SSE consumer: agent ticks + terminal log + result cards
      AgentTicker.jsx  TerminalLog.jsx  ResultCard.jsx
    review/
      VerdictBar.jsx            # candidate/district/dates/tier/ready/counts/cost
      Checklist.jsx             # sorted rows (problems first)
      ChecklistRow.jsx          # one requirement: status, docs, reason, auditor flag
      DocumentViewer.jsx        # inline image/PDF from /document
      CorrectItemPanel.jsx      # Screen C: multi-select docs + status + reason → POST override
      FixAgentPanel.jsx         # scalar overrides for agents 2/3/4/6 + gate 5.5
      AgentOutputPanel.jsx      # raw per-agent output (drilldown)
      EmailPreview.jsx          # credentialer_review_html + held candidate email
      RerunBanner.jsx           # "you have unsaved corrections — Re-run to finalize"
    dashboard/
      DashboardStats.jsx        # metric tiles
      TierDonut.jsx  CostByAgentBar.jsx  StatusBreakdown.jsx  NeedsReviewList.jsx
 
  pages/
    DashboardPage.jsx
    RunPage.jsx
    AssignmentsPage.jsx
    ReviewPage.jsx              # /review/:aid — the cockpit
    NotFoundPage.jsx
 
  hooks/
    useSSE.js                   # subscribe to /stream/:jobId
    useDebounce.js
```
 
---
 
## 4. Routing
 
Use a browser router with a configurable `basename` (for Bullhorn sub‑path embedding).
 
```
/                 → DashboardPage          (portfolio analytics)
/run              → RunPage                (start runs + live stream)
/assignments      → AssignmentsPage        (list, filter, search)
/review/:aid      → ReviewPage             (the HITL cockpit)
*                 → NotFoundPage
```
 
`createBrowserRouter([...], { basename: import.meta.env.VITE_BASE_PATH || "/" })`.
A protected layout wraps everything: if `!user`, redirect to `<LoginPage/>` (rendered outside the router shell or as an `/login` route).
 
---
 
## 5. Design system & branding
 
**Aesthetic direction:** *clinical precision meets editorial calm.* This is an enterprise credentialing tool that decides whether a nurse can start a placement — it must read as **trustworthy, exact, and unhurried**, never toy‑like. Data‑dense but with generous breathing room. Status color is **semantic and load‑bearing** (a credentialer scans for red). Avoid generic SaaS purple‑gradient‑on‑white.
 
### 5.1 Color tokens — the ONE file to edit
 
> Aequor brand colors are **TBD** (you'll provide them). Put them **only** in `styles/theme.css`. Everything else references the tokens. The defaults below are reasonable placeholders in Aequor's healthcare register (teal/navy) — **replace the brand block when colors arrive; do not touch the semantic block unless asked.**
 
```css
/* styles/theme.css */
:root {
  /* ───── BRAND (REPLACE WITH AEQUOR COLORS) ───── */
  --brand-primary:        #0E7C86;   /* teal — primary actions, active nav */
  --brand-primary-hover:  #0A626A;
  --brand-ink:            #0B2545;   /* deep navy — headings, sidebar */
  --brand-ink-2:          #13315C;
  --brand-accent:         #E8B23A;   /* warm gold — highlights, focus */
  --brand-surface:        #FFFFFF;
  --brand-bg:             #F6F8F9;   /* app canvas */
  --brand-bg-2:           #EEF3F4;
 
  /* ───── SEMANTIC / STATUS (do not rebrand) ───── */
  --status-valid:    #1F8A4C;   /* FOUND_VALID            ✅ green  */
  --status-expiring: #C9871A;   /* EXPIRES_SOON/DURING    🟡 amber  */
  --status-expired:  #C0392B;   /* FOUND_EXPIRED          🔴 red    */
  --status-wrong:    #8E2D26;   /* FOUND_WRONG_PERSON     🔴 dark   */
  --status-missing:  #6B7280;   /* MISSING                ❌ gray   */
  --status-unread:   #7C3AED;   /* UNREADABLE             ❓ violet */
 
  --tier-red:    #C0392B;
  --tier-yellow: #C9871A;
  --tier-green:  #1F8A4C;
 
  /* ───── NEUTRALS / TEXT ───── */
  --text-strong: #0B1F33;
  --text:        #2B3A4A;
  --text-muted:  #6A7A89;
  --border:      #DCE3E7;
  --shadow:      0 1px 2px rgba(11,37,69,.06), 0 8px 24px rgba(11,37,69,.06);
 
  /* ───── RADIUS / SPACING SCALE ───── */
  --radius-sm: 6px; --radius: 10px; --radius-lg: 16px;
}
```
 
Wire these into Tailwind v4 with `@theme` so you can write `bg-brand-primary text-status-expired` etc.:
 
```css
/* globals.css */
@import "tailwindcss";
@theme {
  --color-brand-primary: var(--brand-primary);
  --color-ink:           var(--brand-ink);
  --color-status-valid:  var(--status-valid);
  --color-status-expired:var(--status-expired);
  /* …map the rest… */
}
```
 
### 5.2 Typography
 
Pick a **distinctive** pairing (avoid Inter/Roboto/Arial). Suggested:
- **Display / headings:** `Fraunces` (optical serif — authoritative, medical‑document feel) **or** `Spectral`.
- **Body / UI:** `Geist` or `Mona Sans` (clean grotesk, excellent for data tables).
- **Monospace (terminal log, IDs, file names):** `JetBrains Mono` or `IBM Plex Mono`.
 
Load via Fontsource (self‑hosted, no FOUC, and works inside a sandboxed Bullhorn iframe). Define a type scale (e.g. 12 / 14 / 16 / 20 / 28 / 40) and use tabular‑nums for all numbers in tables and metrics.
 
### 5.3 Status & tier vocabulary (drives every color decision)
 
| Item status | Icon | Token |
|---|---|---|
| `FOUND_VALID` | ✅ | `--status-valid` |
| `FOUND_EXPIRES_SOON` / `FOUND_EXPIRES_DURING` | 🟡 | `--status-expiring` |
| `FOUND_EXPIRED` | 🔴 | `--status-expired` |
| `FOUND_WRONG_PERSON` | 🔴 | `--status-wrong` |
| `UNREADABLE` | ❓ | `--status-unread` |
| `MISSING` | ❌ | `--status-missing` |
 
| Gate tier (`hitl_tier`) | Meaning |
|---|---|
| `RED` | must be human‑reviewed before submission |
| `YELLOW` | verify (gaps, low confidence, expiring soon) |
| `GREEN` | auto‑approved |
 
Centralize this in `lib/format.js` as `STATUS_META[status] = { icon, label, colorVar }` and `TIER_META[tier]`. Build `StatusPill` and `TierChip` from it. **Sort checklist rows problems‑first** (expired/wrong → unreadable → missing → expiring → valid).
 
### 5.4 Motion (tasteful, not decorative)
 
- **One** orchestrated page‑load reveal per screen (staggered list rows, `animation-delay`).
- Live run: each `agent_*_complete` event animates a tick into place; `assignment_done` slides in a result card.
- Override save → row briefly pulses then shows the "edited by human" badge.
- Avoid scattered micro‑bounces; this is a serious tool.
 
---
 
## 6. Auth & session model
 
### 6.1 Today (temporary): predefined email login
 
There is **no backend auth**. We simulate a session purely to (a) capture the credentialer's email for the `by` attribution field and (b) structure the code so Bullhorn can take over later.
 
- `config.js` exports `ALLOWED_EMAILS` (from `VITE_ALLOWED_EMAILS`, comma‑separated, e.g. `tanya.underwood@aequor.com, paige.smith@aequor.com`).
- `LoginPage` shows a branded sign‑in: a select/list of these emails (or a typed email validated against the list). On pick → store in `AuthProvider`.
- Persist the chosen identity in **memory + `sessionStorage`** (survives reload within the tab; cleared on tab close). Do **not** treat this as secure.
- `AuthProvider` exposes `{ user: { email, name }, login(email), logout() }`.
- **Every override request sends `by: user.email`.** Guard the Correct/Fix buttons: disabled until a user is set (mirrors the Streamlit "enter your email first" rule).
 
### 6.2 Future: Bullhorn embedding
 
Design the auth layer so the backend interface (`useAuth()`) stays identical and only the *source* of identity changes. Put the swap behind `auth/bullhornBridge.js`:
 
- Bullhorn embeds custom tabs/cards via **iframe**. Identity typically arrives via **URL parameters** Bullhorn appends (user id/email, corp token) and/or **`window.postMessage`** from the parent frame.
- `AuthProvider` will, on mount, attempt `bullhornBridge.resolveIdentity()`:
  1. If running inside Bullhorn (detected via URL param / `window.parent !== window` + a known origin) → resolve email from the bridge and **skip the login page**.
  2. Else fall back to the predefined‑email `LoginPage`.
- Embedding checklist for later (document, don't implement yet): set Vite `base`/router `basename` to the embed path; ensure the server serving the build does **not** send `X-Frame-Options: DENY` and sets a `Content-Security-Policy: frame-ancestors` allowing Bullhorn's domain; verify `sessionStorage` works in the third‑party iframe context (may need `postMessage` token relay if cookies/storage are partitioned).
 
Keep all of 6.2 isolated so today's build ships on 6.1 only.
 
---
 
## 7. API layer
 
### 7.1 Client
 
`lib/apiClient.js`:
- Base URL from `import.meta.env.VITE_API_BASE` (default `http://localhost:8001`).
- `get(path)`, `post(path, body)`, `del(path, body)`; JSON in/out; throw a normalized `ApiError { status, message }` on non‑2xx (read `error`/`detail` from body).
- A helper `documentUrl(aid, file)` → `${BASE}/review/${aid}/document?file=${encodeURIComponent(file)}` for `<img>`/PDF `src` (binary; don't fetch‑then‑blob unless you need auth headers — you don't, there's no auth).
 
### 7.2 Endpoint map (→ React Query)
 
| Hook | Method | Path | Notes |
|---|---|---|---|
| `useAssignments()` | GET | `/assignments` | `{assignment_ids:[]}` — sidebar/list source |
| `useTestIds()` | GET | `/test_ids` | the 10 kept IDs (for the Run picker) |
| `useReview(aid)` | GET | `/review/:aid` | **the cockpit payload** (schema in COCKPIT_API.md). Invalidate after every override. |
| `documentUrl(aid,file)` | GET | `/review/:aid/document?file=` | raw bytes for inline viewer |
| `useAgentOutput(aid,n)` | GET | `/assignment/:aid/agent/:n` | n ∈ 1,2,3,4,5,5_5,6 |
| `useAgentFull(aid)` | GET | `/assignment/:aid/full` | all agents |
| `useCost(aid)` | GET | `/assignment/:aid/cost` | per‑agent `$` |
| `useEmail(aid)` | GET | `/assignment/:aid/email` | `{credentialer_review_html, candidate_email}` |
| `useOverrides(aid)` | GET | `/overrides/:aid` | current overrides |
| `useAllowed()` | GET | `/allowed` | overridable fields per agent (drive the Fix‑agent form) |
| `useSetOverride()` | POST | `/overrides/:aid` | body `{agent, field, value, by, reason}`; **422** if field not allowed → surface inline |
| `useClearOverride()` | DELETE | `/overrides/:aid` | `{agent, field?}` (omit field = clear all for agent) |
| `useRun()` | POST | `/run` | `{ids:"all"\|[...], wipe, reread, backup}` → `{job_id, stream}` |
| `useRerun(aid)` | POST | `/rerun/:aid` | wipe+rerun one → `{job_id, stream}` |
| `useWipe()` | POST | `/wipe` | `{ids, reread}` |
| `useJobs()` | GET | `/jobs` `/jobs/:id` | job status/result |
 
After `useSetOverride`/`useClearOverride` succeed → `queryClient.invalidateQueries(['review', aid])` and `['overrides', aid]`. Show the `RerunBanner`.
 
### 7.3 SSE (`hooks/useSSE.js` + `lib/sse.js`)
 
`EventSource(`${API_BASE}/stream/${jobId}`)`. **`EventSource` cannot set custom headers** — fine, there's no auth. Subscribe to named events (the backend emits `event: <type>`):
 
| Event | Render |
|---|---|
| `backup` / `wiped` | toast/log line (files backed up, wipe counts) |
| `batch_start` | `{total, assignment_ids}` → init progress |
| `assignment_start` | `{index, total, assignment_id}` → advance progress, open candidate accordion |
| `agent_1_complete` … `agent_6_complete` | tick agent; show name, verdict/critic, duration, repairs count |
| `assignment_complete` | `{tier, ready, triage_counts}` |
| `log` | `{line}` → append to terminal panel (monospace, autoscroll) |
| `assignment_done` | `{assignment_id, review}` → render a **result card** (reuse `VerdictBar` summary) |
| `assignment_failed` | `{assignment_id, error}` → error card |
| `job_complete` / `job_failed` | `{ok, total, results}` → finalize, **close the EventSource** |
 
The hook returns `{ status, events, agentsByAid, logLines, results }` and a `close()`. **Always close on `job_complete`/`job_failed`/unmount** (SSE holds a connection open per client). Cap `logLines` (e.g. last 1000) to avoid unbounded memory.
 
---
 
## 8. Screens (build spec)
 
### Screen A — Run (`/run`)
- **Controls** (`RunControls`): IDs = "all 10 test IDs" (default) or a multi‑select from `useTestIds()`; toggles **Start fresh / wipe** (default on), **Re‑read documents** (default off, warn it's slower/costlier), **Back up state** (default on). A confirm checkbox before the primary "Run" button (mirror Streamlit's guardrail).
- **On run** → `useRun()` returns `job_id`; open `useSSE(job_id)`.
- **Live** (`LiveStream`): a progress bar (`index/total`), a per‑candidate accordion that fills with **agent ticks** as `agent_*_complete` arrive, a collapsible **terminal log** fed by `log` events, and **result cards** on `assignment_done`. On `job_complete`, show a summary (ok/total, total cost) and link each card to `/review/:aid`.
 
### Screen B — Candidate Review (`/review/:aid`) — *the core*
Layout: sticky **VerdictBar** on top, **Checklist** as the main column, a right‑hand **Document drawer** that opens when a row's "View document" is clicked, and collapsible **agent drilldown** + **email preview** sections below.
 
- **VerdictBar**: candidate, district, start/end dates, `TierChip(hitl_tier)`, **ready** Y/N, the six counters (`counts.valid/expiring/expired/missing/unreadable/auditor_flags`), and **cost** (`cost.total_usd`, calls, by‑agent breakdown). Pull from `useReview(aid)`.
- **Checklist** (`Checklist` → `ChecklistRow[]`): sort **problems first** (Section 5.3). Each row shows: `StatusPill`, requirement name, `category`/`concept`, `matched_files` (render **all**; "1 file" vs "N documents"), `doc_type`, `holder_name` (**warn if it doesn't match the candidate name** — token overlap check, mirror `_holder_mismatch`), `expiration_date`, `reason`. Surface `auditor_concern` as a **prominent RED "needs review" flag**; surface `auditor_autofix` as an **"auto‑corrected by auditor"** note. Show an **"edited by human"** badge when `override_applied` (with `override_by`).
- **DocumentViewer** (drawer): fetch via `documentUrl(aid, file)`. Images → `<img>`. PDFs → react-pdf (paginated). Other → download link. **This drawer must be openable before the user accepts/changes a verdict** — eyeballing the file against the AI's call is the point.
- **CorrectItemPanel** (Screen C, per row): a **multi‑select** of *all* the candidate's documents (`review.unmatched_documents` ∪ already‑matched), with **inline preview of each selected doc** before committing. Then a **status** select (default `FOUND_VALID` when assigning docs, `MISSING` when cleared — the API has no "derive" call, so the human picks), optional `expiration_date`, and a `reason`. Submit → `useSetOverride({agent:"5", field:<requirement name>, value:{status, matched_files:[...], expiration_date?}, by:user.email, reason})`. On success invalidate `['review', aid]` → row updates instantly; show `RerunBanner`.
- **FixAgentPanel**: scalar overrides for agents **2/3/4/6** and the **5.5 gate tier**. Drive the editable fields from `useAllowed()`. Value is a string/number for scalar agents; for 5.5 the gate is `{agent:"5_5", field:"hitl_tier", value:"RED"|"YELLOW"|"GREEN"}`.
- **AgentOutputPanel**: tabs/accordion for raw outputs (`useAgentOutput(aid, n)` for 2,3,4,5,5_5,6) — the "drilldown" for power users.
- **RerunBanner**: appears after any override. CTA "**Re‑run to finalize**" → `useRerun(aid)` → stream it (reuse `LiveStream`) → on `job_complete` invalidate `['review', aid]`, `['email', aid]`, `['cost', aid]`. Let users batch several corrections, then re‑run **once**.
- **EmailPreview** (Screen E): `useEmail(aid)` → render `credentialer_review_html` (sandboxed) and the held `candidate_email` (to/cc/subject/status/tier/ready + body). **No Send button** (would need a new endpoint — note it, don't fake it).
 
### Screen — Assignments (`/assignments`)
List from `useAssignments()`; for each, lazily `useReview(aid)` (or hydrate from a prior batch's `assignment_done` events) to show: candidate, district, `TierChip`, ready flag, counts summary, cost, **needs‑review** indicator (any `auditor_flags > 0` or tier RED). Search by candidate/district, filter by tier/ready. Row click → `/review/:aid`.
 
### Screen — Dashboard (`/`) — analytics
Aggregate across all assignments (loop `useReview` over `useAssignments`, cached by React Query):
- **Metric tiles**: total candidates, # RED / YELLOW / GREEN, # ready, total LLM cost, avg cost/candidate, total docs missing/expired, total auditor flags.
- **TierDonut** (Recharts pie): RED/YELLOW/GREEN using tier tokens.
- **CostByAgentBar**: sum `cost.by_agent` across candidates.
- **StatusBreakdown** (stacked bar): valid/expiring/expired/missing/unreadable totals.
- **NeedsReviewList**: candidates with RED tier or auditor flags, sorted worst‑first → quick link to review.
- Optional throughput over time if a date is available from agent‑2 output.
 
---
 
## 9. Data shapes (JSDoc typedefs)
 
Define these in `api/types.js` and import as `@type` hints. Authoritative schema: `COCKPIT_API.md`.
 
```js
/**
 * @typedef {Object} ChecklistItem
 * @property {string}  requirement
 * @property {"FOUND_VALID"|"FOUND_EXPIRES_SOON"|"FOUND_EXPIRES_DURING"|"FOUND_EXPIRED"|"FOUND_WRONG_PERSON"|"UNREADABLE"|"MISSING"} status
 * @property {string}  concept
 * @property {string}  category
 * @property {string[]} matched_files     // 0..N
 * @property {string}  doc_type
 * @property {string}  holder_name
 * @property {string}  expiration_date
 * @property {string}  reason
 * @property {?string} auditor_concern    // RED flag when present
 * @property {?Object} auditor_autofix    // {removed:[], concern:""} when present
 * @property {boolean} override_applied
 * @property {?string} override_by
 */
 
/**
 * @typedef {Object} Review
 * @property {number|string} assignment_id
 * @property {string} candidate
 * @property {string} district
 * @property {string} start_date
 * @property {string} end_date
 * @property {string} credentialer
 * @property {"RED"|"YELLOW"|"GREEN"} hitl_tier
 * @property {{red:number,yellow:number,green:number}} triage_counts
 * @property {boolean} ready
 * @property {{valid:number,expiring:number,expired:number,missing:number,unreadable:number,auditor_flags:number,auto_fixed:number}} counts
 * @property {{total_usd:number,calls:number,by_agent:Object,budget_usd:number,over_budget:boolean}} cost
 * @property {ChecklistItem[]} checklist
 * @property {string[]} unmatched_documents
 * @property {boolean} candidate_folder_present
 */
```
 
---
 
## 10. State management rules
 
- **Server state → React Query.** Keys: `['assignments']`, `['review', aid]`, `['overrides', aid]`, `['cost', aid]`, `['email', aid]`, `['allowed']`, `['agent', aid, n]`.
- **Client/UI state → local `useState`/context.** Auth (Context), active SSE job (page‑local), drawer open/selected file, form drafts in Correct/Fix panels.
- **The invariant in code:** after any override mutation → invalidate `review`+`overrides` (instant reflect). After a **re‑run completes** → also invalidate `email`+`cost`+`assignments`. Never show "email updated" before a re‑run.
 
---
 
## 11. UX invariants (these are correctness, not style)
 
1. **Override‑on‑read, propagate‑on‑re‑run.** Don't claim the email/triage changed until a re‑run finishes.
2. **A requirement can have multiple documents.** Render all; Correct is a multi‑select.
3. **Show the document before accepting/changing a verdict.**
4. **Capture the credentialer email; send it as `by` on every override.** Disable override actions until set.
5. **Never auto‑send email; never write to Bullhorn.** Both are hold‑only / read‑only.
6. **A machine never clears a requirement upward.** The auditor only *removes wrong‑type docs* (downgrade) or *flags* (forces RED); only the human or deterministic matcher approves. Reflect this in copy and disabled states.
 
---
 
## 12. Environment & build
 
`.env` (Vite):
```
VITE_API_BASE=http://localhost:8001
VITE_BASE_PATH=/
VITE_ALLOWED_EMAILS=tanya.underwood@aequor.com,paige.smith@aequor.com
VITE_BULLHORN_PARENT_ORIGIN=        # filled in later for embedding
```
 
Scripts: `npm run dev` (Vite), `npm run build`, `npm run preview`.
For Bullhorn embedding later: set `VITE_BASE_PATH` to the embed sub‑path, build, serve behind a host that permits `frame-ancestors` for Bullhorn's domain (no `X-Frame-Options: DENY`).
 
---
 
## 13. Build order (milestones for the agent)
 
1. **Scaffold**: Vite + React + Tailwind v4 + theme tokens + fonts; `AppShell` (sidebar + topbar) with brand placeholders; routing skeleton.
2. **Auth (temporary)**: `AuthProvider` + `LoginPage` (predefined emails) + sessionStorage; gate the app.
3. **API layer**: `apiClient` + all React Query hooks (Section 7).
4. **Assignments list**: `/assignments` reading `useAssignments` + `useReview`.
5. **Review cockpit**: VerdictBar → Checklist → DocumentViewer drawer (read‑only first).
6. **HITL**: CorrectItemPanel + FixAgentPanel + clear/override + invalidation + RerunBanner.
7. **Run + SSE**: RunControls + `useSSE` + LiveStream (ticks, terminal, result cards) + Rerun reuse.
8. **Email preview** drawer.
9. **Dashboard analytics**: tiles + Recharts.
10. **Polish**: motion, empty/error/loading states, responsive, then drop in real **Aequor colors** in `theme.css`.
 
---
 
*References: endpoints/fields → `COCKPIT_API.md`; flow/UX → `FRONTEND_INTEGRATION_GUIDE.md`; backend run/setup → `SETUP.md`. API base is **port 8001**.*
 
---
 
## 14. Current architecture (updates since the original spec)
 
This section reflects what the app actually does today. Where it differs from §1–13, **this wins**. Run/setup steps live in `RUN.md`.
 
### 14.1 Services & ports
 
| Service | Port | Owns | Notes |
|---|---|---|---|
| Cockpit API (Flask, separate repo) | **8001** | pipeline, `/review`, `/overrides`, `/rerun`, `/run`, `/jobs`, SSE `/stream/:job`, `/bullhorn_assignments`, `/assignment/:id/agent/:n` | The only backend the UI talks to in Test mode. |
| Pipeline API (Flask, separate repo) | 5001 | production Bullhorn pipeline | **Live mode — currently DISABLED in the UI** (see 14.5). |
| **excel-api** (Node/Express, **this repo**, `excel-api/`) | **8002** | the **Cred Tracker** DB table `stg.Cred_Tracker` — CRUD + a cockpit-sync | New. Reads repo-root `.env` **and** `excel-api/.env` (local override). See `excel-api/README.md`. |
| Frontend (Vite) | 5173 | the SPA | — |
 
### 14.2 Dual-mode console
 
`ConsoleModeProvider` (`src/console/`) holds a `test | live` mode and is the **single writer** of the active API base (`apiClient.setActiveApiBase`) and the React-Query key prefix (`modeKey.mk`). Test → cockpit (:8001); Live → pipeline (:5001). The `AssignmentsPage` renders **`CockpitView`** in Test mode (step-run cockpit over `/bullhorn_assignments`) and the legacy `AssignmentsList` in Live.
 
### 14.3 Cred Tracker (DB-backed onboarding tracker)
 
- **Table** `stg.Cred_Tracker` (auto-created + idempotently migrated by `ensureCredTrackerTable`). Columns split into **agent-owned** (candidate, district, state, license, AM, recruiter, initial start, **Pipeline_Ran_At**) and **credentialer-editable** (start date, credentialer, date confirmed, new/rebook/ext, last updated, onboarding status, lead), plus audit (`Updated_By/At`, `Synced_At`).
- **excel-api modules:** `credTrackerMap.js` (pure: agent payload → columns, upsert planning, normalization, editable whitelist — unit-tested) and `credTracker.js` (DB + the cockpit sync). Routes: `GET /cred-tracker`, `GET /:id`, `POST /sync`, `PATCH /:id`, `DELETE /:id`.
- **Sync** pulls each id's `agent/2` (intake) + `agent/3` (assignment) from the cockpit, maps `audit.output.*` + the verifier real-name, and **upserts preserving credentialer edits** (refresh uses `COALESCE` so a transient null never clobbers good data).
- **Auth:** the three write routes require an `X-Cred-Tracker-Token` header matched to `CRED_TRACKER_TOKEN`; CORS restricted to `CRED_TRACKER_ALLOWED_ORIGINS`. Unset token = warn-and-allow for local dev. The UI sends `VITE_CRED_TRACKER_TOKEN` (a browser-shipped token — raises the bar, not a true secret; real per-user auth belongs server-side).
- **UI:** `TrackerPage` reads **only** `stg.Cred_Tracker`, renders a custom Tailwind table on **@tanstack/react-table** (headless: per-column sort/filter, pagination), Lenis smooth-scroll, framer-motion, inline single-row edit. Row click does **not** navigate — only the Review button does. Auto-syncs on open.
 
### 14.4 Background batch pipeline runs
 
- **`RunProvider`** (`src/run/`) is mounted **above the router** in `main.jsx` (inside `QueryClientProvider` + `ConsoleModeProvider`), so a run survives page navigation. It owns the batch `jobId` + SSE-derived state (via the pure `sseReducer.js`) and **re-attaches a still-running job on full refresh** by querying `/jobs` (+ a `localStorage['acap.activeRun']` hint).
- **Run Pipeline page:** a picker (idle) → `RunLiveView` (active). The picker lists the **full bullhorn assignment set** (`useBullhornAssignments`) with All/New/In-Progress/Done filter tabs, selects 1–10, and `startRun(ids)` → `POST /run`.
- **Abort = "Stop watching"** (frontend detach) — the cockpit has no batch-cancel endpoint. Labeled honestly.
- **On `job_complete`** the provider auto-`POST`s `/cred-tracker/sync` so finished candidates appear in the Tracker. A TopBar **"Running X/N" pill** is visible on every page while a batch runs.
- **Corrections auto-finalize:** saving an override on the Review page kicks off the re-run automatically (`RerunBanner`), no manual click.
 
### 14.5 Live mode disabled (testing only)
 
Everything that targets the production pipeline (:5001) is commented out and marked `LIVE DISABLED`: `ConsoleModeProvider` forces `test` and no-ops `setMode('live')`; the Live switch (`ModeSwitch`) and `/live` route + `LiveFeedPage` import (`App.jsx`) are commented out. Restore those four spots to re-enable.
 
### 14.6 Routing (current)
 
```
/                 → DashboardPage     (portfolio analytics; counts the processed/with-data set)
/run              → RunPage           (batch picker + background live view)
/assignments      → AssignmentsPage   (CockpitView in Test mode; AssignmentsList in Live)
/review/:aid      → WorkspacePage     (the HITL cockpit)
/tracker          → TrackerPage       (DB-backed Cred Tracker)
/bh-debug         → BullhornDebugPage (TEMP — discovery only)
/live             → (DISABLED)        commented out while live is off
*                 → NotFoundPage
```
 
### 14.7 State management (current)
 
- **Provider order** (`main.jsx`): `QueryClientProvider → ThemeProvider → AuthProvider → ConsoleModeProvider → RunProvider → App(RouterProvider)`.
- **Server state → React Query**, mode-prefixed keys via `mk()`; the Cred Tracker list uses the un-prefixed key `['cred-tracker','rows']` (it's served by excel-api, not the mode-switched cockpit).
- **Cross-navigation run state → `RunProvider` context** (above the router). **Console mode → `ConsoleModeProvider`.** Auth/theme → their contexts. Everything else stays local `useState`.
- **SSE** lives in the provider (batch runs) and `useSSE`/`RerunBanner` (single-assignment re-run); the event→state reduction is the pure, tested `sseReducer.reduceSseEvent`.
 
### 14.8 Updated project structure (additions)
 
```
src/
  run/   sseReducer.js  RunProvider.jsx          # background batch-run state (above router)
  console/ ConsoleModeProvider.jsx  modeKey.js   # test/live mode + RQ key prefix
  components/run/ AssignmentPicker.jsx RunLiveView.jsx
  api/   credTracker.js                           # Cred Tracker hooks (excel-api :8002)
  lib/   credTracker.js  cockpit.js               # column model; cockpit pure helpers
  hooks/ useLenisScroll.js
excel-api/                                        # Node service: db.js credTracker.js credTrackerMap.js auth.js index.js
```
 
### 14.9 Conventions held
 
JS + JSDoc (no TS); Tailwind + `useTokens()` tokens (dark/light), brand `#5BA8FF`/`#1E6FE0`; lean deps (added only `@tanstack/react-table`); pure logic split from I/O and unit-tested (`sseReducer`, `credTrackerMap`, `cockpit`); parameterized SQL only; `npm run lint` clean (0 errors), `npm test` green.