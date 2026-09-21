# Dual-Mode (Test / Live) Console — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a top-level Test/Live mode switch to the Aequor Credentialing frontend — Test hits the Cockpit API (8001), Live hits the production Pipeline API (Bullhorn + scheduler) on the same host/different port — sharing one per-assignment workspace (Review + agent tabs + Audit) and adding a Live landing (Bullhorn status, auto-poll scheduler, live SSE feed, manual controls).

**Architecture:** The active backend becomes a runtime value. A module-level setter (`setActiveApiBase`) drives `apiClient`/SSE; a `ConsoleModeProvider` owns `mode` (persisted to sessionStorage) and, on each render, points the base + a query-key mode-prefix (`mk()`) at the active backend so every existing hook works unchanged in both modes without cache collisions. New Live-only panels consume new pipeline hooks. New UI is pure Tailwind (brand tokens are theme-aware via `@theme`) + existing animation helper classes + framer-motion.

**Tech Stack:** React 19, Vite 8, Tailwind CSS v4, TanStack Query v5, framer-motion 12, lucide-react, native EventSource. Tests: Vitest + @testing-library/react + jsdom.

---

## File Structure

**New files**
- `src/console/ConsoleModeProvider.jsx` — mode context, sessionStorage persistence, active-base + key-prefix wiring.
- `src/console/modeKey.js` — `mk()` query-key prefixer + `setModeForKeys()`.
- `src/api/bullhorn.js` — `useBullhornStatus()`.
- `src/api/scheduler.js` — `useScheduler()`, scheduler mutations, manual run mutations.
- `src/api/audit.js` — `useAuditLog()`, `useCost()`.
- `src/lib/audit.js` — `buildTimeline()` pure transform.
- `src/components/shell/ModeSwitch.jsx` — TopBar segmented Test/Live control.
- `src/components/workspace/AssignmentRail.jsx` — mode-aware assignment list.
- `src/components/workspace/WorkspaceTabs.jsx` — per-assignment tab bar + panels.
- `src/components/review/AuditPanel.jsx` — audit timeline + raw agent JSON + cost.
- `src/components/live/BullhornStatusCard.jsx`
- `src/components/live/SchedulerPanel.jsx`
- `src/components/live/ManualControls.jsx`
- `src/pages/LiveFeedPage.jsx` — Live landing assembly.
- `vitest.setup.js` — jest-dom matchers.
- Test files colocated under `src/**/__tests__/*.test.js(x)`.

**Modified files**
- `src/config.js` — add `PIPELINE_API_BASE`, `COCKPIT_API_BASE`.
- `src/lib/apiClient.js` — active-base setter; `documentUrl` uses active base.
- `src/lib/sse.js` — `openSSE` uses active base.
- `src/main.jsx` — namespace localStorage cache by mode; wrap App in `ConsoleModeProvider`.
- `src/api/{assignments,review,agents,cost,email,overrides,runs}.js` — `mk()` keys.
- `src/pages/AssignmentsPage.jsx` — `mk('review', id)` inline keys.
- `src/components/shell/TopBar.jsx` — render `<ModeSwitch/>`.
- `src/components/shell/Sidebar.jsx` — mode-aware nav items.
- `src/components/shell/AppShell.jsx` — title for `/live`.
- `src/components/review/AgentOutputPanel.jsx` — export `AGENTS` + `AgentContent`.
- `src/App.jsx` — routes for `/live` and workspace tabs.
- `vite.config.js` — add `test` config.
- `package.json` — dev deps + `test` script (via install command).

---

## Task 1: Test infrastructure

**Files:**
- Modify: `vite.config.js`
- Create: `vitest.setup.js`
- Create: `src/lib/__tests__/smoke.test.js`

- [ ] **Step 1: Install dev dependencies**

Run:
```bash
npm i -D vitest@^2 jsdom @testing-library/react @testing-library/jest-dom @testing-library/user-event
```
Expected: packages added to `devDependencies`, no errors.

- [ ] **Step 2: Add test config to `vite.config.js`**

Replace the whole file with:
```js
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [tailwindcss(), react()],
  base: process.env.VITE_BASE_PATH || '/',
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./vitest.setup.js'],
    css: false,
  },
})
```

- [ ] **Step 3: Create `vitest.setup.js`**

```js
import '@testing-library/jest-dom/vitest'
```

- [ ] **Step 4: Add a `test` script to `package.json`**

In the `"scripts"` block add:
```json
"test": "vitest run",
"test:watch": "vitest"
```

- [ ] **Step 5: Write a smoke test**

`src/lib/__tests__/smoke.test.js`:
```js
import { describe, it, expect } from 'vitest'

describe('test harness', () => {
  it('runs', () => {
    expect(1 + 1).toBe(2)
  })
})
```

- [ ] **Step 6: Run the test**

Run: `npm test`
Expected: 1 passed.

- [ ] **Step 7: Commit**

```bash
git add package.json package-lock.json vite.config.js vitest.setup.js src/lib/__tests__/smoke.test.js
git commit -m "test: add vitest + testing-library harness"
```

---

## Task 2: Config — second backend base URL

**Files:**
- Modify: `src/config.js`
- Test: `src/__tests__/config.test.js`

- [ ] **Step 1: Write the failing test**

`src/__tests__/config.test.js`:
```js
import { describe, it, expect } from 'vitest'
import { COCKPIT_API_BASE, PIPELINE_API_BASE, API_BASE } from '../config.js'

describe('config base URLs', () => {
  it('exposes a cockpit (test) base defaulting to port 8001', () => {
    expect(COCKPIT_API_BASE).toContain('8001')
  })
  it('keeps API_BASE as an alias of the cockpit base for back-compat', () => {
    expect(API_BASE).toBe(COCKPIT_API_BASE)
  })
  it('exposes a separate pipeline (live) base', () => {
    expect(typeof PIPELINE_API_BASE).toBe('string')
    expect(PIPELINE_API_BASE.length).toBeGreaterThan(0)
    expect(PIPELINE_API_BASE).not.toBe('')
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/__tests__/config.test.js`
Expected: FAIL — `PIPELINE_API_BASE`/`COCKPIT_API_BASE` are undefined.

- [ ] **Step 3: Update `src/config.js`**

Replace the top two export lines:
```js
export const API_BASE = import.meta.env.VITE_API_BASE ?? 'http://52.9.132.43:8001'
export const BASE_PATH = import.meta.env.VITE_BASE_PATH ?? '/'
```
with:
```js
// Cockpit / TEST backend (review tool, no Bullhorn). Port 8001.
export const COCKPIT_API_BASE = import.meta.env.VITE_API_BASE ?? 'http://52.9.132.43:8001'

// Production Pipeline backend (Bullhorn + scheduler). Same host, different port.
// NOTE: replace 5003 below with the real pipeline port when known.
export const PIPELINE_API_BASE =
  import.meta.env.VITE_PIPELINE_API_BASE ?? 'http://52.9.132.43:5003'

// Back-compat alias — existing imports of API_BASE keep working (Test default).
export const API_BASE = COCKPIT_API_BASE
export const BASE_PATH = import.meta.env.VITE_BASE_PATH ?? '/'
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/__tests__/config.test.js`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/config.js src/__tests__/config.test.js
git commit -m "feat: add PIPELINE_API_BASE config for live mode"
```

---

## Task 3: Mode-aware apiClient (active base)

**Files:**
- Modify: `src/lib/apiClient.js`
- Test: `src/lib/__tests__/apiClient.test.js`

- [ ] **Step 1: Write the failing test**

`src/lib/__tests__/apiClient.test.js`:
```js
import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import { apiClient, setActiveApiBase, getActiveApiBase, documentUrl } from '../apiClient.js'
import { COCKPIT_API_BASE, PIPELINE_API_BASE } from '../../config.js'

describe('apiClient active base', () => {
  beforeEach(() => {
    setActiveApiBase(COCKPIT_API_BASE)
    global.fetch = vi.fn(() =>
      Promise.resolve({ ok: true, status: 200, headers: { get: () => 'application/json' }, json: () => Promise.resolve({}) })
    )
  })
  afterEach(() => { vi.restoreAllMocks() })

  it('defaults to the cockpit base', () => {
    expect(getActiveApiBase()).toBe(COCKPIT_API_BASE)
  })

  it('routes requests to the active base after switching', async () => {
    setActiveApiBase(PIPELINE_API_BASE)
    await apiClient.get('/health')
    expect(global.fetch).toHaveBeenCalledWith(`${PIPELINE_API_BASE}/health`, expect.any(Object))
  })

  it('builds document URLs from the active base', () => {
    setActiveApiBase(PIPELINE_API_BASE)
    expect(documentUrl('42', 'a b.pdf')).toBe(`${PIPELINE_API_BASE}/review/42/document?file=a%20b.pdf`)
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/lib/__tests__/apiClient.test.js`
Expected: FAIL — `setActiveApiBase`/`getActiveApiBase` not exported.

- [ ] **Step 3: Rewrite `src/lib/apiClient.js`**

```js
import { COCKPIT_API_BASE } from '../config.js'

export class ApiError extends Error {
  constructor(status, message) {
    super(message)
    this.status = status
    this.name = 'ApiError'
  }
}

// The active backend base URL. The ConsoleModeProvider is the single writer.
let activeBase = COCKPIT_API_BASE
export function setActiveApiBase(base) { activeBase = base }
export function getActiveApiBase() { return activeBase }

async function request(method, path, body) {
  const opts = {
    method,
    headers: { 'Content-Type': 'application/json' },
  }
  if (body !== undefined) opts.body = JSON.stringify(body)

  const res = await fetch(`${activeBase}${path}`, opts)
  if (!res.ok) {
    let msg = `HTTP ${res.status}`
    try {
      const j = await res.json()
      msg = j.error ?? j.detail ?? msg
    } catch {}
    throw new ApiError(res.status, msg)
  }
  if (res.status === 204) return null
  return res.json()
}

export const apiClient = {
  get:  (path)        => request('GET',    path),
  post: (path, body)  => request('POST',   path, body),
  del:  (path, body)  => request('DELETE', path, body),
}

/** Returns the URL for fetching a raw document (no auth required) */
export function documentUrl(aid, file) {
  return `${activeBase}/review/${aid}/document?file=${encodeURIComponent(file)}`
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/lib/__tests__/apiClient.test.js`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/lib/apiClient.js src/lib/__tests__/apiClient.test.js
git commit -m "feat: make apiClient route to a runtime-switchable base"
```

---

## Task 4: Mode-aware SSE

**Files:**
- Modify: `src/lib/sse.js`
- Test: `src/lib/__tests__/sse.test.js`

- [ ] **Step 1: Write the failing test**

`src/lib/__tests__/sse.test.js`:
```js
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { openSSE } from '../sse.js'
import { setActiveApiBase, getActiveApiBase } from '../apiClient.js'
import { PIPELINE_API_BASE, COCKPIT_API_BASE } from '../../config.js'

describe('openSSE uses the active base', () => {
  let urls
  beforeEach(() => {
    urls = []
    global.EventSource = vi.fn(function (url) {
      urls.push(url)
      this.addEventListener = vi.fn()
      this.close = vi.fn()
    })
  })
  afterEach(() => { setActiveApiBase(COCKPIT_API_BASE) })

  it('builds the stream URL from the active base', () => {
    setActiveApiBase(PIPELINE_API_BASE)
    const close = openSSE('job123', {}, () => {})
    expect(urls[0]).toBe(`${PIPELINE_API_BASE}/stream/job123`)
    close()
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/lib/__tests__/sse.test.js`
Expected: FAIL — URL built from imported `API_BASE` constant (cockpit), not the active pipeline base.

- [ ] **Step 3: Update `src/lib/sse.js`**

Change the import line:
```js
import { API_BASE } from '../config.js'
```
to:
```js
import { getActiveApiBase } from './apiClient.js'
```
and change the URL line inside `openSSE`:
```js
  const url = `${API_BASE}/stream/${jobId}`
```
to:
```js
  const url = `${getActiveApiBase()}/stream/${jobId}`
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/lib/__tests__/sse.test.js`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add src/lib/sse.js src/lib/__tests__/sse.test.js
git commit -m "feat: SSE streams use the active backend base"
```

---

## Task 5: Query-key mode prefix helper

**Files:**
- Create: `src/console/modeKey.js`
- Test: `src/console/__tests__/modeKey.test.js`

- [ ] **Step 1: Write the failing test**

`src/console/__tests__/modeKey.test.js`:
```js
import { describe, it, expect, afterEach } from 'vitest'
import { mk, setModeForKeys } from '../modeKey.js'

describe('mode query-key prefix', () => {
  afterEach(() => setModeForKeys('test'))

  it('defaults to test prefix', () => {
    expect(mk('review', '42')).toEqual(['test', 'review', '42'])
  })
  it('prefixes with the active mode', () => {
    setModeForKeys('live')
    expect(mk('assignments')).toEqual(['live', 'assignments'])
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/console/__tests__/modeKey.test.js`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `src/console/modeKey.js`**

```js
// Query-key namespacing so Test and Live caches never collide.
// The ConsoleModeProvider is the single writer of the current mode.
let currentMode = 'test'

export function setModeForKeys(mode) { currentMode = mode }

/** Prefix a React Query key with the active console mode. */
export function mk(...parts) { return [currentMode, ...parts] }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/console/__tests__/modeKey.test.js`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/console/modeKey.js src/console/__tests__/modeKey.test.js
git commit -m "feat: add mode-prefixed query-key helper"
```

---

## Task 6: ConsoleModeProvider

**Files:**
- Create: `src/console/ConsoleModeProvider.jsx`
- Modify: `src/main.jsx`
- Test: `src/console/__tests__/ConsoleModeProvider.test.jsx`

- [ ] **Step 1: Write the failing test**

`src/console/__tests__/ConsoleModeProvider.test.jsx`:
```jsx
import { describe, it, expect, beforeEach } from 'vitest'
import { render, screen, act } from '@testing-library/react'
import { ConsoleModeProvider, useConsoleMode } from '../ConsoleModeProvider.jsx'
import { getActiveApiBase } from '../../lib/apiClient.js'
import { COCKPIT_API_BASE, PIPELINE_API_BASE } from '../../config.js'

function Probe() {
  const { mode, setMode, apiBase } = useConsoleMode()
  return (
    <div>
      <span data-testid="mode">{mode}</span>
      <span data-testid="base">{apiBase}</span>
      <button onClick={() => setMode('live')}>go live</button>
    </div>
  )
}

describe('ConsoleModeProvider', () => {
  beforeEach(() => { sessionStorage.clear() })

  it('defaults to test mode + cockpit base', () => {
    render(<ConsoleModeProvider><Probe /></ConsoleModeProvider>)
    expect(screen.getByTestId('mode').textContent).toBe('test')
    expect(getActiveApiBase()).toBe(COCKPIT_API_BASE)
  })

  it('switches to live, updates base, and persists to sessionStorage', () => {
    render(<ConsoleModeProvider><Probe /></ConsoleModeProvider>)
    act(() => { screen.getByText('go live').click() })
    expect(screen.getByTestId('mode').textContent).toBe('live')
    expect(screen.getByTestId('base').textContent).toBe(PIPELINE_API_BASE)
    expect(getActiveApiBase()).toBe(PIPELINE_API_BASE)
    expect(sessionStorage.getItem('acap.consoleMode')).toBe('live')
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/console/__tests__/ConsoleModeProvider.test.jsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `src/console/ConsoleModeProvider.jsx`**

```jsx
import { createContext, useContext, useState } from 'react'
import { COCKPIT_API_BASE, PIPELINE_API_BASE } from '../config.js'
import { setActiveApiBase } from '../lib/apiClient.js'
import { setModeForKeys } from './modeKey.js'

const ConsoleModeCtx = createContext(null)
const STORAGE_KEY = 'acap.consoleMode'

const BASE_FOR = { test: COCKPIT_API_BASE, live: PIPELINE_API_BASE }

function initialMode() {
  try {
    const saved = sessionStorage.getItem(STORAGE_KEY)
    if (saved === 'test' || saved === 'live') return saved
  } catch {}
  return 'test'
}

export function ConsoleModeProvider({ children }) {
  const [mode, setModeState] = useState(initialMode)

  // Point the active backend base + query-key prefix at the current mode.
  // Runs in render (idempotent) so children always render against the right base.
  const apiBase = BASE_FOR[mode]
  setActiveApiBase(apiBase)
  setModeForKeys(mode)

  function setMode(next) {
    if (next !== 'test' && next !== 'live') return
    try { sessionStorage.setItem(STORAGE_KEY, next) } catch {}
    setActiveApiBase(BASE_FOR[next])
    setModeForKeys(next)
    setModeState(next)
  }

  return (
    <ConsoleModeCtx.Provider value={{ mode, setMode, apiBase }}>
      {children}
    </ConsoleModeCtx.Provider>
  )
}

export function useConsoleMode() {
  const ctx = useContext(ConsoleModeCtx)
  if (!ctx) throw new Error('useConsoleMode must be inside ConsoleModeProvider')
  return ctx
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/console/__tests__/ConsoleModeProvider.test.jsx`
Expected: PASS (2 tests).

- [ ] **Step 5: Wire provider into `src/main.jsx`**

Add the import after the `ThemeProvider` import:
```js
import { ConsoleModeProvider } from './console/ConsoleModeProvider.jsx'
```
Wrap `<App />` (inside `AuthProvider`):
```jsx
        <AuthProvider>
          <ConsoleModeProvider>
            <App />
          </ConsoleModeProvider>
        </AuthProvider>
```

- [ ] **Step 6: Namespace the localStorage RQ cache key by mode in `src/main.jsx`**

The persisted RQ cache must not mix modes. Change the constant:
```js
const CACHE_KEY = 'cockpit_rq_v1'
```
to:
```js
const CACHE_KEY = 'cockpit_rq_v2'   // v2: keys are now mode-prefixed arrays
```
(No other change needed — keys already carry the mode prefix from Task 7, so a fresh cache namespace avoids reading stale unprefixed entries.)

- [ ] **Step 7: Verify build + tests**

Run: `npm test && npm run build`
Expected: all tests pass; build succeeds.

- [ ] **Step 8: Commit**

```bash
git add src/console/ConsoleModeProvider.jsx src/console/__tests__/ConsoleModeProvider.test.jsx src/main.jsx
git commit -m "feat: ConsoleModeProvider with test/live switching"
```

---

## Task 7: Namespace existing query keys by mode

**Files:**
- Modify: `src/api/assignments.js`, `src/api/review.js`, `src/api/agents.js`, `src/api/cost.js`, `src/api/email.js`, `src/api/overrides.js`, `src/api/runs.js`
- Modify: `src/pages/AssignmentsPage.jsx`

> Mechanical edit: import `mk` and wrap each `queryKey` array literal. Mutations that `invalidateQueries`/`setQueryData` must use the same prefix.

- [ ] **Step 1: `src/api/assignments.js`**

Add import at top: `import { mk } from '../console/modeKey.js'`
Change `queryKey: ['assignments']` → `queryKey: mk('assignments')`
Change `queryKey: ['test_ids']` → `queryKey: mk('test_ids')`

- [ ] **Step 2: `src/api/review.js`**

Add `import { mk } from '../console/modeKey.js'`. Wrap every `queryKey: ['review', ...]` (and any other literal keys in the file) with `mk(...)`, e.g. `queryKey: mk('review', aid)`. Update any `invalidateQueries({ queryKey: ['review', aid] })` → `mk('review', aid)`.

- [ ] **Step 3: `src/api/agents.js`**

Add `import { mk } from '../console/modeKey.js'`.
- `queryKey: ['agent', aid, n]` → `queryKey: mk('agent', aid, n)`
- `queryKey: ['agent_full', aid]` → `queryKey: mk('agent_full', aid)`

- [ ] **Step 4: `src/api/cost.js`**

Add `import { mk } from '../console/modeKey.js'`. Wrap each `queryKey` literal (e.g. `['cost', aid]` → `mk('cost', aid)`).

- [ ] **Step 5: `src/api/email.js`**

Add `import { mk } from '../console/modeKey.js'`. Wrap each `queryKey` literal (e.g. `['email', aid]` → `mk('email', aid)`).

- [ ] **Step 6: `src/api/overrides.js`**

Add `import { mk } from '../console/modeKey.js'`. Replace:
- `queryKey: ['overrides', aid]` → `queryKey: mk('overrides', aid)`
- `queryKey: ['allowed']` → `queryKey: mk('allowed')`
- In `useSetOverride`/`useClearOverride` `onSuccess`: `invalidateQueries({ queryKey: ['review', aid] })` → `mk('review', aid)`, and `['overrides', aid]` → `mk('overrides', aid)`.

- [ ] **Step 7: `src/api/runs.js`**

Add `import { mk } from '../console/modeKey.js'`. In `useRerun.onSuccess` replace each `invalidateQueries({ queryKey: ['review', aid] })`, `['email', aid]`, `['cost', aid]`, `['assignments']` with the `mk(...)` equivalents. Replace `queryKey: ['jobs']` → `queryKey: mk('jobs')`.

- [ ] **Step 8: `src/pages/AssignmentsPage.jsx`**

Add `import { mk } from '../console/modeKey.js'`. In the `useQueries` block change:
```js
queryKey: ['review', id],
```
to:
```js
queryKey: mk('review', id),
```

- [ ] **Step 9: Verify build + tests + lint**

Run: `npm test && npm run build && npm run lint`
Expected: tests pass, build succeeds, no new lint errors.

- [ ] **Step 10: Commit**

```bash
git add src/api/ src/pages/AssignmentsPage.jsx
git commit -m "feat: namespace React Query keys by console mode"
```

---

## Task 8: Pipeline API hooks (Bullhorn + scheduler + manual)

**Files:**
- Create: `src/api/bullhorn.js`
- Create: `src/api/scheduler.js`

- [ ] **Step 1: Create `src/api/bullhorn.js`**

```js
import { useQuery } from '@tanstack/react-query'
import { apiClient } from '../lib/apiClient.js'
import { mk } from '../console/modeKey.js'

/** GET /bullhorn/status — live-mode connection health. */
export function useBullhornStatus(enabled = true) {
  return useQuery({
    queryKey: mk('bullhorn_status'),
    queryFn: () => apiClient.get('/bullhorn/status'),
    enabled,
    refetchInterval: 30_000,
    retry: 0,
    staleTime: 10_000,
  })
}
```

- [ ] **Step 2: Create `src/api/scheduler.js`**

```js
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { apiClient } from '../lib/apiClient.js'
import { mk } from '../console/modeKey.js'

/** GET /scheduler — auto-poll loop state. Polled 1s for the countdown. */
export function useScheduler(enabled = true) {
  return useQuery({
    queryKey: mk('scheduler'),
    queryFn: () => apiClient.get('/scheduler'),
    enabled,
    refetchInterval: 1000,
    retry: 0,
    staleTime: 0,
  })
}

function useSchedulerMutation(path, method = 'post') {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (body) => apiClient[method](path, body ?? {}),
    onSuccess: () => qc.invalidateQueries({ queryKey: mk('scheduler') }),
  })
}

export function useSchedulerStart()   { return useSchedulerMutation('/scheduler/start') }
export function useSchedulerStop()    { return useSchedulerMutation('/scheduler/stop') }
export function useSchedulerPollNow() { return useSchedulerMutation('/scheduler/poll-now') }

/** Manual operator controls (return { job_id } for SSE attach). */
export function useProcessOne() {
  return useMutation({ mutationFn: (aid) => apiClient.post(`/process/${aid}`, {}) })
}
export function usePollOnce() {
  return useMutation({ mutationFn: () => apiClient.post('/poll', {}) })
}
export function useRerunLive() {
  return useMutation({ mutationFn: (aid) => apiClient.post(`/rerun/${aid}`, {}) })
}
export function useWipeLive() {
  return useMutation({ mutationFn: (body) => apiClient.post('/wipe', body) })
}
```

- [ ] **Step 3: Verify build**

Run: `npm run build`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add src/api/bullhorn.js src/api/scheduler.js
git commit -m "feat: add bullhorn + scheduler pipeline hooks"
```

---

## Task 9: Audit hooks + timeline transform

**Files:**
- Create: `src/lib/audit.js`
- Create: `src/api/audit.js`
- Test: `src/lib/__tests__/audit.test.js`

- [ ] **Step 1: Write the failing test**

`src/lib/__tests__/audit.test.js`:
```js
import { describe, it, expect } from 'vitest'
import { buildTimeline } from '../audit.js'

describe('buildTimeline', () => {
  it('returns an empty array when there is no summary', () => {
    expect(buildTimeline(null)).toEqual([])
    expect(buildTimeline({})).toEqual([])
  })

  it('normalizes timeline entries from the audit summary', () => {
    const audit = {
      summary: {
        final_status: 'GREEN',
        total_duration_seconds: 42,
        agents_run: 6,
        timeline: [
          { agent: '2', critic_verdict: 'PASS', duration_seconds: 5, errors_count: 0 },
          { agent: '5', critic_verdict: 'FLAGGED', duration_seconds: 9 },
        ],
      },
    }
    const rows = buildTimeline(audit)
    expect(rows).toHaveLength(2)
    expect(rows[0]).toEqual({ agent: '2', verdict: 'PASS', duration: 5, errors: 0, failed: false })
    expect(rows[1]).toEqual({ agent: '5', verdict: 'FLAGGED', duration: 9, errors: 0, failed: true })
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/lib/__tests__/audit.test.js`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `src/lib/audit.js`**

```js
/**
 * Normalize a backend /assignment/<aid> audit payload into timeline rows.
 * Pure: no network, no React.
 */
export function buildTimeline(audit) {
  const tl = audit?.summary?.timeline
  if (!Array.isArray(tl)) return []
  return tl.map((e) => {
    const verdict = e.critic_verdict ?? e.verdict ?? ''
    const failed = /FAIL/i.test(verdict) || verdict.toUpperCase() === 'FLAGGED' || (e.errors_count ?? 0) > 0
    return {
      agent: String(e.agent ?? '?'),
      verdict,
      duration: e.duration_seconds ?? 0,
      errors: e.errors_count ?? 0,
      failed,
    }
  })
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/lib/__tests__/audit.test.js`
Expected: PASS (2 tests).

- [ ] **Step 5: Create `src/api/audit.js`**

```js
import { useQuery } from '@tanstack/react-query'
import { apiClient } from '../lib/apiClient.js'
import { mk } from '../console/modeKey.js'

/** GET /assignment/<aid> — full audit log (backend only). */
export function useAuditLog(aid) {
  return useQuery({
    queryKey: mk('audit', aid),
    queryFn: () => apiClient.get(`/assignment/${aid}`),
    enabled: !!aid,
    staleTime: 30_000,
  })
}

/** GET /assignment/<aid>/cost — LLM cost breakdown. */
export function useCost(aid) {
  return useQuery({
    queryKey: mk('cost', aid),
    queryFn: () => apiClient.get(`/assignment/${aid}/cost`),
    enabled: !!aid,
    staleTime: 30_000,
  })
}
```

- [ ] **Step 6: Commit**

```bash
git add src/lib/audit.js src/api/audit.js src/lib/__tests__/audit.test.js
git commit -m "feat: add audit log hooks + timeline transform"
```

---

## Task 10: ModeSwitch (TopBar segmented control)

**Files:**
- Create: `src/components/shell/ModeSwitch.jsx`
- Modify: `src/components/shell/TopBar.jsx`

- [ ] **Step 1: Create `src/components/shell/ModeSwitch.jsx`**

Pure Tailwind + framer-motion sliding pill; Live shows a Bullhorn status dot via `useBullhornStatus` (only fetched when in live mode).

```jsx
import { motion } from 'framer-motion'
import { useNavigate, useLocation } from 'react-router-dom'
import { useConsoleMode } from '../../console/ConsoleModeProvider.jsx'
import { useBullhornStatus } from '../../api/bullhorn.js'

const MODES = [
  { key: 'test', label: 'Test', icon: '🧪' },
  { key: 'live', label: 'Live', icon: '🛰' },
]

export default function ModeSwitch() {
  const { mode, setMode } = useConsoleMode()
  const navigate = useNavigate()
  const location = useLocation()

  // Only ping Bullhorn when actually in live mode.
  const { data: bh, isError } = useBullhornStatus(mode === 'live')
  const connected = mode === 'live' && !isError && !!bh?.connected
  const dotClass = mode !== 'live'
    ? 'bg-text-muted/40'
    : connected ? 'bg-tier-green' : 'bg-tier-red'

  function pick(next) {
    if (next === mode) return
    setMode(next)
    // Send the user to that mode's landing.
    if (next === 'live') navigate('/live')
    else if (location.pathname === '/live') navigate('/')
  }

  return (
    <div className="relative flex items-center gap-1 rounded-xl p-1 border border-brand-sky/15 bg-brand-sky/5">
      {MODES.map((m) => {
        const active = mode === m.key
        return (
          <button
            key={m.key}
            onClick={() => pick(m.key)}
            className="relative z-10 flex items-center gap-1.5 px-3 py-1 rounded-lg text-[11px] font-semibold font-sans tracking-wide transition-colors btn-press"
            style={{ color: active ? '#fff' : undefined }}
          >
            {active && (
              <motion.span
                layoutId="modeSwitchPill"
                className="absolute inset-0 -z-10 rounded-lg"
                style={{ background: 'linear-gradient(135deg,#005280,#1DAEEF)', boxShadow: '0 2px 10px rgba(29,174,239,0.35)' }}
                transition={{ type: 'spring', stiffness: 380, damping: 30 }}
              />
            )}
            <span className={active ? '' : 'text-text-muted'}>{m.icon}</span>
            <span className={active ? '' : 'text-text-muted'}>{m.label}</span>
            {m.key === 'live' && (
              <span className={`w-1.5 h-1.5 rounded-full ${dotClass} ${mode === 'live' && connected ? 'animate-pulse-dot' : ''}`} />
            )}
          </button>
        )
      })}
    </div>
  )
}
```

- [ ] **Step 2: Render `<ModeSwitch/>` in `src/components/shell/TopBar.jsx`**

Add import at top:
```js
import ModeSwitch from './ModeSwitch.jsx'
```
Inside the left cluster `div` (after the ACAP wordmark block, still inside `<div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>`), add:
```jsx
        <div style={{ width: 1, height: 18, background: t.divider }} />
        <ModeSwitch />
```

- [ ] **Step 3: Verify build + manual check**

Run: `npm run build`
Then `npm run dev` and confirm the Test/Live pill renders in the top bar and the pill slides when toggled.
Expected: build succeeds; pill animates; switching to Live navigates to `/live` (route added in Task 18 — until then it shows NotFound, which is fine at this step).

- [ ] **Step 4: Commit**

```bash
git add src/components/shell/ModeSwitch.jsx src/components/shell/TopBar.jsx
git commit -m "feat: TopBar Test/Live mode switch"
```

---

## Task 11: Mode-aware Sidebar

**Files:**
- Modify: `src/components/shell/Sidebar.jsx`

- [ ] **Step 1: Import the mode hook**

At the top of `Sidebar.jsx` add:
```js
import { useConsoleMode } from '../../console/ConsoleModeProvider.jsx'
```

- [ ] **Step 2: Add a Live nav icon + per-mode nav arrays**

Replace the single `NAV_ITEMS` const with both arrays (keep the existing `DashIcon`, `PipeIcon`, `ListIcon` functions; add `LiveIcon`):
```js
function LiveIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M4 12a8 8 0 0 1 8-8M4 12a8 8 0 0 0 8 8M20 12a8 8 0 0 0-8-8"/>
      <circle cx="12" cy="12" r="2.5" fill="currentColor" stroke="none"/>
    </svg>
  )
}

const NAV_TEST = [
  { to: '/',            label: 'Dashboard',    icon: DashIcon },
  { to: '/run',         label: 'Run Pipeline', icon: PipeIcon },
  { to: '/assignments', label: 'Assignments',  icon: ListIcon },
]
const NAV_LIVE = [
  { to: '/live',        label: 'Live Feed',    icon: LiveIcon },
  { to: '/assignments', label: 'Assignments',  icon: ListIcon },
]
```

- [ ] **Step 3: Select the array by mode inside the component**

In `export default function Sidebar({ collapsed })`, after `const t = useTokens()` add:
```js
  const { mode } = useConsoleMode()
  const NAV_ITEMS = mode === 'live' ? NAV_LIVE : NAV_TEST
```
(The existing `NAV_ITEMS.map(...)` JSX now reads the mode-selected array.)

- [ ] **Step 4: Verify build + manual check**

Run: `npm run build`
Then in `npm run dev`: switching to Live changes the sidebar nav to Live Feed · Assignments; switching back restores Dashboard · Run · Assignments.
Expected: build succeeds; nav swaps with mode.

- [ ] **Step 5: Commit**

```bash
git add src/components/shell/Sidebar.jsx
git commit -m "feat: mode-aware sidebar navigation"
```

---

## Task 12: AssignmentRail (mode-aware list)

**Files:**
- Create: `src/components/workspace/AssignmentRail.jsx`

> Reuses existing `useAssignments`/`useTestIds`, `apiClient`, `useDebounce`, `TierChip`. Pure Tailwind. Test mode unions test_ids + assignments and badges TEST; Live badges LIVE. Clicking navigates to `/review/:aid` (the workspace route, Task 18).

- [ ] **Step 1: Create `src/components/workspace/AssignmentRail.jsx`**

```jsx
import { useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useQueries } from '@tanstack/react-query'
import { useAssignments, useTestIds } from '../../api/assignments.js'
import { apiClient } from '../../lib/apiClient.js'
import { mk } from '../../console/modeKey.js'
import { useConsoleMode } from '../../console/ConsoleModeProvider.jsx'
import { useDebounce } from '../../hooks/useDebounce.js'
import TierChip from '../common/TierChip.jsx'

export default function AssignmentRail() {
  const { mode } = useConsoleMode()
  const navigate = useNavigate()
  const { aid: activeAid } = useParams()
  const [search, setSearch] = useState('')
  const q = useDebounce(search, 200).toLowerCase()

  const { data: assignmentsData } = useAssignments()
  const { data: testData } = useTestIds()

  const assignmentIds = (assignmentsData?.assignment_ids ?? assignmentsData ?? []).map(String)
  const testIds = (testData?.test_ids ?? []).map((x) => String(x.assignment_id ?? x))
  const ids = mode === 'live'
    ? assignmentIds
    : [...new Set([...testIds, ...assignmentIds])]

  const reviews = useQueries({
    queries: ids.map((id) => ({
      queryKey: mk('review', id),
      queryFn: () => apiClient.get(`/review/${id}`),
      enabled: !!id,
      staleTime: 30_000,
      retry: 0,
    })),
  })
  const reviewById = Object.fromEntries(ids.map((id, i) => [id, reviews[i]?.data]))

  const shown = ids.filter((id) => {
    if (!q) return true
    const r = reviewById[id]
    return id.includes(q) || (r?.candidate ?? '').toLowerCase().includes(q) || (r?.district ?? '').toLowerCase().includes(q)
  })

  return (
    <div className="flex flex-col h-full">
      <div className="px-3 pt-3 pb-2">
        <div className="flex items-center justify-between mb-2">
          <span className="text-[10px] font-bold uppercase tracking-[0.14em] text-text-muted font-sans">
            {mode === 'live' ? 'Live Assignments' : 'Test Assignments'}
          </span>
          <span className="text-[10px] font-mono text-text-muted">{shown.length}/{ids.length}</span>
        </div>
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search id, candidate, district…"
          className="w-full px-3 py-1.5 rounded-lg text-[11px] font-sans bg-brand-bg-2 border border-brand-sky/15 text-text-strong outline-none focus-ring"
        />
      </div>

      <div className="flex-1 overflow-y-auto px-2 pb-3 flex flex-col gap-1.5">
        {shown.length === 0 && (
          <div className="text-[11px] text-text-muted font-sans px-3 py-6 text-center">No assignments.</div>
        )}
        {shown.map((id, i) => {
          const r = reviewById[id]
          const active = String(activeAid) === id
          const tier = r?.hitl_tier
          const accent = tier === 'RED' ? '#C0392B' : tier === 'YELLOW' ? '#C9871A' : tier === 'GREEN' ? '#1F8A4C' : '#1DAEEF'
          return (
            <button
              key={id}
              onClick={() => navigate(`/review/${id}`)}
              className="text-left rounded-xl px-3 py-2 border transition-all duration-150 hover-lift stagger-item"
              style={{
                animationDelay: `${Math.min(i, 12) * 30}ms`,
                borderColor: active ? accent : 'rgba(29,174,239,0.14)',
                background: active ? 'rgba(29,174,239,0.08)' : 'var(--brand-surface)',
                boxShadow: active ? `0 0 0 1px ${accent}40` : 'none',
              }}
            >
              <div className="flex items-center gap-2">
                <span className="w-1 self-stretch rounded-full shrink-0" style={{ background: accent }} />
                {tier && <TierChip tier={tier} />}
                <div className="min-w-0 flex-1">
                  <div className="text-[12px] font-bold font-display text-text-strong truncate">
                    {r?.candidate ?? `Assignment ${id}`}
                  </div>
                  <div className="text-[10px] text-text-muted font-sans truncate">
                    {r?.district ? `${r.district} · ` : ''}<span className="font-mono">#{id}</span>
                  </div>
                </div>
                <span
                  className="text-[8px] font-bold tracking-wider px-1.5 py-0.5 rounded font-sans shrink-0"
                  style={{
                    color: mode === 'live' ? '#1F8A4C' : '#1DAEEF',
                    background: mode === 'live' ? 'rgba(31,138,76,0.12)' : 'rgba(29,174,239,0.12)',
                  }}
                >
                  {mode === 'live' ? 'LIVE' : 'TEST'}
                </span>
              </div>
            </button>
          )
        })}
      </div>
    </div>
  )
}
```

- [ ] **Step 2: Verify build**

Run: `npm run build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add src/components/workspace/AssignmentRail.jsx
git commit -m "feat: mode-aware assignment rail"
```

---

## Task 13: Export AgentContent + AGENTS from AgentOutputPanel

**Files:**
- Modify: `src/components/review/AgentOutputPanel.jsx`

> The per-agent tabs in WorkspaceTabs reuse the existing agent views. Expose them as named exports without changing the default export's behavior.

- [ ] **Step 1: Export the agent metadata**

Change:
```js
const AGENTS = [
```
to:
```js
export const AGENTS = [
```

- [ ] **Step 2: Export the per-agent content renderer**

Change the declaration:
```js
function AgentContent({ aid, n, agent }) {
```
to:
```js
export function AgentContent({ aid, n, agent }) {
```

- [ ] **Step 3: Verify build + tests**

Run: `npm run build && npm test`
Expected: build succeeds (default export unchanged; ReviewPage still works); tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/components/review/AgentOutputPanel.jsx
git commit -m "refactor: export AGENTS + AgentContent for reuse"
```

---

## Task 14: AuditPanel

**Files:**
- Create: `src/components/review/AuditPanel.jsx`

> New audit drilldown — fetches from backend (`useAuditLog`, `useCost`), renders `buildTimeline` as an animated vertical stepper + summary + raw agent JSON fetcher.

- [ ] **Step 1: Create `src/components/review/AuditPanel.jsx`**

```jsx
import { useState } from 'react'
import { motion } from 'framer-motion'
import { useAuditLog, useCost } from '../../api/audit.js'
import { useAgentOutput } from '../../api/agents.js'
import { buildTimeline } from '../../lib/audit.js'
import Spinner from '../common/Spinner.jsx'

const AGENT_NUMS = ['2', '3', '4', '5', '5_5', '6']

export default function AuditPanel({ aid }) {
  const { data: audit, isLoading, error } = useAuditLog(aid)
  const { data: cost } = useCost(aid)
  const [rawN, setRawN] = useState(null)
  const { data: rawData, isLoading: rawLoading } = useAgentOutput(rawN ? aid : null, rawN)

  if (isLoading) {
    return (
      <div className="flex flex-col items-center gap-3 py-10">
        <Spinner size={24} color="#1DAEEF" />
        <span className="text-xs text-text-muted font-sans">Loading audit log…</span>
      </div>
    )
  }
  if (error || !audit) {
    return <div className="text-xs text-text-muted font-sans py-8 text-center">No audit log for assignment {aid}.</div>
  }

  const s = audit.summary ?? {}
  const rows = buildTimeline(audit)

  return (
    <div className="flex flex-col gap-5">
      {/* Summary tiles */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
        {[
          ['Final status', s.final_status ?? '—'],
          ['Duration', s.total_duration_seconds != null ? `${s.total_duration_seconds}s` : '—'],
          ['Agents run', s.agents_run ?? '—'],
          ['LLM cost', cost?.total_usd != null ? `$${Number(cost.total_usd).toFixed(4)}` : '—'],
        ].map(([label, val]) => (
          <div key={label} className="rounded-xl border border-brand-sky/15 bg-brand-surface px-3 py-2.5">
            <div className="text-[15px] font-bold font-display text-text-strong tabnum truncate">{val}</div>
            <div className="text-[9px] uppercase tracking-wider text-text-muted font-sans mt-0.5">{label}</div>
          </div>
        ))}
      </div>

      {/* Timeline stepper */}
      <div>
        <div className="text-[10px] font-bold uppercase tracking-[0.1em] text-text-muted font-sans mb-3">Agent Timeline</div>
        {rows.length === 0 ? (
          <div className="text-xs text-text-muted font-sans">No timeline entries.</div>
        ) : (
          <div className="relative pl-5">
            <div className="absolute left-[7px] top-1 bottom-1 w-px bg-brand-sky/20" />
            <div className="flex flex-col gap-2.5">
              {rows.map((r, i) => (
                <motion.div
                  key={`${r.agent}-${i}`}
                  initial={{ opacity: 0, x: -8 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: Math.min(i, 10) * 0.05 }}
                  className="relative flex items-center gap-3"
                >
                  <span
                    className="absolute -left-5 w-3.5 h-3.5 rounded-full border-2 border-brand-bg"
                    style={{ background: r.failed ? '#C9871A' : '#1F8A4C' }}
                  />
                  <div className="flex-1 flex items-center gap-3 rounded-lg border border-brand-sky/12 bg-brand-surface px-3 py-2">
                    <span className="text-[11px] font-bold font-mono text-text-strong">Agent {r.agent.replace('_', '.')}</span>
                    <span
                      className="text-[10px] font-semibold font-sans px-2 py-0.5 rounded-full"
                      style={{ color: r.failed ? '#C9871A' : '#1F8A4C', background: r.failed ? 'rgba(201,135,26,0.12)' : 'rgba(31,138,76,0.12)' }}
                    >
                      {r.failed ? '⚠' : '✓'} {r.verdict || (r.failed ? 'FLAGGED' : 'PASS')}
                    </span>
                    <span className="ml-auto text-[10px] text-text-muted font-mono tabnum">{r.duration}s</span>
                    {r.errors > 0 && <span className="text-[10px] text-tier-red font-mono">{r.errors} err</span>}
                  </div>
                </motion.div>
              ))}
            </div>
          </div>
        )}
      </div>

      {/* Raw agent JSON */}
      <div>
        <div className="text-[10px] font-bold uppercase tracking-[0.1em] text-text-muted font-sans mb-2">Raw agent output</div>
        <div className="flex flex-wrap gap-1.5 mb-2">
          {AGENT_NUMS.map((n) => (
            <button
              key={n}
              onClick={() => setRawN(n)}
              className="text-[11px] font-sans font-semibold px-2.5 py-1 rounded-lg border btn-press transition-colors"
              style={{
                borderColor: rawN === n ? '#1DAEEF' : 'rgba(29,174,239,0.18)',
                color: rawN === n ? '#1DAEEF' : 'var(--text-muted)',
                background: rawN === n ? 'rgba(29,174,239,0.1)' : 'transparent',
              }}
            >
              {n.replace('_', '.')}
            </button>
          ))}
        </div>
        {rawN && (
          <pre className="rounded-lg p-3 text-[10px] font-mono overflow-auto max-h-80 border border-brand-sky/12"
               style={{ background: 'rgba(5,12,25,0.85)', color: '#3FC8EF' }}>
            {rawLoading ? 'Loading…' : JSON.stringify(rawData ?? {}, null, 2)}
          </pre>
        )}
      </div>
    </div>
  )
}
```

- [ ] **Step 2: Verify build**

Run: `npm run build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add src/components/review/AuditPanel.jsx
git commit -m "feat: audit panel with timeline + raw agent JSON"
```

---

## Task 15: WorkspaceTabs

**Files:**
- Create: `src/components/workspace/WorkspaceTabs.jsx`

> The per-assignment tab bar. Review tab hosts the existing review content (Checklist + overrides via the existing ReviewPage body); agent tabs reuse `AgentContent`; Preview reuses `EmailPreview`; Audit uses `AuditPanel`. Override-count badges read `useOverrides`. Sliding underline via framer-motion `layoutId`; collapses to a `<select>` under `sm`.

- [ ] **Step 1: Create `src/components/workspace/WorkspaceTabs.jsx`**

```jsx
import { useState } from 'react'
import { motion } from 'framer-motion'
import { AGENTS, AgentContent } from '../review/AgentOutputPanel.jsx'
import EmailPreview from '../review/EmailPreview.jsx'
import AuditPanel from '../review/AuditPanel.jsx'
import { useOverrides } from '../../api/overrides.js'

const AGENT_TAB_LABELS = {
  '2': 'Intake', '3': 'Assignment', '4': 'Requirements',
  '5': 'Docs', '5_5': 'Gate', '6': 'Email',
}

export default function WorkspaceTabs({ aid, reviewSlot }) {
  const [tab, setTab] = useState('review')
  const { data: overrides } = useOverrides(aid)

  // Build the tab list.
  const tabs = [
    { key: 'review', label: 'Review', icon: '📋' },
    ...AGENTS.map((a) => ({
      key: `agent_${a.n}`,
      label: AGENT_TAB_LABELS[a.n] ?? a.label,
      icon: a.icon,
      agentN: a.n,
    })),
    { key: 'preview', label: 'Preview', icon: '✉' },
    { key: 'audit', label: 'Audit', icon: '🧩' },
  ]

  function overrideCount(agentN) {
    if (!agentN || !overrides) return 0
    return Object.keys(overrides[`agent_${agentN}`] ?? {}).length
  }

  const active = tabs.find((t) => t.key === tab) ?? tabs[0]

  return (
    <div className="flex flex-col gap-4">
      {/* Mobile dropdown */}
      <div className="sm:hidden">
        <select
          value={tab}
          onChange={(e) => setTab(e.target.value)}
          className="w-full px-3 py-2 rounded-lg text-xs font-sans bg-brand-bg-2 border border-brand-sky/15 text-text-strong outline-none"
        >
          {tabs.map((t) => <option key={t.key} value={t.key}>{t.icon} {t.label}</option>)}
        </select>
      </div>

      {/* Desktop tab bar */}
      <div className="hidden sm:flex items-center gap-1 overflow-x-auto border-b border-brand-sky/12 pb-px">
        {tabs.map((t) => {
          const isActive = t.key === tab
          const n = overrideCount(t.agentN)
          return (
            <button
              key={t.key}
              onClick={() => setTab(t.key)}
              className="relative flex items-center gap-1.5 px-3 py-2 text-[11px] font-semibold font-sans whitespace-nowrap transition-colors"
              style={{ color: isActive ? '#1DAEEF' : 'var(--text-muted)' }}
            >
              <span>{t.icon}</span>
              <span>{t.label}</span>
              {n > 0 && (
                <span className="ml-0.5 text-[9px] font-bold text-white rounded-full px-1.5 py-px"
                      style={{ background: '#1DAEEF' }}>
                  {n}
                </span>
              )}
              {isActive && (
                <motion.span
                  layoutId="workspaceTabUnderline"
                  className="absolute left-2 right-2 -bottom-px h-0.5 rounded-full"
                  style={{ background: 'linear-gradient(90deg,#005280,#1DAEEF,#3FC8EF)' }}
                  transition={{ type: 'spring', stiffness: 400, damping: 32 }}
                />
              )}
            </button>
          )
        })}
      </div>

      {/* Panel */}
      <motion.div
        key={tab}
        initial={{ opacity: 0, y: 6 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.22 }}
      >
        {tab === 'review' && reviewSlot}
        {active.agentN && (
          <AgentContent key={`${aid}-${active.agentN}`} aid={aid} n={active.agentN} agent={active} />
        )}
        {tab === 'preview' && <EmailPreview aid={aid} />}
        {tab === 'audit' && <AuditPanel aid={aid} />}
      </motion.div>
    </div>
  )
}
```

- [ ] **Step 2: Verify build**

Run: `npm run build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add src/components/workspace/WorkspaceTabs.jsx
git commit -m "feat: per-assignment workspace tab bar"
```

---

## Task 16: BullhornStatusCard

**Files:**
- Create: `src/components/live/BullhornStatusCard.jsx`

- [ ] **Step 1: Create `src/components/live/BullhornStatusCard.jsx`**

```jsx
import { motion } from 'framer-motion'
import { useBullhornStatus } from '../../api/bullhorn.js'

function Row({ k, v, mono }) {
  if (v == null || v === '') return null
  return (
    <div className="grid grid-cols-[120px_1fr] gap-2 py-1 text-[12px]">
      <span className="text-text-muted font-sans">{k}</span>
      <span className={`text-text-strong ${mono ? 'font-mono break-all' : 'font-sans'}`}>{String(v)}</span>
    </div>
  )
}

export default function BullhornStatusCard() {
  const { data, isLoading, isError, refetch, isFetching } = useBullhornStatus(true)
  const connected = !isError && !!data?.connected

  return (
    <div className="rounded-2xl border border-brand-sky/15 bg-brand-surface p-5 card-hover">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-[13px] font-bold font-display text-text-strong">Bullhorn connection</h3>
        <button
          onClick={() => refetch()}
          className="text-[11px] font-sans font-semibold px-2.5 py-1 rounded-lg border border-brand-sky/20 text-brand-sky btn-press"
        >
          {isFetching ? 'Checking…' : 'Re-check'}
        </button>
      </div>

      <div className="flex items-center gap-3 mb-4">
        <span className="relative flex items-center justify-center w-10 h-10 rounded-full"
              style={{ background: connected ? 'rgba(31,138,76,0.12)' : 'rgba(192,57,43,0.12)' }}>
          <motion.span
            className="w-3.5 h-3.5 rounded-full"
            style={{ background: connected ? '#1F8A4C' : '#C0392B' }}
            animate={connected ? { scale: [1, 1.25, 1] } : {}}
            transition={{ repeat: Infinity, duration: 2 }}
          />
        </span>
        <div>
          <div className="text-[14px] font-bold font-display"
               style={{ color: connected ? '#1F8A4C' : '#C0392B' }}>
            {isLoading ? 'Checking…' : connected ? 'CONNECTED' : 'NOT CONNECTED'}
          </div>
          <div className="text-[11px] text-text-muted font-sans">
            {connected ? (data?.username ?? '') : (data?.error ?? (isError ? 'Pipeline API unreachable' : 'configure BH_* env vars'))}
          </div>
        </div>
      </div>

      {connected && (
        <div className="border-t border-brand-sky/10 pt-3">
          <Row k="user" v={data?.username} />
          <Row k="REST endpoint" v={data?.rest_url} mono />
          <Row k="auth ping" v={data?.ping_ms != null ? `${data.ping_ms} ms` : null} />
          <Row k="token age" v={data?.token_age_sec != null ? `${data.token_age_sec}s` : null} />
        </div>
      )}
    </div>
  )
}
```

- [ ] **Step 2: Verify build**

Run: `npm run build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add src/components/live/BullhornStatusCard.jsx
git commit -m "feat: bullhorn status card"
```

---

## Task 17: SchedulerPanel

**Files:**
- Create: `src/components/live/SchedulerPanel.jsx`

> Renders scheduler state with an animated countdown ring, stat tiles, new-EDU-ID pills, and start/stop/poll-now controls. `onAttach(jobId)` lets the parent attach the SSE feed.

- [ ] **Step 1: Create `src/components/live/SchedulerPanel.jsx`**

```jsx
import { useScheduler, useSchedulerStart, useSchedulerStop, useSchedulerPollNow } from '../../api/scheduler.js'

function fmtClock(s) {
  if (s == null) return '—'
  const m = Math.floor(s / 60)
  const ss = String(s % 60).padStart(2, '0')
  return `${m}:${ss}`
}

function Ring({ seconds, interval }) {
  const total = (interval ?? 5) * 60
  const pct = seconds != null && total > 0 ? Math.max(0, Math.min(1, 1 - seconds / total)) : 0
  const R = 26
  const C = 2 * Math.PI * R
  return (
    <svg width="64" height="64" viewBox="0 0 64 64" className="shrink-0">
      <circle cx="32" cy="32" r={R} fill="none" stroke="rgba(29,174,239,0.15)" strokeWidth="5" />
      <circle
        cx="32" cy="32" r={R} fill="none" stroke="#1DAEEF" strokeWidth="5" strokeLinecap="round"
        strokeDasharray={C} strokeDashoffset={C * (1 - pct)}
        transform="rotate(-90 32 32)" style={{ transition: 'stroke-dashoffset 1s linear' }}
      />
      <text x="32" y="36" textAnchor="middle" fontSize="11" fill="#1DAEEF" fontFamily="JetBrains Mono, monospace">
        {fmtClock(seconds)}
      </text>
    </svg>
  )
}

export default function SchedulerPanel({ onAttach }) {
  const { data: sch } = useScheduler(true)
  const start = useSchedulerStart()
  const stop = useSchedulerStop()
  const pollNow = useSchedulerPollNow()

  const d = sch ?? {}
  const on = !!d.enabled
  const state = on ? (d.running ? 'POLLING' : 'RUNNING') : 'STOPPED'
  const stateColor = on ? '#1F8A4C' : '#C0392B'

  async function doStart() {
    const res = await start.mutateAsync({})
    if (res?.job_id) onAttach?.(res.job_id)
  }
  async function doPollNow() {
    const res = await pollNow.mutateAsync()
    if (res?.job_id) onAttach?.(res.job_id)
  }

  const stats = [
    ['next poll', d.running ? 'polling…' : on ? fmtClock(d.seconds_to_next) : 'stopped'],
    ['last poll', d.last_poll_at ? String(d.last_poll_at).replace('T', ' ') : '—'],
    ['polls run', d.polls_run ?? 0],
    ['processed', d.total_processed ?? 0],
    ['new last cycle', (d.last_new_ids ?? []).length],
  ]

  return (
    <div className="rounded-2xl border border-brand-sky/15 bg-brand-surface p-5 card-hover">
      <div className="flex items-start justify-between gap-3 mb-4 flex-wrap">
        <div className="flex items-center gap-3">
          <Ring seconds={d.seconds_to_next} interval={d.interval_min} />
          <div>
            <div className="flex items-center gap-2">
              <h3 className="text-[13px] font-bold font-display text-text-strong">Auto-poll loop</h3>
              <span className="text-[10px] font-bold font-sans px-2 py-0.5 rounded-full"
                    style={{ color: stateColor, background: `${stateColor}1f` }}>
                {state}
              </span>
            </div>
            <p className="text-[11px] text-text-muted font-sans mt-1 max-w-md">
              Every <b>{d.interval_min ?? 5}</b> min the API polls Bullhorn for new EDU placements and runs the full pipeline.
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <button onClick={doStart} disabled={start.isPending}
                  className="text-[11px] font-sans font-bold px-3 py-1.5 rounded-lg text-white btn-press disabled:opacity-50"
                  style={{ background: 'linear-gradient(135deg,#005280,#1DAEEF)' }}>
            ▶ Start
          </button>
          <button onClick={() => stop.mutate()} disabled={stop.isPending}
                  className="text-[11px] font-sans font-semibold px-3 py-1.5 rounded-lg border border-brand-sky/20 text-text-muted btn-press">
            ⏸ Stop
          </button>
          <button onClick={doPollNow} disabled={pollNow.isPending}
                  className="text-[11px] font-sans font-semibold px-3 py-1.5 rounded-lg border border-brand-sky/20 text-text-muted btn-press">
            ⟳ Poll now
          </button>
        </div>
      </div>

      <div className="grid grid-cols-2 sm:grid-cols-5 gap-2">
        {stats.map(([label, val]) => (
          <div key={label} className="rounded-xl border border-brand-sky/12 bg-brand-bg-2 px-3 py-2">
            <div className="text-[14px] font-bold font-display text-text-strong tabnum truncate">{String(val)}</div>
            <div className="text-[9px] uppercase tracking-wider text-text-muted font-sans mt-0.5">{label}</div>
          </div>
        ))}
      </div>

      {(d.last_new_ids ?? []).length > 0 && (
        <div className="mt-3 flex items-center gap-2 flex-wrap">
          <span className="text-[11px] text-text-muted font-sans">EDU placements last cycle:</span>
          {d.last_new_ids.map((id) => (
            <span key={id} className="text-[11px] font-mono px-2 py-0.5 rounded-md border border-brand-sky/15 bg-brand-sky/5 text-text-strong">
              {id}
            </span>
          ))}
        </div>
      )}

      {d.last_error && (
        <div className="mt-3 text-[11px] font-sans px-3 py-2 rounded-lg" style={{ color: '#C0392B', background: 'rgba(192,57,43,0.08)' }}>
          ⚠ {d.last_error}
        </div>
      )}
    </div>
  )
}
```

- [ ] **Step 2: Verify build**

Run: `npm run build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add src/components/live/SchedulerPanel.jsx
git commit -m "feat: scheduler panel with countdown ring"
```

---

## Task 18: ManualControls + LiveFeedPage + routing

**Files:**
- Create: `src/components/live/ManualControls.jsx`
- Create: `src/pages/LiveFeedPage.jsx`
- Create: `src/pages/WorkspacePage.jsx`
- Modify: `src/App.jsx`
- Modify: `src/components/shell/AppShell.jsx`

- [ ] **Step 1: Create `src/components/live/ManualControls.jsx`**

```jsx
import { useState } from 'react'
import { useProcessOne, usePollOnce, useRerunLive, useWipeLive } from '../../api/scheduler.js'

export default function ManualControls({ onAttach }) {
  const [open, setOpen] = useState(false)
  const [aid, setAid] = useState('')
  const [reread, setReread] = useState(false)
  const processOne = useProcessOne()
  const pollOnce = usePollOnce()
  const rerun = useRerunLive()
  const wipe = useWipeLive()

  async function run(mut, arg) {
    const res = await mut.mutateAsync(arg)
    if (res?.job_id) onAttach?.(res.job_id)
  }

  return (
    <div className="rounded-2xl border border-brand-sky/15 bg-brand-surface p-5">
      <button onClick={() => setOpen((o) => !o)} className="flex items-center gap-2 text-[13px] font-bold font-display text-text-strong">
        <span style={{ transform: open ? 'rotate(90deg)' : 'none', transition: 'transform 0.2s' }}>▸</span>
        Manual controls
        <span className="text-[10px] font-sans font-normal text-text-muted">(operator override)</span>
      </button>

      {open && (
        <div className="mt-4 flex flex-col gap-3 animate-slide-down">
          <div className="flex items-center gap-2 flex-wrap">
            <input
              value={aid} onChange={(e) => setAid(e.target.value)} placeholder="assignment id"
              className="px-3 py-1.5 rounded-lg text-[11px] font-mono bg-brand-bg-2 border border-brand-sky/15 text-text-strong outline-none w-32"
            />
            <label className="flex items-center gap-1.5 text-[11px] text-text-muted font-sans cursor-pointer">
              <input type="checkbox" checked={reread} onChange={(e) => setReread(e.target.checked)} /> re-read docs
            </label>
          </div>
          <div className="flex items-center gap-2 flex-wrap">
            <button disabled={!aid} onClick={() => run(processOne, aid)} className="text-[11px] font-sans font-semibold px-3 py-1.5 rounded-lg border border-brand-sky/20 text-text-strong btn-press disabled:opacity-40">Process one (/process)</button>
            <button onClick={() => run(pollOnce)} className="text-[11px] font-sans font-semibold px-3 py-1.5 rounded-lg border border-brand-sky/20 text-text-strong btn-press">Force poll (/poll)</button>
            <button disabled={!aid} onClick={() => run(rerun, aid)} className="text-[11px] font-sans font-semibold px-3 py-1.5 rounded-lg border border-brand-sky/20 text-text-strong btn-press disabled:opacity-40">Rerun selected</button>
            <button disabled={!aid} onClick={() => wipe.mutate({ ids: [aid], reread })} className="text-[11px] font-sans font-semibold px-3 py-1.5 rounded-lg border btn-press disabled:opacity-40" style={{ borderColor: 'rgba(192,57,43,0.4)', color: '#C0392B' }}>Wipe selected</button>
          </div>
        </div>
      )}
    </div>
  )
}
```

- [ ] **Step 2: Create `src/pages/LiveFeedPage.jsx`**

Reuses the existing `TerminalLog` for the SSE console and `useSSE` for streaming.

```jsx
import { useState, useEffect } from 'react'
import BullhornStatusCard from '../components/live/BullhornStatusCard.jsx'
import SchedulerPanel from '../components/live/SchedulerPanel.jsx'
import ManualControls from '../components/live/ManualControls.jsx'
import TerminalLog from '../components/run/TerminalLog.jsx'
import { useScheduler } from '../api/scheduler.js'
import { useSSE } from '../hooks/useSSE.js'

export default function LiveFeedPage() {
  const [jobId, setJobId] = useState(null)
  const [logCollapsed, setLogCollapsed] = useState(false)
  const { logLines, status } = useSSE(jobId)
  const { data: sch } = useScheduler(true)

  // Auto-attach to a running scheduler job on first load.
  useEffect(() => {
    if (!jobId && sch?.enabled && sch?.job_id) setJobId(sch.job_id)
  }, [sch?.enabled, sch?.job_id, jobId])

  return (
    <div className="max-w-[1100px] mx-auto px-6 py-6 flex flex-col gap-4 page-enter">
      <div>
        <h1 className="text-[26px] font-bold font-display text-text-strong leading-tight">Live Pipeline</h1>
        <p className="text-xs text-text-muted font-sans mt-1">Production Bullhorn ingest — auto-polls EDU placements and runs the full credentialing pipeline.</p>
      </div>

      <BullhornStatusCard />
      <SchedulerPanel onAttach={setJobId} />

      <div className="rounded-2xl border border-brand-sky/15 bg-brand-surface p-5">
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-[13px] font-bold font-display text-text-strong">
            Live feed <span className="text-[10px] font-mono text-text-muted ml-1">{jobId ?? '—'}</span>
          </h3>
          <span className="text-[10px] font-sans px-2 py-0.5 rounded-full"
                style={{ color: status === 'running' ? '#1DAEEF' : 'var(--text-muted)', background: 'rgba(29,174,239,0.1)' }}>
            {status}
          </span>
        </div>
        {/* TerminalLog props are { lines, collapsed, onToggle } — verified against LiveStream.jsx usage. */}
        <TerminalLog lines={logLines} collapsed={logCollapsed} onToggle={() => setLogCollapsed((c) => !c)} />
      </div>

      <ManualControls onAttach={setJobId} />
    </div>
  )
}
```

- [ ] **Step 3: Create `src/pages/WorkspacePage.jsx`**

Wraps the existing review experience with the rail + tabs. It renders the existing `ReviewPage` content as the Review tab via the `reviewSlot` prop.

```jsx
import { useParams } from 'react-router-dom'
import AssignmentRail from '../components/workspace/AssignmentRail.jsx'
import WorkspaceTabs from '../components/workspace/WorkspaceTabs.jsx'
import ReviewPage from './ReviewPage.jsx'

export default function WorkspacePage() {
  const { aid } = useParams()

  return (
    <div className="flex h-full">
      <aside className="w-[280px] shrink-0 border-r border-brand-sky/12 bg-brand-bg-2/40 hidden md:block">
        <AssignmentRail />
      </aside>
      <div className="flex-1 overflow-y-auto">
        {!aid ? (
          <div className="flex items-center justify-center h-full text-sm text-text-muted font-sans px-6 text-center">
            Select an assignment from the list to open its workspace.
          </div>
        ) : (
          <div className="max-w-[1100px] mx-auto px-6 py-6 page-enter">
            <WorkspaceTabs aid={aid} reviewSlot={<ReviewPage />} />
          </div>
        )}
      </div>
    </div>
  )
}
```

- [ ] **Step 4: Wire routes in `src/App.jsx`**

Add imports:
```js
import LiveFeedPage from './pages/LiveFeedPage.jsx'
import WorkspacePage from './pages/WorkspacePage.jsx'
```
Replace the review route and add the live route. Change:
```js
      { path: 'review/:aid',   element: <ReviewPage /> },
```
to:
```js
      { path: 'live',          element: <LiveFeedPage /> },
      { path: 'review/:aid',   element: <WorkspacePage /> },
```
(`ReviewPage` is still imported and now rendered inside `WorkspacePage` as the Review tab. Leave its existing import in place.)

- [ ] **Step 5: Add the Live title in `src/components/shell/AppShell.jsx`**

In the `PAGE_TITLES` map add:
```js
  '/live':        'Live Pipeline',
```

- [ ] **Step 6: Verify build + tests + lint**

Run: `npm test && npm run build && npm run lint`
Expected: all tests pass; build succeeds; no new lint errors.

- [ ] **Step 7: Manual verification (dev server)**

Run: `npm run dev`. Confirm:
- Top bar shows Test/Live switch; Live dot reflects Bullhorn status.
- Test mode: Dashboard/Run/Assignments nav; opening an assignment shows the rail + workspace tabs (Review, Intake…Email, Preview, Audit).
- Audit tab loads timeline from backend.
- Live mode: navigates to `/live`; Bullhorn card, scheduler panel (countdown ring), manual controls, and live feed render.
Expected: all panels render; mode switch swaps backend (network tab shows pipeline base for live calls).

- [ ] **Step 8: Commit**

```bash
git add src/components/live/ManualControls.jsx src/pages/LiveFeedPage.jsx src/pages/WorkspacePage.jsx src/App.jsx src/components/shell/AppShell.jsx
git commit -m "feat: live feed page + workspace page + routing"
```

---

## Notes / Out of scope (YAGNI)

- **Per-agent inline override editors** (the demo's `renderScalarAgent`/`renderAgent5`/`renderAgent55`) are NOT rebuilt. Overrides continue through the existing `FixAgentPanel` + `CorrectItemPanel` surfaced in the Review tab. Agent tabs ②–⑥ are the existing read-only drilldown views.
- **Pipeline port:** `PIPELINE_API_BASE` defaults to `:5003` in `config.js` as a placeholder. Replace with the real port (or set `VITE_PIPELINE_API_BASE` in `.env.local`) when known — no code change required elsewhere.
- Live mode degrades gracefully: `useBullhornStatus`/`useScheduler` use `retry: 0`; cards show NOT CONNECTED / STOPPED states on failure rather than crashing.

# Cockpit in the Assignments Tab — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replicate the `:8001/ui` cockpit (live list + Step Run / Batch / Mail / Excel) inside the React app's Assignments tab in **test mode only**, styled with the existing ACAP design system, with all data from live API calls.

**Architecture:** `AssignmentsPage` becomes a mode router — live mode renders the existing list (extracted to `AssignmentsList`), test mode renders a new two-pane `CockpitView` (left = `/bullhorn_assignments`, right = sub-tabs). Logic lives in pure helpers (`lib/cockpit.js`) and hooks (`api/*`, `hooks/useStepRun.js`); components are thin and reuse `review/`, `run/`, and `common/` pieces.

**Tech Stack:** React 19, react-router 7, @tanstack/react-query v5, Vitest 2 + @testing-library/react 16 (jsdom), Tailwind v4, `useTokens()` theme.

**Spec:** `docs/superpowers/specs/2026-06-15-cockpit-assignments-tab-design.md`

**Conventions (read before starting):**
- API calls go through `apiClient.get/post/del` (`src/lib/apiClient.js`); base URL is mode-aware (set by `ConsoleModeProvider`).
- React Query keys MUST be built with `mk(...)` (`src/console/modeKey.js`) so test/live caches never collide.
- Tests live in a `__tests__` folder next to the code; run with `npm test` (`vitest run`) or a single file with `npx vitest run <path>`.
- Styling: call `const t = useTokens()` and use inline `style={{…}}` with `t.*` tokens, mirroring existing components (see `src/components/review/DocumentViewer.jsx`).

---

## File Structure

**Create:**
- `src/api/stepRun.js` — start/status/approve/abort hooks for the stepped run.
- `src/api/credentialers.js` — `useCredentialers()`.
- `src/lib/cockpit.js` — pure helpers + constants (state derivation, pipeline nodes, excel row merge, pagination, gate key, approve payload, localStorage step-job).
- `src/lib/__tests__/cockpit.test.js` — unit tests for the above.
- `src/hooks/useStepRun.js` — orchestrates status polling + SSE for a step job.
- `src/hooks/__tests__/useStepRun.test.js`
- `src/components/assignments/AssignmentsList.jsx` — current Assignments page body, extracted unchanged.
- `src/components/cockpit/AssignmentRail.jsx`
- `src/components/cockpit/PipelineTracker.jsx`
- `src/components/cockpit/OigBanner.jsx`
- `src/components/cockpit/AgentOutputView.jsx`
- `src/components/cockpit/VerifierView.jsx`
- `src/components/cockpit/GatePanel.jsx`
- `src/components/cockpit/StepRunPanel.jsx`
- `src/components/cockpit/BatchPanel.jsx`
- `src/components/cockpit/PendingEmailPreview.jsx`
- `src/components/cockpit/MailPanel.jsx`
- `src/components/cockpit/ExcelGrid.jsx`
- `src/components/cockpit/DocumentDrawer.jsx`
- `src/components/cockpit/CockpitTabs.jsx`
- `src/components/cockpit/CockpitView.jsx`
- `src/components/cockpit/__tests__/*.test.jsx` — render/interaction tests as noted per task.

**Modify:**
- `src/lib/sse.js` — add step-run event names.
- `src/api/bullhorn.js` — add `useBullhornAssignments()`.
- `src/api/email.js` — add `usePendingEmails()` + `usePendingEmail(aid)`.
- `src/pages/AssignmentsPage.jsx` — replace body with the mode router.

---

## Phase 0 — API & SSE foundation

### Task 1: Add step-run events to the SSE event list

**Files:**
- Modify: `src/lib/sse.js`
- Test: `src/lib/__tests__/sse.test.js`

- [ ] **Step 1: Write the failing test** (append to existing file inside a new `describe`)

```js
describe('openSSE registers step-run events', () => {
  it('adds listeners for step_paused, step_resumed, assignment_aborted, stream_idle', () => {
    const listened = []
    globalThis.EventSource = vi.fn(function () {
      this.addEventListener = vi.fn((evt) => listened.push(evt))
      this.close = vi.fn()
    })
    const close = openSSE('job1', {}, () => {})
    for (const evt of ['step_paused', 'step_resumed', 'assignment_aborted', 'stream_idle']) {
      expect(listened).toContain(evt)
    }
    close()
    delete globalThis.EventSource
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/lib/__tests__/sse.test.js`
Expected: FAIL — `step_paused` etc. not in `listened`.

- [ ] **Step 3: Implement** — in `src/lib/sse.js`, extend the `EVENTS` array:

```js
  const EVENTS = [
    'backup','wiped','batch_start','assignment_start',
    'agent_1_complete','agent_2_complete','agent_3_complete','agent_4_complete',
    'agent_5_complete','agent_5_5_complete','agent_6_complete',
    'assignment_complete','log','assignment_done','assignment_failed',
    'job_complete','job_failed',
    // step-run gate events
    'step_paused','step_resumed','assignment_aborted','stream_idle',
  ]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/lib/__tests__/sse.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/lib/sse.js src/lib/__tests__/sse.test.js
git commit -m "feat(sse): register step-run gate events"
```

---

### Task 2: `useBullhornAssignments` hook

**Files:**
- Modify: `src/api/bullhorn.js`

- [ ] **Step 1: Implement** (no unit test — thin react-query wrapper, covered by component tests later)

Append to `src/api/bullhorn.js`:

```js
/** GET /bullhorn_assignments — all alive EDU placements (cockpit left rail). */
export function useBullhornAssignments() {
  return useQuery({
    queryKey: mk('bullhorn_assignments'),
    queryFn: () => apiClient.get('/bullhorn_assignments'),
    staleTime: 60_000,
  })
}
```

(`useQuery`, `apiClient`, `mk` are already imported at the top of the file.)

- [ ] **Step 2: Sanity check it compiles**

Run: `npx vitest run src/lib/__tests__/smoke.test.js`
Expected: PASS (no import errors).

- [ ] **Step 3: Commit**

```bash
git add src/api/bullhorn.js
git commit -m "feat(api): useBullhornAssignments"
```

---

### Task 3: Pending-email hooks

**Files:**
- Modify: `src/api/email.js`

- [ ] **Step 1: Implement** — append to `src/api/email.js`:

```js
/** GET /pending_emails — held emails awaiting release (Mail tab list). */
export function usePendingEmails() {
  return useQuery({
    queryKey: mk('pending_emails'),
    queryFn: () => apiClient.get('/pending_emails'),
    staleTime: 15_000,
  })
}

/** GET /pending_email/<aid> — a single held email with attachments + forms manifest. */
export function usePendingEmail(aid) {
  return useQuery({
    queryKey: mk('pending_email', aid),
    queryFn: () => apiClient.get(`/pending_email/${aid}`),
    enabled: !!aid,
    staleTime: 15_000,
  })
}
```

- [ ] **Step 2: Sanity check**

Run: `npx vitest run src/lib/__tests__/smoke.test.js`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add src/api/email.js
git commit -m "feat(api): pending-email hooks for Mail tab"
```

---

### Task 4: `useCredentialers` hook

**Files:**
- Create: `src/api/credentialers.js`

- [ ] **Step 1: Implement**

```js
import { useQuery } from '@tanstack/react-query'
import { apiClient } from '../lib/apiClient.js'
import { mk } from '../console/modeKey.js'

/** GET /credentialers — roster for the Agent 3 reassign dropdown. */
export function useCredentialers() {
  return useQuery({
    queryKey: mk('credentialers'),
    queryFn: () => apiClient.get('/credentialers'),
    staleTime: 300_000,
  })
}
```

- [ ] **Step 2: Sanity check**

Run: `npx vitest run src/lib/__tests__/smoke.test.js`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add src/api/credentialers.js
git commit -m "feat(api): useCredentialers"
```

---

### Task 5: Step-run hooks (start / status / approve / abort)

**Files:**
- Create: `src/api/stepRun.js`

- [ ] **Step 1: Implement**

```js
import { useQuery, useMutation } from '@tanstack/react-query'
import { apiClient } from '../lib/apiClient.js'
import { mk } from '../console/modeKey.js'

const TERMINAL = new Set(['complete', 'aborted', 'failed'])

/** POST /step_run/<aid> -> { job_id }. Call mutate(aid). */
export function useStartStepRun() {
  return useMutation({
    mutationFn: (aid) => apiClient.post(`/step_run/${aid}`, {}),
  })
}

/** GET /step_run/<job>/status — polls every 2.5s until terminal. */
export function useStepStatus(jobId) {
  return useQuery({
    queryKey: mk('step_status', jobId),
    queryFn: () => apiClient.get(`/step_run/${jobId}/status`),
    enabled: !!jobId,
    refetchInterval: (query) =>
      TERMINAL.has(query.state.data?.status) ? false : 2500,
  })
}

/** POST /step_run/<job>/approve  body: { by, overrides? } */
export function useApproveStep(jobId) {
  return useMutation({
    mutationFn: (body) => apiClient.post(`/step_run/${jobId}/approve`, body),
  })
}

/** POST /step_run/<job>/abort  body: { by } */
export function useAbortStep(jobId) {
  return useMutation({
    mutationFn: (body) => apiClient.post(`/step_run/${jobId}/abort`, body),
  })
}
```

- [ ] **Step 2: Sanity check**

Run: `npx vitest run src/lib/__tests__/smoke.test.js`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add src/api/stepRun.js
git commit -m "feat(api): step-run start/status/approve/abort hooks"
```

---

## Phase 1 — Pure logic (`lib/cockpit.js`)

### Task 6: Cockpit helpers + constants

**Files:**
- Create: `src/lib/cockpit.js`
- Test: `src/lib/__tests__/cockpit.test.js`

- [ ] **Step 1: Write the failing tests**

```js
import { describe, it, expect } from 'vitest'
import {
  assignmentState, pipelineNodes, mergeExcelRow, paginate,
  gateKey, approvePayload, COCKPIT_AGENTS,
} from '../cockpit.js'

describe('assignmentState', () => {
  it('prefers explicit state', () => {
    expect(assignmentState({ state: 'partial' })).toBe('partial')
  })
  it('falls back to processed flag', () => {
    expect(assignmentState({ processed: true })).toBe('done')
    expect(assignmentState({ processed: false })).toBe('new')
    expect(assignmentState({})).toBe('new')
  })
})

describe('pipelineNodes', () => {
  it('marks done, wait, and idle correctly', () => {
    const nodes = pipelineNodes(
      [{ agent: '1' }, { agent: '2' }],
      { agent: '3' },
      false,
    )
    const byId = Object.fromEntries(nodes.map(n => [n.id, n.state]))
    expect(byId['1']).toBe('done')
    expect(byId['2']).toBe('done')
    expect(byId['3']).toBe('wait')
    expect(byId['4']).toBe('idle')
    expect(nodes).toHaveLength(COCKPIT_AGENTS.length)
  })
  it('marks the next node running when no gate and not paused', () => {
    const nodes = pipelineNodes([{ agent: '1' }], null, true)
    const byId = Object.fromEntries(nodes.map(n => [n.id, n.state]))
    expect(byId['2']).toBe('run')
  })
})

describe('mergeExcelRow', () => {
  it('combines bullhorn core + review enrichment', () => {
    const row = mergeExcelRow(
      { assignment_id: 7, candidate: 'Jane', school: 'PS 1', status: 'Booked', cost_usd: 0.12, state: 'done' },
      { hitl_tier: 'GREEN', ready: true, counts: { valid: 3, expired: 1, missing: 0 }, credentialer_name: 'Deb' },
    )
    expect(row).toMatchObject({
      id: 7, candidate: 'Jane', district: 'PS 1', bullhorn_status: 'Booked',
      run_state: 'done', tier: 'GREEN', ready: true,
      valid: 3, expired: 1, missing: 0, credentialer: 'Deb', cost: 0.12,
    })
  })
  it('tolerates missing review (enrichment null)', () => {
    const row = mergeExcelRow({ assignment_id: 7, candidate: 'Jane' }, null)
    expect(row.id).toBe(7)
    expect(row.tier).toBeNull()
    expect(row.ready).toBeNull()
  })
})

describe('paginate', () => {
  it('slices the requested page and reports totals', () => {
    const items = Array.from({ length: 53 }, (_, i) => i)
    const r = paginate(items, 2, 25) // page is 1-based
    expect(r.slice).toEqual(items.slice(25, 50))
    expect(r.totalPages).toBe(3)
    expect(r.page).toBe(2)
  })
  it('clamps page into range', () => {
    expect(paginate([1, 2, 3], 99, 25).page).toBe(1)
    expect(paginate([], 1, 25).totalPages).toBe(1)
  })
})

describe('gateKey', () => {
  it('keys a paused gate by agent', () => {
    expect(gateKey({ status: 'paused', awaiting: { agent: '5' } })).toBe('paused:5')
  })
  it('keys non-paused by status', () => {
    expect(gateKey({ status: 'running' })).toBe('running')
    expect(gateKey(null)).toBe('idle')
  })
})

describe('approvePayload', () => {
  it('includes overrides only when present', () => {
    expect(approvePayload('me@x.com', {})).toEqual({ by: 'me@x.com' })
    expect(approvePayload('me@x.com', { TB: { status: 'MISSING' } }))
      .toEqual({ by: 'me@x.com', overrides: { TB: { status: 'MISSING' } } })
  })
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/lib/__tests__/cockpit.test.js`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `src/lib/cockpit.js`**

```js
// Pure helpers + constants for the cockpit. No React, no I/O — unit-tested.

export const COCKPIT_AGENTS = [
  ['1', 'Trigger'], ['2', 'Intake'], ['3', 'Assign'],
  ['4', 'Requirements'], ['5', 'Doc Recon'], ['5_5', 'Gate'], ['6', 'Comms'],
]

// Document statuses an Agent-5 checklist item can be overridden to.
export const CHECKLIST_STATUSES = [
  'FOUND_VALID', 'MISSING', 'FOUND_EXPIRED', 'FOUND_EXPIRES_SOON',
  'FOUND_EXPIRES_DURING', 'FOUND_WRONG_PERSON', 'UNREADABLE',
]

const TAG_META = {
  new:      { cls: 'new',  label: 'NEW' },
  partial:  { cls: 'part', label: 'IN-PROGRESS' },
  done:     { cls: 'done', label: 'DONE' },
  failed:   { cls: 'fail', label: 'FAILED' },
  aborted:  { cls: 'fail', label: 'ABORTED' },
}

/** Derive the run-state of a bullhorn assignment row. */
export function assignmentState(a) {
  return a?.state || (a?.processed ? 'done' : 'new')
}

/** Tag metadata ({ cls, label }) for a run-state. */
export function stateTag(state) {
  return TAG_META[state] || TAG_META.new
}

/**
 * Build the 7 pipeline nodes with display state.
 * @param {{agent:string}[]} steps completed steps
 * @param {{agent:string}|null} awaiting gate currently paused on
 * @param {boolean} running whether the job is actively running
 * @returns {{id:string,label:string,state:'done'|'wait'|'run'|'idle'}[]}
 */
export function pipelineNodes(steps = [], awaiting = null, running = false) {
  const done = new Set((steps || []).map(s => s.agent))
  return COCKPIT_AGENTS.map(([id, label], i) => {
    let state = 'idle'
    if (done.has(id)) state = 'done'
    else if (awaiting && awaiting.agent === id) state = 'wait'
    else if (running && !awaiting && done.size === i) state = 'run'
    return { id, label, state }
  })
}

/** Merge one bullhorn row + its (optional) /review payload into an Excel row. */
export function mergeExcelRow(bh, review) {
  const counts = review?.counts || {}
  return {
    id: bh?.assignment_id ?? null,
    candidate: bh?.candidate ?? null,
    district: bh?.school ?? null,
    bullhorn_status: bh?.status ?? null,
    run_state: assignmentState(bh),
    cost: bh?.cost_usd ?? review?.cost?.total_usd ?? null,
    tier: review?.hitl_tier ?? null,
    ready: review?.ready ?? null,
    valid: counts.valid ?? null,
    expired: counts.expired ?? null,
    missing: counts.missing ?? null,
    credentialer: review?.credentialer_name ?? null,
    license: review?.license_cert ?? null,
  }
}

/** 1-based pagination. Returns { slice, page, totalPages, pageSize }. */
export function paginate(items = [], page = 1, pageSize = 25) {
  const total = items.length
  const totalPages = Math.max(1, Math.ceil(total / pageSize))
  const clamped = Math.min(Math.max(1, page), totalPages)
  const start = (clamped - 1) * pageSize
  return { slice: items.slice(start, start + pageSize), page: clamped, totalPages, pageSize }
}

/** Stable key for a status snapshot so the gate only re-renders when it changes. */
export function gateKey(status) {
  if (!status) return 'idle'
  if (status.status === 'paused' && status.awaiting) return `paused:${status.awaiting.agent}`
  return status.status
}

/** Build the /approve body, omitting an empty overrides object. */
export function approvePayload(by, overrides) {
  const body = { by }
  if (overrides && Object.keys(overrides).length) body.overrides = overrides
  return body
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `npx vitest run src/lib/__tests__/cockpit.test.js`
Expected: PASS (all cases).

- [ ] **Step 5: Commit**

```bash
git add src/lib/cockpit.js src/lib/__tests__/cockpit.test.js
git commit -m "feat(cockpit): pure helpers (state, pipeline, excel, pagination, gate)"
```

---

### Task 7: Step-job localStorage helpers

**Files:**
- Modify: `src/lib/cockpit.js`
- Modify: `src/lib/__tests__/cockpit.test.js`

- [ ] **Step 1: Write the failing test** (append)

```js
import { readStepJob, writeStepJob, clearStepJob } from '../cockpit.js'

describe('step-job persistence', () => {
  beforeEach(() => localStorage.clear())
  it('round-trips a job', () => {
    expect(readStepJob()).toBeNull()
    writeStepJob({ job: 'j1', aid: 42 })
    expect(readStepJob()).toEqual({ job: 'j1', aid: 42 })
    clearStepJob()
    expect(readStepJob()).toBeNull()
  })
  it('returns null on corrupt data', () => {
    localStorage.setItem('cockpit.stepJob', '{not json')
    expect(readStepJob()).toBeNull()
  })
})
```

Add `beforeEach` to the vitest import at the top of the test file if not already imported:
`import { describe, it, expect, beforeEach } from 'vitest'`

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/lib/__tests__/cockpit.test.js`
Expected: FAIL — exports not found.

- [ ] **Step 3: Implement** (append to `src/lib/cockpit.js`)

```js
const STEP_JOB_KEY = 'cockpit.stepJob'

export function readStepJob() {
  try {
    const raw = localStorage.getItem(STEP_JOB_KEY)
    return raw ? JSON.parse(raw) : null
  } catch {
    return null
  }
}
export function writeStepJob(obj) {
  try { localStorage.setItem(STEP_JOB_KEY, JSON.stringify(obj)) } catch {}
}
export function clearStepJob() {
  try { localStorage.removeItem(STEP_JOB_KEY) } catch {}
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `npx vitest run src/lib/__tests__/cockpit.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/lib/cockpit.js src/lib/__tests__/cockpit.test.js
git commit -m "feat(cockpit): localStorage step-job resume helpers"
```

---

## Phase 2 — `useStepRun` orchestration hook

### Task 8: `useStepRun` — combine status poll + SSE log stream

**Files:**
- Create: `src/hooks/useStepRun.js`
- Test: `src/hooks/__tests__/useStepRun.test.js`

This hook owns: starting a run, exposing live `status`/`logLines`, approve/abort, and resume. It wraps the Phase-0 hooks so components stay thin.

- [ ] **Step 1: Write the failing test**

```jsx
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { renderHook, act, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { useStepRun } from '../useStepRun.js'

// Mock the SSE layer so no real EventSource is needed.
vi.mock('../../lib/sse.js', () => ({
  openSSE: vi.fn(() => () => {}),
}))
// Mock the API client.
vi.mock('../../lib/apiClient.js', () => ({
  apiClient: {
    get: vi.fn(),
    post: vi.fn(),
  },
}))
import { apiClient } from '../../lib/apiClient.js'

function wrapper({ children }) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return <QueryClientProvider client={qc}>{children}</QueryClientProvider>
}

beforeEach(() => {
  localStorage.clear()
  apiClient.get.mockReset()
  apiClient.post.mockReset()
})
afterEach(() => vi.clearAllTimers())

describe('useStepRun', () => {
  it('starts a run and exposes the job id', async () => {
    apiClient.post.mockResolvedValueOnce({ job_id: 'job9' })
    apiClient.get.mockResolvedValue({ status: 'running', steps: [], awaiting: null })
    const { result } = renderHook(() => useStepRun(), { wrapper })

    await act(async () => { await result.current.start(42) })

    expect(apiClient.post).toHaveBeenCalledWith('/step_run/42', {})
    await waitFor(() => expect(result.current.jobId).toBe('job9'))
  })

  it('appends log lines pushed through the SSE handlers', async () => {
    const { openSSE } = await import('../../lib/sse.js')
    apiClient.post.mockResolvedValueOnce({ job_id: 'jobL' })
    apiClient.get.mockResolvedValue({ status: 'running', steps: [], awaiting: null })
    const { result } = renderHook(() => useStepRun(), { wrapper })
    await act(async () => { await result.current.start(1) })

    // grab the handlers passed to openSSE and fire a log event
    const handlers = openSSE.mock.calls.at(-1)[1]
    act(() => handlers.log({ line: 'hello' }))
    expect(result.current.logLines).toContain('hello')
  })
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `npx vitest run src/hooks/__tests__/useStepRun.test.js`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `src/hooks/useStepRun.js`**

```js
import { useState, useRef, useCallback, useEffect } from 'react'
import { openSSE } from '../lib/sse.js'
import {
  useStartStepRun, useStepStatus, useApproveStep, useAbortStep,
} from '../api/stepRun.js'
import { approvePayload, writeStepJob, clearStepJob, readStepJob } from '../lib/cockpit.js'

const MAX_LOG = 600

export function useStepRun() {
  const [jobId, setJobId] = useState(null)
  const [aid, setAid] = useState(null)
  const [logLines, setLogLines] = useState([])
  const closeRef = useRef(null)

  const startMut = useStartStepRun()
  const status = useStepStatus(jobId)
  const approveMut = useApproveStep(jobId)
  const abortMut = useAbortStep(jobId)

  const pushLog = useCallback((line) => {
    setLogLines(p => {
      const next = [...p, line]
      return next.length > MAX_LOG ? next.slice(-MAX_LOG) : next
    })
  }, [])

  const connect = useCallback((id) => {
    if (closeRef.current) closeRef.current()
    const handlers = {
      log: (d) => pushLog(d.line ?? String(d)),
      '*': (type) => { if (type !== 'log') pushLog(`━━ ${type.replace(/_/g, ' ').toUpperCase()}`) },
    }
    closeRef.current = openSSE(id, handlers, () => {})
  }, [pushLog])

  const start = useCallback(async (assignmentId) => {
    setLogLines([])
    const res = await startMut.mutateAsync(assignmentId)
    if (res?.job_id) {
      setJobId(res.job_id)
      setAid(assignmentId)
      writeStepJob({ job: res.job_id, aid: assignmentId })
      connect(res.job_id)
    }
    return res
  }, [startMut, connect])

  const resume = useCallback((saved) => {
    setJobId(saved.job)
    setAid(saved.aid)
    connect(saved.job)
  }, [connect])

  const approve = useCallback(async (by, overrides) => {
    await approveMut.mutateAsync(approvePayload(by, overrides))
  }, [approveMut])

  const abort = useCallback(async (by) => {
    await abortMut.mutateAsync({ by: by || 'cockpit_ui' })
  }, [abortMut])

  // Clear persisted job + close stream on terminal states.
  useEffect(() => {
    const s = status.data?.status
    if (s === 'complete' || s === 'aborted' || s === 'failed') {
      clearStepJob()
      if (closeRef.current) { closeRef.current(); closeRef.current = null }
    }
  }, [status.data?.status])

  useEffect(() => () => { if (closeRef.current) closeRef.current() }, [])

  return {
    jobId, aid, start, resume, approve, abort,
    logLines,
    status: status.data,
    isStarting: startMut.isPending,
    savedJob: readStepJob(),
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `npx vitest run src/hooks/__tests__/useStepRun.test.js`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/hooks/useStepRun.js src/hooks/__tests__/useStepRun.test.js
git commit -m "feat(cockpit): useStepRun orchestration hook"
```

---

## Phase 3 — Leaf components

> For every component task: render tests use `@testing-library/react`. Components that call `useTokens()` must be wrapped in the app's `ThemeProvider`. Create one shared test helper first.

### Task 9: Test render helper

**Files:**
- Create: `src/test-utils/render.jsx`

- [ ] **Step 1: Implement** (inspect `src/lib/theme.jsx` for the actual provider export name; it exposes `ThemeProvider` and `useTokens`)

```jsx
import { render } from '@testing-library/react'
import { QueryClientProvider, QueryClient } from '@tanstack/react-query'
import { ThemeProvider } from '../lib/theme.jsx'

export function renderWithProviders(ui) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <ThemeProvider>{ui}</ThemeProvider>
    </QueryClientProvider>,
  )
}
```

> **NOTE for implementer:** open `src/lib/theme.jsx` and confirm the provider is exported as `ThemeProvider`. If it is named differently (e.g. `Theme`), use that name. If `useTokens` works without a provider (reads a default), you may drop the `ThemeProvider` wrapper.

- [ ] **Step 2: Commit**

```bash
git add src/test-utils/render.jsx
git commit -m "test: shared renderWithProviders helper"
```

---

### Task 10: `PipelineTracker`

**Files:**
- Create: `src/components/cockpit/PipelineTracker.jsx`
- Test: `src/components/cockpit/__tests__/PipelineTracker.test.jsx`

- [ ] **Step 1: Write the failing test**

```jsx
import { describe, it, expect } from 'vitest'
import { screen } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'
import PipelineTracker from '../PipelineTracker.jsx'

describe('PipelineTracker', () => {
  it('renders all 7 agent labels and a check on completed nodes', () => {
    renderWithProviders(
      <PipelineTracker steps={[{ agent: '1' }]} awaiting={{ agent: '2' }} running />,
    )
    expect(screen.getByText('Trigger')).toBeInTheDocument()
    expect(screen.getByText('Comms')).toBeInTheDocument()
    // completed node shows a check glyph
    expect(screen.getAllByText('✓').length).toBeGreaterThanOrEqual(1)
  })
})
```

- [ ] **Step 2: Run to verify it fails** — `npx vitest run src/components/cockpit/__tests__/PipelineTracker.test.jsx` → FAIL (no module).

- [ ] **Step 3: Implement**

```jsx
import { useTokens } from '../../lib/theme.jsx'
import { pipelineNodes } from '../../lib/cockpit.js'

const COLORS = {
  done: '#1F8A4C', wait: '#C9871A', run: '#1DAEEF', idle: null,
}

export default function PipelineTracker({ steps, awaiting, running }) {
  const t = useTokens()
  const nodes = pipelineNodes(steps, awaiting, running)
  return (
    <div className="flex items-center gap-0 my-3">
      {nodes.map((n, i) => {
        const c = COLORS[n.state] || t.muted
        return (
          <div key={n.id} className="flex-1 text-center relative">
            <div className="mx-auto flex items-center justify-center rounded-full font-bold"
              style={{
                width: 42, height: 42, fontSize: 12,
                border: `2px solid ${n.state === 'idle' ? t.cardBorder : c}`,
                color: n.state === 'idle' ? t.muted : c,
                background: t.cardBg,
                boxShadow: n.state === 'wait' || n.state === 'run' ? `0 0 14px ${c}55` : 'none',
              }}>
              {n.state === 'done' ? '✓' : n.id.replace('_', '.')}
            </div>
            <div className="text-[9px] uppercase tracking-wider mt-1.5"
              style={{ color: t.muted, fontFamily: 'Geist,sans-serif' }}>{n.label}</div>
            {i < nodes.length - 1 && (
              <div className="absolute top-[20px] right-[-50%] h-0.5 w-full"
                style={{ background: n.state === 'done' ? COLORS.done : t.cardBorder }} />
            )}
          </div>
        )
      })}
    </div>
  )
}
```

- [ ] **Step 4: Run to verify it passes** — same command → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/PipelineTracker.jsx src/components/cockpit/__tests__/PipelineTracker.test.jsx
git commit -m "feat(cockpit): PipelineTracker"
```

---

### Task 11: `OigBanner`

**Files:**
- Create: `src/components/cockpit/OigBanner.jsx`
- Test: `src/components/cockpit/__tests__/OigBanner.test.jsx`

- [ ] **Step 1: Write the failing test**

```jsx
import { describe, it, expect } from 'vitest'
import { screen } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'
import OigBanner from '../OigBanner.jsx'

describe('OigBanner', () => {
  it('renders nothing without a screen', () => {
    const { container } = renderWithProviders(<OigBanner oig={null} />)
    expect(container).toBeEmptyDOMElement()
  })
  it('shows a loud warning on CONFIRMED', () => {
    renderWithProviders(<OigBanner oig={{ status: 'CONFIRMED' }} />)
    expect(screen.getByText(/OIG EXCLUSION MATCH/i)).toBeInTheDocument()
  })
  it('shows clear state', () => {
    renderWithProviders(<OigBanner oig={{ status: 'CLEAR' }} />)
    expect(screen.getByText(/CLEAR/i)).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run to verify it fails** → FAIL.

- [ ] **Step 3: Implement**

```jsx
const STYLES = {
  CONFIRMED: { bg: 'rgba(192,57,43,0.14)', border: '#C0392B', color: '#C0392B',
    title: '🛑 OIG EXCLUSION MATCH — DO NOT PLACE',
    sub: 'name AND date-of-birth match a federally-excluded individual — review immediately' },
  POSSIBLE: { bg: 'rgba(201,135,26,0.13)', border: '#C9871A', color: '#C9871A',
    title: '⚠ OIG: possible match — verify DOB', sub: '' },
  UNAVAILABLE: { bg: 'rgba(107,114,128,0.12)', border: '#6B7280', color: '#6B7280',
    title: 'OIG list unavailable — candidate not screened', sub: '' },
  CLEAR: { bg: 'rgba(31,138,76,0.12)', border: '#1F8A4C', color: '#1F8A4C',
    title: '🛡 OIG: CLEAR', sub: 'screened against the federal exclusion list — no match' },
}

export default function OigBanner({ oig }) {
  if (!oig || !oig.status) return null
  const s = STYLES[oig.status] || STYLES.CLEAR
  return (
    <div className="rounded-xl px-4 py-2.5 my-2.5 font-bold flex items-center gap-2.5 text-sm"
      style={{ background: s.bg, border: `1px solid ${s.border}`, color: s.color, fontFamily: 'Geist,sans-serif' }}>
      <span>{s.title}</span>
      {(oig.reason || s.sub) && (
        <small className="font-normal opacity-80">{oig.reason || s.sub}</small>
      )}
    </div>
  )
}
```

- [ ] **Step 4: Run to verify it passes** → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/OigBanner.jsx src/components/cockpit/__tests__/OigBanner.test.jsx
git commit -m "feat(cockpit): OigBanner"
```

---

### Task 12: `AgentOutputView` + `VerifierView`

**Files:**
- Create: `src/components/cockpit/AgentOutputView.jsx`
- Create: `src/components/cockpit/VerifierView.jsx`
- Test: `src/components/cockpit/__tests__/VerifierView.test.jsx`

- [ ] **Step 1: Write the failing test** (covers VerifierView; AgentOutputView is simple presentational)

```jsx
import { describe, it, expect } from 'vitest'
import { screen } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'
import VerifierView from '../VerifierView.jsx'

describe('VerifierView', () => {
  it('renders verdict and per-check reasons', () => {
    renderWithProviders(<VerifierView verifier={{
      verdict: 'WARN',
      checks: [
        { name: 'oig_exclusion_screen', status: 'PASS', reason: 'no match' },
        { name: 'all_missing_canary', status: 'WARN', reason: '17/17 missing' },
      ],
    }} />)
    expect(screen.getByText('WARN')).toBeInTheDocument()
    expect(screen.getByText('17/17 missing')).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run to verify it fails** → FAIL.

- [ ] **Step 3: Implement `AgentOutputView.jsx`**

```jsx
import { useTokens } from '../../lib/theme.jsx'

const BIG = new Set(['gap_list', 'triage', 'requirements', 'extractions'])
const nice = (k) => String(k).replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())

function fmt(v) {
  if (v === null || v === undefined || v === '') return '—'
  if (typeof v === 'boolean') return v ? '✓ yes' : '— no'
  if (Array.isArray(v)) return v.length ? `${v.length} item(s)` : '—'
  if (typeof v === 'object') return `${Object.keys(v).length} entries`
  const s = String(v)
  return s.length > 200 ? s.slice(0, 200) + '…' : s
}

export default function AgentOutputView({ output }) {
  const t = useTokens()
  if (!output || typeof output !== 'object') {
    return <div className="text-xs" style={{ color: t.muted }}>{String(output ?? '—')}</div>
  }
  const rows = Object.entries(output).filter(([k]) => !k.startsWith('_'))
  return (
    <div className="grid gap-1.5 rounded-xl p-3.5 text-xs"
      style={{ gridTemplateColumns: 'minmax(120px,36%) 1fr', background: t.inputBg, border: `1px solid ${t.cardBorder}` }}>
      {rows.map(([k, v]) => (
        <div key={k} className="contents">
          <div style={{ color: t.muted, fontFamily: 'Geist,sans-serif' }}>{nice(k)}</div>
          <div style={{ color: t.text, wordBreak: 'break-word' }}>
            {BIG.has(k) ? `${Array.isArray(v) ? v.length : Object.keys(v || {}).length} item(s)` : fmt(v)}
          </div>
        </div>
      ))}
    </div>
  )
}
```

- [ ] **Step 4: Implement `VerifierView.jsx`**

```jsx
import { useTokens } from '../../lib/theme.jsx'

const nice = (k) => String(k || 'check').replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())
const ICON = { PASS: ['✓', '#1F8A4C'], WARN: ['⚠', '#C9871A'], FAIL: ['✗', '#C0392B'] }
const VERDICT_BG = { PASS: '#1F8A4C', WARN: '#C9871A', FAIL: '#C0392B' }

export default function VerifierView({ verifier }) {
  const t = useTokens()
  if (!verifier || typeof verifier !== 'object') {
    return <div className="text-xs" style={{ color: t.muted }}>—</div>
  }
  const verdict = verifier.verdict || '?'
  const checks = verifier.checks || []
  const color = VERDICT_BG[verdict] || t.muted
  return (
    <div className="rounded-xl p-3 text-xs" style={{ background: t.inputBg, border: `1px solid ${t.cardBorder}` }}>
      <span className="inline-block px-2.5 py-0.5 rounded-full font-bold mb-2"
        style={{ background: `${color}22`, color, border: `1px solid ${color}` }}>{verdict}</span>
      {checks.map((c, i) => {
        const [glyph, gc] = ICON[c.status] || ['•', t.muted]
        return (
          <div key={i} className="flex gap-2.5 py-1.5"
            style={{ borderTop: i ? `1px solid ${t.divider}` : 'none' }}>
            <span style={{ color: gc, fontWeight: 800 }}>{glyph}</span>
            <div>
              <div style={{ color: t.text }}>{nice(c.name)}</div>
              {c.reason && <div style={{ color: t.muted }}>{c.reason}</div>}
            </div>
          </div>
        )
      })}
    </div>
  )
}
```

- [ ] **Step 5: Run to verify it passes** → PASS.

- [ ] **Step 6: Commit**

```bash
git add src/components/cockpit/AgentOutputView.jsx src/components/cockpit/VerifierView.jsx src/components/cockpit/__tests__/VerifierView.test.jsx
git commit -m "feat(cockpit): AgentOutputView + VerifierView"
```

---

### Task 13: `DocumentDrawer`

**Files:**
- Create: `src/components/cockpit/DocumentDrawer.jsx`
- Test: `src/components/cockpit/__tests__/DocumentDrawer.test.jsx`

Reuses `review/DocumentViewer.jsx`. Controlled via `{ aid, file, onClose }`; open when `file` is set.

- [ ] **Step 1: Write the failing test**

```jsx
import { describe, it, expect, vi } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'
import DocumentDrawer from '../DocumentDrawer.jsx'

describe('DocumentDrawer', () => {
  it('renders the filename and fires onClose', () => {
    const onClose = vi.fn()
    renderWithProviders(<DocumentDrawer aid="42" file="tb_test.pdf" onClose={onClose} />)
    expect(screen.getByText('tb_test.pdf')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /close/i }))
    expect(onClose).toHaveBeenCalled()
  })
})
```

- [ ] **Step 2: Run to verify it fails** → FAIL.

- [ ] **Step 3: Implement**

```jsx
import { useTokens } from '../../lib/theme.jsx'
import DocumentViewer from '../review/DocumentViewer.jsx'

export default function DocumentDrawer({ aid, file, onClose }) {
  const t = useTokens()
  const open = !!file
  return (
    <div className="fixed top-0 right-0 h-screen z-40 flex flex-col"
      style={{
        width: 'min(46vw, 720px)', minWidth: 340,
        background: t.cardBg, borderLeft: `2px solid ${t.accent}`,
        boxShadow: '-14px 0 44px rgba(0,0,0,0.35)',
        transform: open ? 'none' : 'translateX(103%)',
        transition: 'transform 0.25s ease',
      }}>
      <div className="flex items-center gap-3 px-4 py-3 text-xs"
        style={{ borderBottom: `1px solid ${t.divider}` }}>
        <span className="flex-1 font-bold truncate" style={{ color: t.accent }}>{file}</span>
        <button aria-label="close" onClick={onClose}
          className="text-lg px-1" style={{ color: t.muted, cursor: 'pointer', background: 'none', border: 'none' }}>✕</button>
      </div>
      <div className="flex-1 overflow-auto">
        {open && <DocumentViewer aid={aid} filename={file} />}
      </div>
    </div>
  )
}
```

- [ ] **Step 4: Run to verify it passes** → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/DocumentDrawer.jsx src/components/cockpit/__tests__/DocumentDrawer.test.jsx
git commit -m "feat(cockpit): DocumentDrawer (reuses DocumentViewer)"
```

---

### Task 14: `AssignmentRail`

**Files:**
- Create: `src/components/cockpit/AssignmentRail.jsx`
- Test: `src/components/cockpit/__tests__/AssignmentRail.test.jsx`

Props: `{ assignments, loading, multi, selectedId, selectedIds, onPick }`. `multi=false` → single-select; `multi=true` → toggle into a Set. Search is internal state.

- [ ] **Step 1: Write the failing test**

```jsx
import { describe, it, expect, vi } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'
import AssignmentRail from '../AssignmentRail.jsx'

const ROWS = [
  { assignment_id: 1, candidate: 'Jane Doe', school: 'PS 1', status: 'Booked', state: 'new', cost_usd: 0.1 },
  { assignment_id: 2, candidate: 'John Roe', school: 'PS 2', status: 'Booked', state: 'done', cost_usd: 0.2 },
]

describe('AssignmentRail', () => {
  it('lists candidates and fires onPick', () => {
    const onPick = vi.fn()
    renderWithProviders(<AssignmentRail assignments={ROWS} onPick={onPick} />)
    fireEvent.click(screen.getByText('Jane Doe'))
    expect(onPick).toHaveBeenCalledWith(1)
  })
  it('filters by the search box', () => {
    renderWithProviders(<AssignmentRail assignments={ROWS} onPick={() => {}} />)
    fireEvent.change(screen.getByPlaceholderText(/filter/i), { target: { value: 'roe' } })
    expect(screen.queryByText('Jane Doe')).not.toBeInTheDocument()
    expect(screen.getByText('John Roe')).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run to verify it fails** → FAIL.

- [ ] **Step 3: Implement**

```jsx
import { useState } from 'react'
import { useTokens } from '../../lib/theme.jsx'
import { assignmentState, stateTag } from '../../lib/cockpit.js'
import { formatUSD } from '../../lib/format.js'

const TAG_COLOR = {
  new: '#1DAEEF', part: '#C9871A', done: '#1F8A4C', fail: '#C0392B',
}

export default function AssignmentRail({
  assignments = [], loading = false, multi = false,
  selectedId = null, selectedIds = new Set(), onPick,
}) {
  const t = useTokens()
  const [q, setQ] = useState('')
  const rows = assignments.filter(a =>
    `${a.candidate ?? ''} ${a.school ?? ''}`.toLowerCase().includes(q.toLowerCase()))

  return (
    <div className="flex flex-col gap-2">
      <input value={q} onChange={e => setQ(e.target.value)} placeholder="filter candidates / schools…"
        className="rounded-lg px-3 py-2 text-xs"
        style={{ background: t.inputBg, border: `1px solid ${t.inputBorder}`, color: t.text, outline: 'none' }} />
      <div className="flex flex-col gap-2 overflow-y-auto" style={{ maxHeight: 'calc(100vh - 220px)' }}>
        {loading && <div className="text-xs" style={{ color: t.muted }}>loading…</div>}
        {!loading && rows.length === 0 && <div className="text-xs" style={{ color: t.muted }}>no matches</div>}
        {rows.map(a => {
          const st = assignmentState(a)
          const tag = stateTag(st)
          const tc = TAG_COLOR[tag.cls] || t.accent
          const sel = multi ? selectedIds.has(a.assignment_id) : selectedId === a.assignment_id
          return (
            <div key={a.assignment_id} onClick={() => onPick(a.assignment_id)}
              className="rounded-xl px-3 py-2.5 cursor-pointer relative transition-all"
              style={{
                background: sel ? (t.isDark ? 'rgba(29,174,239,0.08)' : 'rgba(0,82,128,0.06)') : t.cardBg,
                border: `1px solid ${sel ? t.accent : t.cardBorder}`,
              }}>
              <div className="font-bold text-[13px] truncate" style={{ color: t.textStrong, fontFamily: 'Fraunces,serif' }}>
                {a.candidate || '—'}
              </div>
              <div className="text-[11px] mt-0.5" style={{ color: t.muted, fontFamily: 'Geist,sans-serif' }}>
                #{a.assignment_id} · {a.school}{a.status ? ` · ${a.status}` : ''}
                {a.cost_usd != null ? ` · ${formatUSD(a.cost_usd)}` : ''}
              </div>
              <span className="absolute top-2 right-2.5 text-[9px] tracking-wider px-2 py-0.5 rounded-full"
                style={{ color: tc, border: `1px solid ${tc}` }}>{tag.label}</span>
            </div>
          )
        })}
      </div>
    </div>
  )
}
```

- [ ] **Step 4: Run to verify it passes** → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/AssignmentRail.jsx src/components/cockpit/__tests__/AssignmentRail.test.jsx
git commit -m "feat(cockpit): AssignmentRail (search + state tags + select)"
```

---

### Task 15: `PendingEmailPreview`

**Files:**
- Create: `src/components/cockpit/PendingEmailPreview.jsx`
- Test: `src/components/cockpit/__tests__/PendingEmailPreview.test.jsx`

Props: `{ aid }`. Uses `usePendingEmail(aid)`.

- [ ] **Step 1: Write the failing test**

```jsx
import { describe, it, expect, vi } from 'vitest'
import { screen } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'

vi.mock('../../../api/email.js', () => ({
  usePendingEmail: () => ({
    data: {
      found: true, to: 'a@x.com', cc: 'b@x.com', subject: 'Docs needed',
      html_body: '<p>hello</p>', attachments: ['forms/dd.pdf'],
      forms_manifest: [{ file: 'dd.pdf', attached: true }],
    },
    isLoading: false,
  }),
}))
import PendingEmailPreview from '../PendingEmailPreview.jsx'

describe('PendingEmailPreview', () => {
  it('renders subject, recipients and attachment chips', () => {
    renderWithProviders(<PendingEmailPreview aid="42" />)
    expect(screen.getByText('Docs needed')).toBeInTheDocument()
    expect(screen.getByText('a@x.com')).toBeInTheDocument()
    expect(screen.getByText(/dd\.pdf/)).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run to verify it fails** → FAIL.

- [ ] **Step 3: Implement**

```jsx
import { usePendingEmail } from '../../api/email.js'
import { useTokens } from '../../lib/theme.jsx'
import Spinner from '../common/Spinner.jsx'

const base = (p) => String(p || '').split(/[\\/]/).pop()

export default function PendingEmailPreview({ aid }) {
  const t = useTokens()
  const { data: m, isLoading } = usePendingEmail(aid)
  if (isLoading) return <div className="py-6 flex justify-center"><Spinner size={20} color={t.accent} /></div>
  if (!m || !m.found) {
    return <div className="text-xs mt-2" style={{ color: t.muted }}>
      📧 no held candidate email for this run (flagged runs alert the credentialer instead).
    </div>
  }
  const atts = (m.attachments || [])
  return (
    <div className="rounded-xl overflow-hidden mt-3" style={{ border: `1px solid ${t.cardBorder}` }}>
      <div className="grid gap-1.5 px-4 py-3 text-xs" style={{ gridTemplateColumns: '70px 1fr', background: t.inputBg }}>
        <span style={{ color: t.muted }}>To</span><span style={{ color: t.text }}>{m.to || '—'}</span>
        <span style={{ color: t.muted }}>Cc</span><span style={{ color: t.text }}>{m.cc || '—'}</span>
        <span style={{ color: t.muted }}>Subject</span><span style={{ color: t.text }}>{m.subject || '—'}</span>
        <span style={{ color: t.muted }}>Attach</span>
        <span>{atts.length ? atts.map((a, i) =>
          <span key={i} className="inline-block text-[11px] mr-1.5 mb-1 px-2 py-0.5 rounded-lg"
            style={{ color: t.accent, border: `1px solid ${t.accent}55` }}>📎 {base(a)}</span>) :
          <span style={{ color: t.muted }}>none</span>}</span>
      </div>
      <iframe title="held email" sandbox="" srcDoc={m.html_body || '<p>(empty body)</p>'}
        className="w-full block" style={{ height: 430, background: '#fff', border: 'none' }} />
    </div>
  )
}
```

- [ ] **Step 4: Run to verify it passes** → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/PendingEmailPreview.jsx src/components/cockpit/__tests__/PendingEmailPreview.test.jsx
git commit -m "feat(cockpit): PendingEmailPreview"
```

---

## Phase 4 — Panels

### Task 16: `GatePanel`

**Files:**
- Create: `src/components/cockpit/GatePanel.jsx`
- Test: `src/components/cockpit/__tests__/GatePanel.test.jsx`

Props: `{ aid, awaiting, by, onApprove, onAbort, onOpenDoc }`. `awaiting = { agent, name, output, verifier }`. Builds `overrides` locally; calls `onApprove(overrides)` / `onAbort()`. For agent `5`, renders `OigBanner` + reuses `review/Checklist.jsx` (read its props first) and per-row status/file override controls; for agent `3`, a credentialer reassign `<select>` from `useCredentialers()`; for agent `6`, `PendingEmailPreview`. Approve is disabled when `by` is empty AND overrides are queued.

> **NOTE for implementer:** open `src/components/review/Checklist.jsx` and `ChecklistRow.jsx` to learn the exact props (it takes the `/review` payload's `checklist` array). Reuse it for the Agent-5 evidence display; wire its "view document" affordance to `onOpenDoc(file)`. If its props don't fit cleanly, render a minimal local checklist list using `review.checklist` fields (`requirement`, `status`, `confidence`, `matched_files`, `reason`).

- [ ] **Step 1: Write the failing test**

```jsx
import { describe, it, expect, vi } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'

vi.mock('../../../api/credentialers.js', () => ({ useCredentialers: () => ({ data: { credentialers: [] } }) }))
vi.mock('../../../api/review.js', () => ({ useReview: () => ({ data: { checklist: [], oig_screen: { status: 'CLEAR' } } }) }))
import GatePanel from '../GatePanel.jsx'

describe('GatePanel', () => {
  const awaiting = { agent: '2', name: 'Intake', output: { matched_client_name: 'PS 1' }, verifier: { verdict: 'PASS', checks: [] } }

  it('shows the agent name and approve/abort', () => {
    renderWithProviders(<GatePanel aid="42" awaiting={awaiting} by="me@x.com" onApprove={() => {}} onAbort={() => {}} onOpenDoc={() => {}} />)
    expect(screen.getByText(/Intake/)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /approve/i })).toBeInTheDocument()
  })

  it('passes queued overrides to onApprove', () => {
    const onApprove = vi.fn()
    const a4 = { agent: '4', name: 'Requirements', output: {}, verifier: { verdict: 'PASS', checks: [] } }
    renderWithProviders(<GatePanel aid="42" awaiting={a4} by="me@x.com" onApprove={onApprove} onAbort={() => {}} onOpenDoc={() => {}} />)
    fireEvent.click(screen.getByRole('button', { name: /approve/i }))
    expect(onApprove).toHaveBeenCalledWith(expect.any(Object))
  })

  it('blocks approve when overrides queued but no operator email', () => {
    const onApprove = vi.fn()
    renderWithProviders(<GatePanel aid="42" awaiting={awaiting} by="" onApprove={onApprove} onAbort={() => {}} onOpenDoc={() => {}} queuedForTest={{ x: 1 }} />)
    fireEvent.click(screen.getByRole('button', { name: /approve/i }))
    expect(onApprove).not.toHaveBeenCalled()
  })
})
```

- [ ] **Step 2: Run to verify it fails** → FAIL.

- [ ] **Step 3: Implement**

```jsx
import { useState } from 'react'
import { useTokens } from '../../lib/theme.jsx'
import { useCredentialers } from '../../api/credentialers.js'
import { useReview } from '../../api/review.js'
import AgentOutputView from './AgentOutputView.jsx'
import VerifierView from './VerifierView.jsx'
import OigBanner from './OigBanner.jsx'
import PendingEmailPreview from './PendingEmailPreview.jsx'
import { CHECKLIST_STATUSES } from '../../lib/cockpit.js'

export default function GatePanel({ aid, awaiting, by, onApprove, onAbort, onOpenDoc, queuedForTest }) {
  const t = useTokens()
  const [overrides, setOverrides] = useState(queuedForTest || {})
  const ag = awaiting?.agent

  const setOv = (key, val) => setOverrides(p => ({ ...p, [key]: val }))
  const queuedCount = Object.keys(overrides).length

  function approve() {
    if (queuedCount && !by) { window.alert('Enter your email up top before approving with changes'); return }
    onApprove(overrides)
    setOverrides({})
  }

  return (
    <div>
      <div className="flex items-center gap-3 mb-3">
        <span className="px-2.5 py-0.5 rounded-full text-xs font-bold"
          style={{ background: 'rgba(201,135,26,0.13)', color: '#C9871A', border: '1px solid #C9871A' }}>⏸ GATE</span>
        <span className="font-bold text-[15px]" style={{ color: t.textStrong, fontFamily: 'Fraunces,serif' }}>
          Agent {String(ag).replace('_', '.')} — {awaiting?.name} finished. Your call.
        </span>
      </div>

      {ag === '5'
        ? <Agent5Gate aid={aid} overrides={overrides} setOv={setOv} onOpenDoc={onOpenDoc} />
        : (
          <div className="grid gap-3" style={{ gridTemplateColumns: '1fr 1fr' }}>
            <div><Label t={t}>Agent Output</Label><AgentOutputView output={awaiting?.output} /></div>
            <div><Label t={t}>Independent Verifier</Label><VerifierView verifier={awaiting?.verifier} /></div>
          </div>
        )}

      {ag === '3' && <Agent3Reassign setOv={setOv} t={t} />}
      {ag === '6' && <PendingEmailPreview aid={aid} />}

      {queuedCount > 0 && (
        <div className="mt-3 rounded-xl px-3 py-2 text-xs"
          style={{ border: '1px dashed #C9871A', color: '#C9871A' }}>
          ⚡ {queuedCount} fix(es) queued — applied on approve
          <button className="underline ml-2" style={{ background: 'none', border: 'none', color: '#C9871A', cursor: 'pointer' }}
            onClick={() => setOverrides({})}>clear</button>
        </div>
      )}

      <div className="flex gap-2.5 mt-4">
        <button onClick={approve} className="px-4 py-2 rounded-xl font-bold text-sm"
          style={{ background: '#1F8A4C', color: '#fff', border: 'none', cursor: 'pointer' }}>✓ Approve → Next agent</button>
        <button onClick={() => onAbort()} className="px-4 py-2 rounded-xl font-bold text-sm"
          style={{ background: 'transparent', color: '#C0392B', border: '1px solid #C0392B', cursor: 'pointer' }}>🛑 Abort</button>
      </div>
    </div>
  )
}

function Label({ children, t }) {
  return <div className="text-[10px] font-bold tracking-widest uppercase mb-2"
    style={{ color: t.sectionLabel, fontFamily: 'Geist,sans-serif' }}>{children}</div>
}

function Agent3Reassign({ setOv, t }) {
  const { data } = useCredentialers()
  const roster = data?.credentialers || []
  return (
    <div className="flex items-center gap-2.5 mt-3 text-xs" style={{ color: t.muted }}>
      <span>Reassign credentialer:</span>
      <select onChange={e => {
        if (!e.target.value) return
        const c = JSON.parse(e.target.value)
        setOv('credentialer_name', c.name); setOv('credentialer_email', c.email)
      }} style={{ background: t.inputBg, border: `1px solid ${t.inputBorder}`, color: t.text, borderRadius: 8, padding: '6px 10px' }}>
        <option value="">— keep AI's choice —</option>
        {roster.map((c, i) => <option key={i} value={JSON.stringify(c)}>{c.name} — {c.email} (load {c.workload})</option>)}
      </select>
    </div>
  )
}

function Agent5Gate({ aid, overrides, setOv, onOpenDoc }) {
  const t = useTokens()
  const { data: rev } = useReview(aid)
  const checklist = rev?.checklist || []
  return (
    <div>
      <OigBanner oig={rev?.oig_screen} />
      <Label t={t}>Checklist — see the evidence</Label>
      {checklist.map((c, i) => {
        const files = c.matched_files || (c.matched_file ? [c.matched_file] : [])
        return (
          <div key={i} className="rounded-xl mb-2 p-3" style={{ border: `1px solid ${t.cardBorder}`, background: t.cardBg }}>
            <div className="flex items-center gap-2">
              <span className="flex-1 font-semibold text-[13px]" style={{ color: t.textStrong }}>{c.requirement}</span>
              <span className="text-[11px]" style={{ color: t.muted }}>{c.status}</span>
            </div>
            {c.reason && <div className="text-[11px] mt-1" style={{ color: t.muted }}>{c.reason}</div>}
            <div className="flex flex-wrap gap-1.5 mt-2 items-center">
              {files.map((f, j) => (
                <button key={j} onClick={() => onOpenDoc(f)}
                  className="text-[11px] px-2 py-1 rounded-lg" style={{ color: t.accent, border: `1px solid ${t.accent}55`, background: 'none', cursor: 'pointer' }}>👁 {f}</button>
              ))}
              <select defaultValue="" onChange={e => e.target.value && setOv(c.requirement, { status: e.target.value })}
                style={{ background: t.inputBg, border: `1px solid ${t.inputBorder}`, color: t.text, borderRadius: 8, padding: '4px 8px', fontSize: 11 }}>
                <option value="">status: keep</option>
                {CHECKLIST_STATUSES.map(s => <option key={s}>{s}</option>)}
              </select>
            </div>
          </div>
        )
      })}
    </div>
  )
}
```

- [ ] **Step 4: Run to verify it passes** → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/GatePanel.jsx src/components/cockpit/__tests__/GatePanel.test.jsx
git commit -m "feat(cockpit): GatePanel (per-agent gates, overrides, abort)"
```

---

### Task 17: `StepRunPanel`

**Files:**
- Create: `src/components/cockpit/StepRunPanel.jsx`
- Test: `src/components/cockpit/__tests__/StepRunPanel.test.jsx`

Props: `{ selectedId, by, onOpenDoc }`. Uses `useStepRun()`. Renders Start button (when idle), `PipelineTracker`, `GatePanel` when paused, and the live `TerminalLog` (reuse `run/TerminalLog.jsx` — read its props first; pass `logLines`).

> **NOTE for implementer:** open `src/components/run/TerminalLog.jsx` to confirm its prop name for the lines array (likely `lines` or `logLines`). Pass `useStepRun().logLines` accordingly.

- [ ] **Step 1: Write the failing test**

```jsx
import { describe, it, expect, vi } from 'vitest'
import { screen } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'

const fakeRun = {
  jobId: null, start: vi.fn(), resume: vi.fn(), approve: vi.fn(), abort: vi.fn(),
  logLines: [], status: null, isStarting: false, savedJob: null,
}
vi.mock('../../../hooks/useStepRun.js', () => ({ useStepRun: () => fakeRun }))
import StepRunPanel from '../StepRunPanel.jsx'

describe('StepRunPanel', () => {
  it('prompts to ignite when a candidate is selected and idle', () => {
    renderWithProviders(<StepRunPanel selectedId={42} by="me@x.com" onOpenDoc={() => {}} />)
    expect(screen.getByRole('button', { name: /ignite|step run/i })).toBeInTheDocument()
  })
  it('asks to select a candidate when none chosen', () => {
    renderWithProviders(<StepRunPanel selectedId={null} by="" onOpenDoc={() => {}} />)
    expect(screen.getByText(/select a candidate/i)).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run to verify it fails** → FAIL.

- [ ] **Step 3: Implement**

```jsx
import { useEffect } from 'react'
import { useTokens } from '../../lib/theme.jsx'
import { useStepRun } from '../../hooks/useStepRun.js'
import PipelineTracker from './PipelineTracker.jsx'
import GatePanel from './GatePanel.jsx'
import TerminalLog from '../run/TerminalLog.jsx'

export default function StepRunPanel({ selectedId, by, onOpenDoc }) {
  const t = useTokens()
  const run = useStepRun()
  const s = run.status

  // Offer to resume an in-flight job from a previous session.
  useEffect(() => {
    if (!run.jobId && run.savedJob) run.resume(run.savedJob)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const running = s?.status === 'running'
  const paused = s?.status === 'paused' && s?.awaiting
  const aid = run.aid ?? selectedId

  return (
    <div className="flex flex-col gap-4">
      {!run.jobId ? (
        selectedId ? (
          <button onClick={() => run.start(selectedId)} disabled={run.isStarting}
            className="px-4 py-3 rounded-xl font-bold text-sm w-full"
            style={{ background: 'linear-gradient(135deg,#005280,#1DAEEF)', color: '#fff', border: 'none', cursor: 'pointer' }}>
            {run.isStarting ? 'Starting…' : '▶ Ignite step run'}
          </button>
        ) : (
          <div className="text-sm py-8 text-center" style={{ color: t.muted }}>
            Select a candidate on the left, then ignite the run.
          </div>
        )
      ) : (
        <>
          <PipelineTracker steps={s?.steps} awaiting={s?.awaiting} running={running} />
          {paused
            ? <GatePanel aid={aid} awaiting={s.awaiting} by={by}
                onApprove={(ov) => run.approve(by || 'cockpit_ui', ov)}
                onAbort={() => run.abort(by)} onOpenDoc={onOpenDoc} />
            : <div className="text-sm" style={{ color: t.muted }}>
                {s?.status === 'complete' ? '✓ Run complete — all gates approved.'
                  : s?.status === 'aborted' ? '🛑 Aborted by human — audit recorded.'
                  : s?.status === 'failed' ? '✖ Run failed — check telemetry.'
                  : '⚙ agent working…'}
              </div>}
          <div>
            <div className="text-[10px] font-bold tracking-widest uppercase mb-1.5"
              style={{ color: t.sectionLabel }}>Live telemetry</div>
            <TerminalLog lines={run.logLines} />
          </div>
        </>
      )}
    </div>
  )
}
```

> **NOTE for implementer:** if `TerminalLog` uses a prop other than `lines`, adjust the prop name here.

- [ ] **Step 4: Run to verify it passes** → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/StepRunPanel.jsx src/components/cockpit/__tests__/StepRunPanel.test.jsx
git commit -m "feat(cockpit): StepRunPanel (tracker + gate + telemetry + resume)"
```

---

### Task 18: `BatchPanel`

**Files:**
- Create: `src/components/cockpit/BatchPanel.jsx`
- Test: `src/components/cockpit/__tests__/BatchPanel.test.jsx`

Props: `{ selectedIds }` (a Set). Uses existing `useRun()` + `useSSE()` + `LiveStream`.

- [ ] **Step 1: Write the failing test**

```jsx
import { describe, it, expect, vi } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'

const mutate = vi.fn().mockResolvedValue({ job_id: 'b1' })
vi.mock('../../../api/runs.js', () => ({ useRun: () => ({ mutateAsync: mutate, isPending: false }) }))
vi.mock('../../../hooks/useSSE.js', () => ({ useSSE: () => ({ status: 'idle', events: [], agentsByAid: {}, logLines: [], results: [] }) }))
import BatchPanel from '../BatchPanel.jsx'

describe('BatchPanel', () => {
  it('disables launch with no selection', () => {
    renderWithProviders(<BatchPanel selectedIds={new Set()} />)
    expect(screen.getByRole('button', { name: /launch/i })).toBeDisabled()
  })
  it('launches /run with selected ids', async () => {
    renderWithProviders(<BatchPanel selectedIds={new Set([1, 2])} />)
    fireEvent.click(screen.getByRole('button', { name: /launch/i }))
    expect(mutate).toHaveBeenCalledWith(expect.objectContaining({ ids: [1, 2] }))
  })
})
```

- [ ] **Step 2: Run to verify it fails** → FAIL.

- [ ] **Step 3: Implement**

```jsx
import { useState } from 'react'
import { useTokens } from '../../lib/theme.jsx'
import { useRun } from '../../api/runs.js'
import { useSSE } from '../../hooks/useSSE.js'
import LiveStream from '../run/LiveStream.jsx'

export default function BatchPanel({ selectedIds }) {
  const t = useTokens()
  const [wipe, setWipe] = useState(false)
  const [jobId, setJobId] = useState(null)
  const runMut = useRun()
  const sse = useSSE(jobId)
  const ids = [...selectedIds]

  async function launch() {
    const res = await runMut.mutateAsync({ ids, wipe })
    if (res?.job_id) setJobId(res.job_id)
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="text-xs" style={{ color: t.muted }}>
        Runs straight through (no gates). Select candidates on the left — click to toggle multiple.
      </div>
      <div className="flex items-center gap-3">
        <label className="text-xs flex items-center gap-2" style={{ color: t.text }}>
          <input type="checkbox" checked={wipe} onChange={e => setWipe(e.target.checked)} /> wipe previous outputs first
        </label>
        <div className="flex-1" />
        <button onClick={launch} disabled={!ids.length || runMut.isPending}
          className="px-4 py-2 rounded-xl font-bold text-sm"
          style={{
            background: ids.length ? 'linear-gradient(135deg,#005280,#1DAEEF)' : t.inputBg,
            color: ids.length ? '#fff' : t.muted, border: 'none',
            cursor: ids.length ? 'pointer' : 'not-allowed',
          }}>▶ Launch batch ({ids.length})</button>
      </div>
      {jobId && (
        <LiveStream status={sse.status} events={sse.events} agentsByAid={sse.agentsByAid}
          logLines={sse.logLines} results={sse.results} />
      )}
    </div>
  )
}
```

- [ ] **Step 4: Run to verify it passes** → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/BatchPanel.jsx src/components/cockpit/__tests__/BatchPanel.test.jsx
git commit -m "feat(cockpit): BatchPanel (multi-select run + live stream)"
```

---

### Task 19: `MailPanel`

**Files:**
- Create: `src/components/cockpit/MailPanel.jsx`
- Test: `src/components/cockpit/__tests__/MailPanel.test.jsx`

Uses `usePendingEmails()` for the list and `PendingEmailPreview` for the selected one.

- [ ] **Step 1: Write the failing test**

```jsx
import { describe, it, expect, vi } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'

vi.mock('../../../api/email.js', () => ({
  usePendingEmails: () => ({ data: { pending: [
    { assignment_id: 7, candidate: 'Jane', subject: 'Docs', to: 'a@x.com', cc: '', attachments_count: 2, built_at: 'now' },
  ] }, isLoading: false }),
  usePendingEmail: () => ({ data: { found: false }, isLoading: false }),
}))
import MailPanel from '../MailPanel.jsx'

describe('MailPanel', () => {
  it('lists held emails and selects one', () => {
    renderWithProviders(<MailPanel />)
    expect(screen.getByText(/Docs/)).toBeInTheDocument()
    fireEvent.click(screen.getByText(/Docs/))
    // selecting renders the (empty) preview without crashing
    expect(screen.getByText(/no held candidate email/i)).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run to verify it fails** → FAIL.

- [ ] **Step 3: Implement**

```jsx
import { useState } from 'react'
import { useTokens } from '../../lib/theme.jsx'
import { usePendingEmails } from '../../api/email.js'
import PendingEmailPreview from './PendingEmailPreview.jsx'

export default function MailPanel() {
  const t = useTokens()
  const { data, isLoading } = usePendingEmails()
  const [sel, setSel] = useState(null)
  const rows = data?.pending || []

  return (
    <div className="flex flex-col gap-3">
      <div className="text-[10px] font-bold tracking-widest uppercase" style={{ color: t.sectionLabel }}>
        Held emails — built by Agent 6, waiting for release
      </div>
      {isLoading && <div className="text-xs" style={{ color: t.muted }}>loading…</div>}
      {!isLoading && rows.length === 0 && (
        <div className="text-xs" style={{ color: t.muted }}>no held emails yet — run a candidate first.</div>
      )}
      <div className="flex flex-col gap-2" style={{ maxHeight: 300, overflowY: 'auto' }}>
        {rows.map(m => (
          <div key={m.assignment_id} onClick={() => setSel(m.assignment_id)}
            className="rounded-xl px-3 py-2.5 cursor-pointer"
            style={{ background: t.cardBg, border: `1px solid ${sel === m.assignment_id ? t.accent : t.cardBorder}` }}>
            <div className="font-bold text-[13px]" style={{ color: t.textStrong }}>
              #{m.assignment_id} · {m.candidate || m.to}
              <span className="float-right text-[11px]" style={{ color: t.muted }}>📎 {m.attachments_count}</span>
            </div>
            <div className="text-[11px]" style={{ color: t.muted }}>{m.subject}</div>
            <div className="text-[11px]" style={{ color: t.muted }}>to {m.to || '—'} · {m.built_at}</div>
          </div>
        ))}
      </div>
      {sel && <PendingEmailPreview aid={sel} />}
    </div>
  )
}
```

- [ ] **Step 4: Run to verify it passes** → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/MailPanel.jsx src/components/cockpit/__tests__/MailPanel.test.jsx
git commit -m "feat(cockpit): MailPanel (held email list + preview)"
```

---

### Task 20: `ExcelGrid`

**Files:**
- Create: `src/components/cockpit/ExcelGrid.jsx`
- Test: `src/components/cockpit/__tests__/ExcelGrid.test.jsx`

Uses `useBullhornAssignments()` for core data; paginates 25/row; fetches `/review/<id>` per visible row via `useQueries`. The merge + pagination logic is already unit-tested in `cockpit.js`; this test covers rendering + pager.

- [ ] **Step 1: Write the failing test**

```jsx
import { describe, it, expect, vi } from 'vitest'
import { screen } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'

vi.mock('../../../api/bullhorn.js', () => ({
  useBullhornAssignments: () => ({
    data: { assignments: Array.from({ length: 30 }, (_, i) => ({
      assignment_id: i + 1, candidate: `Cand ${i + 1}`, school: 'PS', status: 'Booked', state: 'new', cost_usd: 0.1,
    })) },
    isLoading: false,
  }),
}))
// useQueries returns one entry per id; stub as no review data.
vi.mock('@tanstack/react-query', async (orig) => {
  const actual = await orig()
  return { ...actual, useQueries: () => Array.from({ length: 25 }, () => ({ data: null })) }
})
import ExcelGrid from '../ExcelGrid.jsx'

describe('ExcelGrid', () => {
  it('shows 25 rows on page 1 and a pager', () => {
    renderWithProviders(<ExcelGrid />)
    expect(screen.getByText('Cand 1')).toBeInTheDocument()
    expect(screen.getByText('Cand 25')).toBeInTheDocument()
    expect(screen.queryByText('Cand 26')).not.toBeInTheDocument()
    expect(screen.getByText(/page 1 of 2/i)).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run to verify it fails** → FAIL.

- [ ] **Step 3: Implement**

```jsx
import { useState } from 'react'
import { useQueries } from '@tanstack/react-query'
import { useTokens } from '../../lib/theme.jsx'
import { useBullhornAssignments } from '../../api/bullhorn.js'
import { apiClient } from '../../lib/apiClient.js'
import { mk } from '../../console/modeKey.js'
import { paginate, mergeExcelRow } from '../../lib/cockpit.js'
import { formatUSD } from '../../lib/format.js'

const COLS = [
  ['id', '#'], ['candidate', 'Candidate'], ['district', 'District/School'],
  ['bullhorn_status', 'Status'], ['run_state', 'Run'], ['tier', 'Tier'],
  ['ready', 'Ready'], ['valid', '✓'], ['expired', '✗'], ['missing', '∅'],
  ['credentialer', 'Cred. Coord.'], ['license', 'License/Cert'], ['cost', 'Cost'],
]

export default function ExcelGrid() {
  const t = useTokens()
  const [page, setPage] = useState(1)
  const { data, isLoading } = useBullhornAssignments()
  const all = data?.assignments || []
  const { slice, totalPages, page: cur } = paginate(all, page, 25)

  // Enrich the current page only.
  const reviews = useQueries({
    queries: slice.map(a => ({
      queryKey: mk('review', a.assignment_id),
      queryFn: () => apiClient.get(`/review/${a.assignment_id}`),
      staleTime: 30_000,
    })),
  })
  const rows = slice.map((a, i) => mergeExcelRow(a, reviews[i]?.data))

  const cell = (row, key) => {
    const v = row[key]
    if (key === 'cost' && v != null) return formatUSD(v)
    if (key === 'ready') return v == null ? '' : (v ? '✅' : '❌')
    return v == null ? '' : String(v)
  }

  return (
    <div className="flex flex-col gap-3">
      {isLoading ? <div className="text-xs" style={{ color: t.muted }}>loading…</div> : (
        <div className="overflow-auto rounded-xl" style={{ border: `1px solid ${t.cardBorder}` }}>
          <table className="w-full text-xs" style={{ borderCollapse: 'collapse', fontFamily: 'Geist,sans-serif' }}>
            <thead>
              <tr style={{ position: 'sticky', top: 0, background: t.inputBg }}>
                {COLS.map(([k, label]) => (
                  <th key={k} className="text-left px-2.5 py-2 font-bold"
                    style={{ color: t.sectionLabel, borderBottom: `1px solid ${t.cardBorder}`, whiteSpace: 'nowrap' }}>{label}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((row, i) => (
                <tr key={row.id ?? i} style={{ background: i % 2 ? 'transparent' : (t.isDark ? 'rgba(255,255,255,0.02)' : 'rgba(0,82,128,0.02)') }}>
                  {COLS.map(([k]) => (
                    <td key={k} className="px-2.5 py-1.5"
                      style={{ color: t.text, borderBottom: `1px solid ${t.divider}`, whiteSpace: 'nowrap',
                        fontFamily: ['id', 'cost', 'valid', 'expired', 'missing'].includes(k) ? 'JetBrains Mono,monospace' : undefined }}>
                      {cell(row, k)}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <div className="flex items-center gap-3 text-xs" style={{ color: t.muted }}>
        <button onClick={() => setPage(p => Math.max(1, p - 1))} disabled={cur <= 1}
          className="px-3 py-1.5 rounded-lg" style={{ border: `1px solid ${t.cardBorder}`, background: 'none', color: t.text, cursor: cur <= 1 ? 'not-allowed' : 'pointer' }}>← Prev</button>
        <span>Page {cur} of {totalPages}</span>
        <button onClick={() => setPage(p => Math.min(totalPages, p + 1))} disabled={cur >= totalPages}
          className="px-3 py-1.5 rounded-lg" style={{ border: `1px solid ${t.cardBorder}`, background: 'none', color: t.text, cursor: cur >= totalPages ? 'not-allowed' : 'pointer' }}>Next →</button>
        <span className="ml-auto">{all.length} assignments · tracker-only columns (AM/Recruiter/Lead) are not API-backed</span>
      </div>
    </div>
  )
}
```

- [ ] **Step 4: Run to verify it passes** → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/ExcelGrid.jsx src/components/cockpit/__tests__/ExcelGrid.test.jsx
git commit -m "feat(cockpit): ExcelGrid (paginated, API-assembled rows)"
```

---

## Phase 5 — Assembly & mode router

### Task 21: `CockpitTabs` + `CockpitView`

**Files:**
- Create: `src/components/cockpit/CockpitTabs.jsx`
- Create: `src/components/cockpit/CockpitView.jsx`
- Test: `src/components/cockpit/__tests__/CockpitView.test.jsx`

`CockpitView` owns selection state (`selectedId`, `batchIds`), active tab, document-drawer state, and the operator `by` email; renders `AssignmentRail` (left) + the active panel (right) + `DocumentDrawer`.

- [ ] **Step 1: Write the failing test**

```jsx
import { describe, it, expect, vi } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'

vi.mock('../../../api/bullhorn.js', () => ({
  useBullhornAssignments: () => ({ data: { assignments: [
    { assignment_id: 1, candidate: 'Jane', school: 'PS 1', status: 'Booked', state: 'new', cost_usd: 0 },
  ] }, isLoading: false }),
}))
vi.mock('../StepRunPanel.jsx', () => ({ default: () => <div>STEP PANEL</div> }))
vi.mock('../BatchPanel.jsx', () => ({ default: () => <div>BATCH PANEL</div> }))
vi.mock('../MailPanel.jsx', () => ({ default: () => <div>MAIL PANEL</div> }))
vi.mock('../ExcelGrid.jsx', () => ({ default: () => <div>EXCEL GRID</div> }))
import CockpitView from '../CockpitView.jsx'

describe('CockpitView', () => {
  it('shows Step Run by default and switches tabs', () => {
    renderWithProviders(<CockpitView />)
    expect(screen.getByText('STEP PANEL')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /excel/i }))
    expect(screen.getByText('EXCEL GRID')).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run to verify it fails** → FAIL.

- [ ] **Step 3: Implement `CockpitTabs.jsx`**

```jsx
import { useTokens } from '../../lib/theme.jsx'

const TABS = [['step', '⚡ Step Run'], ['batch', '▦ Batch'], ['mail', '📧 Mail'], ['excel', '▤ Excel']]

export default function CockpitTabs({ active, onChange }) {
  const t = useTokens()
  return (
    <div className="flex gap-2 mb-4">
      {TABS.map(([key, label]) => {
        const on = active === key
        return (
          <button key={key} onClick={() => onChange(key)}
            className="px-4 py-2 rounded-xl font-bold text-xs"
            style={{
              border: on ? 'none' : `1px solid ${t.cardBorder}`,
              background: on ? 'linear-gradient(90deg,#005280,#1DAEEF)' : 'transparent',
              color: on ? '#fff' : t.muted, cursor: 'pointer',
            }}>{label}</button>
        )
      })}
    </div>
  )
}
```

- [ ] **Step 4: Implement `CockpitView.jsx`**

```jsx
import { useState } from 'react'
import { useTokens } from '../../lib/theme.jsx'
import { useBullhornAssignments } from '../../api/bullhorn.js'
import AssignmentRail from './AssignmentRail.jsx'
import CockpitTabs from './CockpitTabs.jsx'
import StepRunPanel from './StepRunPanel.jsx'
import BatchPanel from './BatchPanel.jsx'
import MailPanel from './MailPanel.jsx'
import ExcelGrid from './ExcelGrid.jsx'
import DocumentDrawer from './DocumentDrawer.jsx'

export default function CockpitView() {
  const t = useTokens()
  const { data, isLoading } = useBullhornAssignments()
  const assignments = data?.assignments || []

  const [tab, setTab] = useState('step')
  const [selectedId, setSelectedId] = useState(null)
  const [batchIds, setBatchIds] = useState(new Set())
  const [by, setBy] = useState('')
  const [doc, setDoc] = useState(null) // { aid, file }

  const multi = tab === 'batch'
  function pick(id) {
    if (multi) {
      setBatchIds(prev => {
        const next = new Set(prev)
        next.has(id) ? next.delete(id) : next.add(id)
        return next
      })
    } else {
      setSelectedId(id)
    }
  }
  const openDoc = (file) => setDoc({ aid: selectedId, file })

  return (
    <div className="grid h-full" style={{ gridTemplateColumns: '320px 1fr' }}>
      {/* Left rail */}
      <div className="p-4 overflow-hidden" style={{ borderRight: `1px solid ${t.divider}` }}>
        <div className="text-[10px] font-bold tracking-widest uppercase mb-2" style={{ color: t.sectionLabel }}>
          Live in Bullhorn — {assignments.length}
        </div>
        <AssignmentRail assignments={assignments} loading={isLoading} multi={multi}
          selectedId={selectedId} selectedIds={batchIds} onPick={pick} />
      </div>

      {/* Right pane */}
      <div className="p-5 overflow-y-auto">
        <div className="flex items-center gap-3 mb-3">
          <CockpitTabs active={tab} onChange={setTab} />
          <div className="flex-1" />
          <input value={by} onChange={e => setBy(e.target.value)} placeholder="👤 your email — required for changes"
            className="rounded-lg px-3 py-2 text-xs" style={{ width: 250, background: t.inputBg, border: `1px solid ${t.inputBorder}`, color: t.text, outline: 'none' }} />
        </div>

        {tab === 'step'  && <StepRunPanel selectedId={selectedId} by={by} onOpenDoc={openDoc} />}
        {tab === 'batch' && <BatchPanel selectedIds={batchIds} />}
        {tab === 'mail'  && <MailPanel />}
        {tab === 'excel' && <ExcelGrid />}
      </div>

      <DocumentDrawer aid={doc?.aid} file={doc?.file} onClose={() => setDoc(null)} />
    </div>
  )
}
```

- [ ] **Step 5: Run to verify it passes** → PASS.

- [ ] **Step 6: Commit**

```bash
git add src/components/cockpit/CockpitTabs.jsx src/components/cockpit/CockpitView.jsx src/components/cockpit/__tests__/CockpitView.test.jsx
git commit -m "feat(cockpit): CockpitView + CockpitTabs assembly"
```

---

### Task 22: Extract `AssignmentsList` (preserve live mode)

**Files:**
- Create: `src/components/assignments/AssignmentsList.jsx`
- Modify: `src/pages/AssignmentsPage.jsx`

- [ ] **Step 1: Move the current body into `AssignmentsList.jsx`**

Copy the **entire current contents** of `src/pages/AssignmentsPage.jsx` into `src/components/assignments/AssignmentsList.jsx`, renaming the default export function from `AssignmentsPage` to `AssignmentsList`. Fix the relative import depth (these imports move from `../` to `../../`):

```jsx
// at top of AssignmentsList.jsx — adjust paths (one level deeper than pages/)
import { useAssignments, useTestIds } from '../../api/assignments.js'
import { apiClient } from '../../lib/apiClient.js'
import { mk } from '../../console/modeKey.js'
import { useConsoleMode } from '../../console/ConsoleModeProvider.jsx'
import TierChip from '../common/TierChip.jsx'
import Spinner from '../common/Spinner.jsx'
import EmptyState from '../common/EmptyState.jsx'
import { useDebounce } from '../../hooks/useDebounce.js'
import { formatUSD } from '../../lib/format.js'
import { useTokens } from '../../lib/theme.jsx'
import { realCandidateName } from '../../lib/redact.js'
// keep: import { useState } from 'react'; import { Link } from 'react-router-dom'; import { useQueries } from '@tanstack/react-query'
```

Keep the `SkeletonRow` and `AssignmentRow` helpers in this same file (they move with it).

- [ ] **Step 2: Rewrite `src/pages/AssignmentsPage.jsx` as the mode router**

```jsx
import { useConsoleMode } from '../console/ConsoleModeProvider.jsx'
import AssignmentsList from '../components/assignments/AssignmentsList.jsx'
import CockpitView from '../components/cockpit/CockpitView.jsx'

export default function AssignmentsPage() {
  const { mode } = useConsoleMode()
  // Test mode → the cockpit (lives on :8001, which exposes /step_run, /bullhorn_assignments, /pending_emails).
  // Live mode → the existing assignments list, unchanged.
  return mode === 'test' ? <CockpitView /> : <AssignmentsList />
}
```

- [ ] **Step 3: Run the full test suite**

Run: `npm test`
Expected: PASS (all existing + new tests).

- [ ] **Step 4: Manual smoke check**

Run: `npm run dev`, open the app in **test mode**, click **Assignments** → cockpit appears (left list + Step Run/Batch/Mail/Excel). Switch to **live mode** → the original Assignments list renders unchanged.

- [ ] **Step 5: Commit**

```bash
git add src/components/assignments/AssignmentsList.jsx src/pages/AssignmentsPage.jsx
git commit -m "feat(cockpit): mode-router Assignments (test=cockpit, live=list)"
```

---

### Task 23: Lint + full verification

- [ ] **Step 1: Lint**

Run: `npm run lint`
Expected: no errors. Fix any unused imports / hook-deps warnings introduced.

- [ ] **Step 2: Full test run**

Run: `npm test`
Expected: all PASS.

- [ ] **Step 3: Build**

Run: `npm run build`
Expected: build succeeds.

- [ ] **Step 4: Commit any lint fixes**

```bash
git add -A
git commit -m "chore(cockpit): lint + verification pass"
```

---

## Self-Review (plan author)

**Spec coverage:**
- Two-pane cockpit, test-mode only → Tasks 21, 22. ✓
- Left list from `/bullhorn_assignments` → Tasks 2, 14. ✓
- Step Run + pipeline tracker + per-agent gates + OIG + overrides + resume → Tasks 1, 5, 6, 7, 8, 10, 11, 12, 16, 17. ✓
- Batch → Task 18. ✓
- Mail (`/pending_emails`, `/pending_email`) → Tasks 3, 15, 19. ✓
- Excel paginated, assembled from `/bullhorn_assignments` + `/review` → Tasks 2, 6, 20. ✓
- Document drawer (reuse DocumentViewer) → Task 13. ✓
- Match ACAP theme → all components use `useTokens()`. ✓
- Live mode untouched → Task 22 preserves `AssignmentsList`. ✓
- Testing strategy → unit tests Tasks 6–8; render/interaction tests Tasks 10–21. ✓

**Placeholder scan:** No TBD/TODO. Three explicit "NOTE for implementer" items (verify `ThemeProvider` export name, `Checklist`/`ChecklistRow` props, `TerminalLog` prop name) are real verification steps against existing files, not deferred work — each has a concrete fallback.

**Type/signature consistency:** `assignmentState`, `stateTag`, `pipelineNodes`, `mergeExcelRow`, `paginate`, `gateKey`, `approvePayload`, `readStepJob/writeStepJob/clearStepJob`, `CHECKLIST_STATUSES`, `COCKPIT_AGENTS` defined in Tasks 6–7 and consumed with matching signatures in Tasks 10, 14, 16, 17, 20. `useStepRun` shape (Task 8) matches consumption in Task 17. API hook names (Tasks 2–5) match imports in Tasks 14–20.

**Scope:** One cohesive subsystem (the cockpit). Single plan is appropriate; tasks are independently committable and build on each other in order.
# Cockpit Click Branch + Real-time Dashboard Polling — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Branch cockpit candidate clicks by processed state, and add 15-second polling to DashboardPage queries.

**Architecture:** Change A patches `CockpitView.jsx` to import `assignmentState` from `src/lib/cockpit.js` and replace the `pick()` function with a branch. Change B patches `src/api/assignments.js` to accept optional query options and threads `refetchInterval: 15_000` through from `DashboardPage.jsx`; the `useQueries` inside `DashboardContent` also gets the same interval. Tests are added to the existing `CockpitView.test.jsx`; no new test files.

**Tech Stack:** React 19, Vite, Vitest 2, react-query v5, react-router-dom v6, @testing-library/react

---

## File Map

| File | Action |
|------|--------|
| `src/components/cockpit/CockpitView.jsx` | Modify — add import, replace `pick()` |
| `src/components/cockpit/__tests__/CockpitView.test.jsx` | Modify — add `useNavigate` mock + processed-row test |
| `src/api/assignments.js` | Modify — add optional `options` param to `useAssignments` |
| `src/pages/DashboardPage.jsx` | Modify — pass `{ refetchInterval: 15_000 }` to `useAssignments`, add interval to `useQueries` |

---

### Task 1: Patch CockpitView — conditional pick()

**Files:**
- Modify: `src/components/cockpit/CockpitView.jsx`

- [ ] **Step 1: Add the `assignmentState` import**

Open `src/components/cockpit/CockpitView.jsx`. After line 11 (the last existing import), add:

```js
import { assignmentState } from '../../lib/cockpit.js'
```

- [ ] **Step 2: Replace the `pick` function**

Replace the existing `pick` function (lines 37–40):

```js
  function pick(id) {
    setSelectedId(id)
    setDoc(null)
  }
```

with:

```js
  function pick(id) {
    const a = assignments.find(x => x.assignment_id === id)
    if (a && assignmentState(a) !== 'new') { navigate(`/review/${id}`); return }
    setSelectedId(id)
    setDoc(null)
  }
```

- [ ] **Step 3: Verify file looks correct**

Run:
```bash
npx vitest run src/components/cockpit/__tests__/CockpitView.test.jsx
```
Expected: 1 test passes (existing test still green).

---

### Task 2: Add CockpitView test for processed-row navigation

**Files:**
- Modify: `src/components/cockpit/__tests__/CockpitView.test.jsx`

- [ ] **Step 1: Add the `useNavigate` mock at the top of the test file**

The mock must go BEFORE any imports of the component under test (this is already the pattern in the file — mocks go before the `import CockpitView` line). Add this block after the existing `vi.mock` calls and before `import CockpitView`:

```js
const mockNavigate = vi.fn()
vi.mock('react-router-dom', async (orig) => {
  const actual = await orig()
  return { ...actual, useNavigate: () => mockNavigate }
})
```

- [ ] **Step 2: Update the `useBullhornAssignments` mock to include a processed row**

Replace the existing bullhorn mock:

```js
vi.mock('../../../api/bullhorn.js', () => ({
  useBullhornAssignments: () => ({ data: { assignments: [
    { assignment_id: 1, candidate: 'Jane', school: 'PS 1', status: 'Booked', state: 'new', cost_usd: 0 },
  ] }, isLoading: false }),
}))
```

with:

```js
vi.mock('../../../api/bullhorn.js', () => ({
  useBullhornAssignments: () => ({ data: { assignments: [
    { assignment_id: 1, candidate: 'Jane', school: 'PS 1', status: 'Booked', state: 'new', cost_usd: 0 },
    { assignment_id: 2, candidate: 'Joe',  school: 'PS 2', status: 'Booked', state: 'done', cost_usd: 0 },
  ] }, isLoading: false }),
}))
```

- [ ] **Step 3: Add the new test inside the `describe` block**

After the existing `it('shows Step Run by default...')` test, add:

```jsx
  it('navigates to review when a processed candidate is clicked', () => {
    renderWithProviders(<MemoryRouter><CockpitView /></MemoryRouter>)
    fireEvent.click(screen.getByText('Joe'))
    expect(mockNavigate).toHaveBeenCalledWith('/review/2')
  })
```

- [ ] **Step 4: Add `beforeEach` mock reset so tests don't bleed**

The file already has `beforeEach(() => sessionStorage.clear())`. Extend it to also clear `mockNavigate`:

Replace:
```js
  beforeEach(() => sessionStorage.clear())
```
with:
```js
  beforeEach(() => { sessionStorage.clear(); mockNavigate.mockClear() })
```

- [ ] **Step 5: Run the test suite for this file**

```bash
npx vitest run src/components/cockpit/__tests__/CockpitView.test.jsx
```
Expected: 2 tests pass.

---

### Task 3: Add optional options param to useAssignments

**Files:**
- Modify: `src/api/assignments.js`

- [ ] **Step 1: Replace `useAssignments` with option-accepting version**

Replace:

```js
export function useAssignments() {
  return useQuery({
    queryKey: mk('assignments'),
    queryFn: () => apiClient.get('/assignments'),
    staleTime: 60_000,
  })
}
```

with:

```js
export function useAssignments(options = {}) {
  return useQuery({
    queryKey: mk('assignments'),
    queryFn: () => apiClient.get('/assignments'),
    staleTime: 60_000,
    ...options,
  })
}
```

This is backward-compatible — all existing callers pass no arguments and receive identical behavior.

---

### Task 4: Wire refetchInterval into DashboardPage

**Files:**
- Modify: `src/pages/DashboardPage.jsx`

- [ ] **Step 1: Add refetchInterval to the useAssignments call in DashboardPage**

Find this line in `DashboardPage` (around line 135):

```js
  const { data: assignmentsData, isLoading, error } = useAssignments()
```

Replace with:

```js
  const { data: assignmentsData, isLoading, error } = useAssignments({ refetchInterval: 15_000, refetchIntervalInBackground: false })
```

- [ ] **Step 2: Add refetchInterval to the useQueries block in DashboardContent**

Find the `useQueries` call in `DashboardContent` (lines 52–59):

```js
  const results = useQueries({
    queries: ids.map(id => ({
      queryKey: mk('review', id),
      queryFn: () => apiClient.get(`/review/${id}`),
      enabled: !!id,
      staleTime: 10 * 60 * 1000,
    })),
  })
```

Replace with:

```js
  const results = useQueries({
    queries: ids.map(id => ({
      queryKey: mk('review', id),
      queryFn: () => apiClient.get(`/review/${id}`),
      enabled: !!id,
      staleTime: 10 * 60 * 1000,
      refetchInterval: 15_000,
      refetchIntervalInBackground: false,
    })),
  })
```

Note: DashboardPage already has a pulsing "Live" dot with loading state indicator (lines 77–86). No additional affordance is needed.

---

### Task 5: Full suite verification + commit

- [ ] **Step 1: Run full Vitest suite**

```bash
npx vitest run
```
Expected: all tests green, no failures.

- [ ] **Step 2: Run the build**

```bash
npm run build
```
Expected: build succeeds with no errors.

- [ ] **Step 3: Run ESLint on changed files**

```bash
npx eslint src/components/cockpit/CockpitView.jsx src/pages/DashboardPage.jsx src/api/assignments.js
```
Expected: no errors or warnings.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(flow): processed candidates open Review on click; real-time Dashboard polling"
```
Expected: commit succeeds, SHA printed.

# Cred Tracker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a DB-backed, editable onboarding Tracker reading only `stg.Cred_Tracker`, with CRUD in the `excel-api` service and a redesigned dark/light Tailwind table (sort/filter/paginate, smooth scroll, inline row edit).

**Architecture:** `excel-api` (:8002) gains a `POST /cred-tracker/sync` that pulls agent output from the cockpit API (:8001), maps it to `stg.Cred_Tracker` columns, and upserts — refreshing agent columns while preserving credentialer edits. The Tracker UI reads only `GET /cred-tracker`, edits via `PATCH`, removes via `DELETE`, and auto-runs sync on page load.

**Tech Stack:** Node 18+/Express + `mssql` (backend, global `fetch`, no new dep); React 19 + `@tanstack/react-query` + `@tanstack/react-table` (NEW) + `framer-motion` + `lenis` + Tailwind v4 (frontend).

## Global Constraints

- All frontend styling in Tailwind CSS + inline style tokens from `useTokens()` (existing pattern). No CSS frameworks beyond Tailwind.
- Two themes (dark/light) via existing `useTokens()`; brand accents `#5BA8FF` (dark) / `#1E6FE0` (light). Fonts: `Geist` (UI), `JetBrains Mono` (ids/dates).
- Backend pure logic lives in `excel-api/credTrackerMap.js` (no DB/network); DB+network in `excel-api/credTracker.js`. Mirror existing `normalize.js` / `db.js` split.
- DB table name is exactly `stg.Cred_Tracker`.
- Editable fields (exactly 7): `start_date`, `credentialer`, `date_confirmed`, `new_rebook_ext`, `last_updated`, `onboarding_status`, `lead`. PATCH must whitelist these; any other key is ignored.
- Backend tests: `node:test` (run `npm test` in `excel-api`). Frontend tests: `vitest` (run `npm test` at repo root).
- Values matching `/^MISSING:/i` or containing `REDACTED`/`REDACT`, or null/empty → stored as NULL/blank.
- Commit after every task.

---

## File Structure

- `excel-api/credTrackerMap.js` (NEW) — pure helpers: clean/redaction, `parseNewRebookExt`, `realCandidateName`, `mapAgentToRow`, `buildUpsertPlan`, `normalizeCredRow`, `EDITABLE_FIELD_MAP`, `pickEditable`.
- `excel-api/test/credTrackerMap.test.js` (NEW) — unit tests for the above.
- `excel-api/credTracker.js` (NEW) — DB+network layer: `ensureCredTrackerTable`, `listRows`, `getRow`, `updateRow`, `deleteRow`, `syncFromCockpit`.
- `excel-api/index.js` (MODIFY) — mount `express.json()` + 5 `/cred-tracker` routes; read `COCKPIT_API_BASE`.
- `src/api/credTracker.js` (NEW) — react-query hooks.
- `src/lib/credTracker.js` (NEW) — `CRED_COLUMNS`, `EDITABLE_FIELDS`, `buildCredRow` (React-free).
- `src/lib/__tests__/credTracker.test.js` (NEW) — unit tests for the lib.
- `src/hooks/useLenisScroll.js` (NEW) — scoped Lenis smooth scroll for one container.
- `src/pages/TrackerPage.jsx` (REPLACE) — redesigned table.
- `src/pages/__tests__/TrackerPage.test.jsx` (REPLACE) — new tests.
- `package.json` (MODIFY) — add `@tanstack/react-table`.

---

## Task 1: Backend pure mapping helpers

**Files:**
- Create: `excel-api/credTrackerMap.js`
- Test: `excel-api/test/credTrackerMap.test.js`

**Interfaces:**
- Produces:
  - `clean(v) -> string` ('' for null/MISSING/REDACTED)
  - `orNull(v) -> string|null`
  - `parseNewRebookExt(jobTitle) -> 'EXT'|'Rebook'|'New'`
  - `realCandidateName(agent2) -> string|null`
  - `mapAgentToRow(agent2, agent3) -> { Assignment_Id, Candidate_Name, Start_Date, Credentialer, Initial_Start_Date, District, State, License_Cert, New_Rebook_Ext, AM, Recruiter }`
  - `buildUpsertPlan(rows, existingIdSet) -> { toInsert: row[], toRefresh: {Assignment_Id,Candidate_Name,District,State,License_Cert,AM,Recruiter}[] }`
  - `normalizeCredRow(dbRow) -> snake_case object`
  - `EDITABLE_FIELD_MAP` (snake_case -> DB col), `EDITABLE_FIELDS` (string[]), `pickEditable(fields) -> {key,col,value}[]`

- [ ] **Step 1: Write the failing test**

Create `excel-api/test/credTrackerMap.test.js`:

```js
const { test } = require('node:test')
const assert = require('node:assert')
const {
  clean, parseNewRebookExt, realCandidateName, mapAgentToRow,
  buildUpsertPlan, normalizeCredRow, pickEditable,
} = require('../credTrackerMap.js')

const AGENT2 = {
  output: {
    assignment_id: 149035, candidate_name: '[REDACTED]', hospital: 'Twin Rivers USD',
    job_title: '26/27 SY Renewals l Paraprofessionals', start_date: '2026-08-18',
    discipline: 'Paraprofessional (PARA)', recruiter: 'Kristin Gergen',
    account_manager: 'MISSING: account_manager', client_state: 'California',
    verifier: { checks: [{ name: 'field_candidate_name', actual: 'Jane Doe' }] },
  },
}
const AGENT3 = { output: { credentialer_name: 'Sophia Gray' } }

test('clean blanks null/MISSING/REDACTED', () => {
  assert.equal(clean(null), '')
  assert.equal(clean('MISSING: account_manager'), '')
  assert.equal(clean('[REDACTED]'), '')
  assert.equal(clean('California'), 'California')
})

test('parseNewRebookExt classifies by job title', () => {
  assert.equal(parseNewRebookExt('ESY 2026 l Paraprofessional (PARA)'), 'EXT')
  assert.equal(parseNewRebookExt('26/27 SY Renewals l Paraprofessionals'), 'Rebook')
  assert.equal(parseNewRebookExt('Rebook - School Nurse'), 'Rebook')
  assert.equal(parseNewRebookExt('New SY Assignment'), 'New')
  assert.equal(parseNewRebookExt(''), 'New')
})

test('realCandidateName reads verifier actual, skips redacted', () => {
  assert.equal(realCandidateName(AGENT2), 'Jane Doe')
  assert.equal(realCandidateName({ output: { candidate_name: '[REDACTED]' } }), null)
  assert.equal(realCandidateName({ output: { candidate_name: 'Bob' } }), 'Bob')
})

test('mapAgentToRow maps agent2/agent3 to DB columns', () => {
  const r = mapAgentToRow(AGENT2, AGENT3)
  assert.equal(r.Assignment_Id, 149035)
  assert.equal(r.Candidate_Name, 'Jane Doe')
  assert.equal(r.District, 'Twin Rivers USD')
  assert.equal(r.State, 'California')
  assert.equal(r.License_Cert, 'Paraprofessional (PARA)')
  assert.equal(r.Recruiter, 'Kristin Gergen')
  assert.equal(r.AM, null)               // MISSING -> null
  assert.equal(r.Start_Date, '2026-08-18')
  assert.equal(r.Initial_Start_Date, '2026-08-18')
  assert.equal(r.New_Rebook_Ext, 'Rebook')
  assert.equal(r.Credentialer, 'Sophia Gray')
})

test('buildUpsertPlan refreshes only non-editable cols for existing ids', () => {
  const rows = [mapAgentToRow(AGENT2, AGENT3), { ...mapAgentToRow(AGENT2, AGENT3), Assignment_Id: 200 }]
  const plan = buildUpsertPlan(rows, new Set([149035]))
  assert.equal(plan.toInsert.length, 1)
  assert.equal(plan.toInsert[0].Assignment_Id, 200)
  assert.equal(plan.toRefresh.length, 1)
  const ref = plan.toRefresh[0]
  assert.equal(ref.Assignment_Id, 149035)
  assert.equal(ref.Candidate_Name, 'Jane Doe')
  // editable cols must NOT be in the refresh payload
  assert.equal('Start_Date' in ref, false)
  assert.equal('Credentialer' in ref, false)
  assert.equal('New_Rebook_Ext' in ref, false)
})

test('normalizeCredRow maps DB cols to snake_case', () => {
  const out = normalizeCredRow({ Assignment_Id: 1, Candidate_Name: 'Jane', Onboarding_Status: 'ok', Updated_By: 'a@b.com' })
  assert.equal(out.assignment_id, 1)
  assert.equal(out.candidate_name, 'Jane')
  assert.equal(out.onboarding_status, 'ok')
  assert.equal(out.updated_by, 'a@b.com')
})

test('pickEditable keeps only whitelisted keys', () => {
  const picked = pickEditable({ lead: 'Tina', district: 'hack', onboarding_status: 'note' })
  const keys = picked.map(p => p.key).sort()
  assert.deepEqual(keys, ['lead', 'onboarding_status'])
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd excel-api && node --test test/credTrackerMap.test.js`
Expected: FAIL — `Cannot find module '../credTrackerMap.js'`

- [ ] **Step 3: Write minimal implementation**

Create `excel-api/credTrackerMap.js`:

```js
// Pure helpers for stg.Cred_Tracker: agent payload -> DB columns, upsert planning,
// normalization, and the editable-field whitelist. No DB / network here.

function clean(v) {
  if (v == null) return ''
  const s = String(v).trim()
  if (/^MISSING:/i.test(s)) return ''
  if (/REDACT/i.test(s)) return ''
  return s
}
function orNull(v) { const s = clean(v); return s === '' ? null : s }

function parseNewRebookExt(jobTitle) {
  const s = String(jobTitle || '')
  if (/\bESY\b/i.test(s) || /\bEXT\b/i.test(s) || /extension/i.test(s)) return 'EXT'
  if (/renewal/i.test(s) || /rebook/i.test(s)) return 'Rebook'
  return 'New'
}

function isRedacted(v) {
  return v == null || v === '' || (typeof v === 'string' && v.toUpperCase().includes('REDACT'))
}
// Real candidate name lives in intake (agent 2) verifier checks; output.candidate_name is redacted.
function realCandidateName(agent2) {
  const o = agent2?.output ?? agent2 ?? {}
  const checks = o?.verifier?.checks ?? agent2?.verifier?.checks ?? []
  const actual = (checks.find(c => c?.name === 'field_candidate_name') || {}).actual
  if (actual && !isRedacted(actual)) return actual
  return isRedacted(o.candidate_name) ? null : o.candidate_name
}

function mapAgentToRow(agent2, agent3) {
  const o = agent2?.output ?? agent2 ?? {}
  const a3 = agent3?.output ?? agent3 ?? {}
  const start = orNull(o.start_date)
  return {
    Assignment_Id: Number(o.assignment_id),
    Candidate_Name: realCandidateName(agent2) || null,
    Start_Date: start,
    Credentialer: orNull(a3.credentialer_name),
    Initial_Start_Date: start,
    District: orNull(o.hospital),
    State: orNull(o.client_state),
    License_Cert: orNull(o.discipline),
    New_Rebook_Ext: parseNewRebookExt(clean(o.job_title)),
    AM: orNull(o.account_manager),
    Recruiter: orNull(o.recruiter),
  }
}

const REFRESH_COLUMNS = ['Candidate_Name', 'District', 'State', 'License_Cert', 'AM', 'Recruiter']
function buildUpsertPlan(rows, existingIdSet) {
  const toInsert = [], toRefresh = []
  for (const r of rows) {
    if (!r || !Number.isFinite(r.Assignment_Id)) continue
    if (existingIdSet.has(r.Assignment_Id)) {
      const ref = { Assignment_Id: r.Assignment_Id }
      for (const c of REFRESH_COLUMNS) ref[c] = r[c]
      toRefresh.push(ref)
    } else {
      toInsert.push(r)
    }
  }
  return { toInsert, toRefresh }
}

const DB_TO_SNAKE = {
  Assignment_Id: 'assignment_id', Candidate_Name: 'candidate_name', Start_Date: 'start_date',
  Credentialer: 'credentialer', Date_Confirmed: 'date_confirmed', Initial_Start_Date: 'initial_start_date',
  District: 'district', State: 'state', License_Cert: 'license_cert', New_Rebook_Ext: 'new_rebook_ext',
  Last_Updated: 'last_updated', Onboarding_Status: 'onboarding_status', AM: 'am', Recruiter: 'recruiter',
  Lead: 'lead', Updated_By: 'updated_by', Updated_At: 'updated_at', Synced_At: 'synced_at',
}
function normalizeCredRow(row) {
  const out = {}
  for (const [dbCol, key] of Object.entries(DB_TO_SNAKE)) {
    if (Object.prototype.hasOwnProperty.call(row, dbCol)) out[key] = row[dbCol]
  }
  return out
}

const EDITABLE_FIELD_MAP = {
  start_date: 'Start_Date', credentialer: 'Credentialer', date_confirmed: 'Date_Confirmed',
  new_rebook_ext: 'New_Rebook_Ext', last_updated: 'Last_Updated',
  onboarding_status: 'Onboarding_Status', lead: 'Lead',
}
const EDITABLE_FIELDS = Object.keys(EDITABLE_FIELD_MAP)
function pickEditable(fields) {
  const out = []
  for (const [key, col] of Object.entries(EDITABLE_FIELD_MAP)) {
    if (fields && Object.prototype.hasOwnProperty.call(fields, key)) out.push({ key, col, value: fields[key] })
  }
  return out
}

module.exports = {
  clean, orNull, parseNewRebookExt, realCandidateName, mapAgentToRow,
  buildUpsertPlan, normalizeCredRow, EDITABLE_FIELD_MAP, EDITABLE_FIELDS, pickEditable,
  DATE_COLUMNS: ['Start_Date', 'Date_Confirmed', 'Initial_Start_Date', 'Last_Updated'],
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd excel-api && node --test test/credTrackerMap.test.js`
Expected: PASS (7 tests)

- [ ] **Step 5: Commit**

```bash
git add excel-api/credTrackerMap.js excel-api/test/credTrackerMap.test.js
git commit -m "feat(tracker): pure agent->Cred_Tracker mapping helpers + tests"
```

---

## Task 2: Backend DB + sync layer

**Files:**
- Create: `excel-api/credTracker.js`

**Interfaces:**
- Consumes (Task 1): `mapAgentToRow`, `buildUpsertPlan`, `normalizeCredRow`, `pickEditable`, `DATE_COLUMNS`.
- Consumes (existing): `excel-api/db.js` → `{ sql, getPool }`.
- Produces:
  - `ensureCredTrackerTable(pool) -> Promise<void>`
  - `listRows(pool) -> Promise<object[]>` (snake_case rows, dates as `YYYY-MM-DD` strings)
  - `getRow(pool, id) -> Promise<object|null>`
  - `updateRow(pool, id, fields, updatedBy) -> Promise<object|null>`
  - `deleteRow(pool, id) -> Promise<boolean>`
  - `syncFromCockpit(pool, cockpitBase) -> Promise<{ synced:number, inserted:number, refreshed:number }>`

This task is integration-level (needs SQL + cockpit API); it is verified by the manual smoke test in Task 3, not by unit tests. The pure logic it relies on is already tested in Task 1.

- [ ] **Step 1: Write the module**

Create `excel-api/credTracker.js`:

```js
const { sql } = require('./db.js')
const {
  mapAgentToRow, buildUpsertPlan, normalizeCredRow, pickEditable, DATE_COLUMNS,
} = require('./credTrackerMap.js')

const DATE_SET = new Set(DATE_COLUMNS)

async function ensureCredTrackerTable(pool) {
  await pool.request().batch(`
    IF OBJECT_ID('stg.Cred_Tracker','U') IS NULL
    CREATE TABLE stg.Cred_Tracker (
      Assignment_Id       INT           NOT NULL PRIMARY KEY,
      Candidate_Name      NVARCHAR(200) NULL,
      Start_Date          DATE          NULL,
      Credentialer        NVARCHAR(200) NULL,
      Date_Confirmed      DATE          NULL,
      Initial_Start_Date  DATE          NULL,
      District            NVARCHAR(300) NULL,
      State               NVARCHAR(100) NULL,
      License_Cert        NVARCHAR(300) NULL,
      New_Rebook_Ext      NVARCHAR(50)  NULL,
      Last_Updated        DATE          NULL,
      Onboarding_Status   NVARCHAR(MAX) NULL,
      AM                  NVARCHAR(200) NULL,
      Recruiter           NVARCHAR(200) NULL,
      Lead                NVARCHAR(200) NULL,
      Updated_By          NVARCHAR(200) NULL,
      Updated_At          DATETIME2     NULL,
      Synced_At           DATETIME2     NULL
    );
  `)
}

const SELECT_COLUMNS = `
  Assignment_Id, Candidate_Name,
  CONVERT(char(10), Start_Date, 23)         AS Start_Date,
  Credentialer,
  CONVERT(char(10), Date_Confirmed, 23)     AS Date_Confirmed,
  CONVERT(char(10), Initial_Start_Date, 23) AS Initial_Start_Date,
  District, State, License_Cert, New_Rebook_Ext,
  CONVERT(char(10), Last_Updated, 23)       AS Last_Updated,
  Onboarding_Status, AM, Recruiter, Lead, Updated_By,
  CONVERT(varchar(33), Updated_At, 126)     AS Updated_At,
  CONVERT(varchar(33), Synced_At, 126)      AS Synced_At`

async function listRows(pool) {
  const r = await pool.request().query(
    `SELECT ${SELECT_COLUMNS} FROM stg.Cred_Tracker ORDER BY Assignment_Id DESC`)
  return r.recordset.map(normalizeCredRow)
}

async function getRow(pool, id) {
  const r = await pool.request().input('id', sql.Int, Number(id))
    .query(`SELECT ${SELECT_COLUMNS} FROM stg.Cred_Tracker WHERE Assignment_Id = @id`)
  return r.recordset.length ? normalizeCredRow(r.recordset[0]) : null
}

// dates passed as NVarChar; SQL Server implicitly converts ISO 'YYYY-MM-DD' to DATE.
function bindValue(req, name, col, value) {
  if (DATE_SET.has(col)) req.input(name, sql.NVarChar, value === '' || value == null ? null : String(value))
  else if (col === 'Assignment_Id') req.input(name, sql.Int, Number(value))
  else req.input(name, sql.NVarChar, value === '' || value == null ? null : String(value))
}

async function insertRow(pool, row) {
  const cols = ['Assignment_Id', 'Candidate_Name', 'Start_Date', 'Credentialer', 'Initial_Start_Date',
    'District', 'State', 'License_Cert', 'New_Rebook_Ext', 'AM', 'Recruiter']
  const req = pool.request()
  cols.forEach((c, i) => bindValue(req, `p${i}`, c, row[c]))
  const colList = cols.join(', ')
  const valList = cols.map((_, i) => `@p${i}`).join(', ')
  await req.query(
    `INSERT INTO stg.Cred_Tracker (${colList}, Synced_At) VALUES (${valList}, SYSUTCDATETIME())`)
}

async function refreshRow(pool, ref) {
  const cols = ['Candidate_Name', 'District', 'State', 'License_Cert', 'AM', 'Recruiter']
  const req = pool.request().input('id', sql.Int, ref.Assignment_Id)
  cols.forEach((c, i) => bindValue(req, `p${i}`, c, ref[c]))
  const sets = cols.map((c, i) => `${c} = @p${i}`).join(', ')
  await req.query(
    `UPDATE stg.Cred_Tracker SET ${sets}, Synced_At = SYSUTCDATETIME() WHERE Assignment_Id = @id`)
}

async function updateRow(pool, id, fields, updatedBy) {
  const picked = pickEditable(fields)
  if (!picked.length) return getRow(pool, id)
  const req = pool.request().input('id', sql.Int, Number(id))
  picked.forEach((p, i) => bindValue(req, `e${i}`, p.col, p.value))
  req.input('ub', sql.NVarChar, updatedBy || 'tracker-ui')
  const sets = picked.map((p, i) => `${p.col} = @e${i}`).join(', ')
  const result = await req.query(
    `UPDATE stg.Cred_Tracker SET ${sets}, Updated_By = @ub, Updated_At = SYSUTCDATETIME()
     WHERE Assignment_Id = @id`)
  if (!result.rowsAffected[0]) return null
  return getRow(pool, id)
}

async function deleteRow(pool, id) {
  const r = await pool.request().input('id', sql.Int, Number(id))
    .query('DELETE FROM stg.Cred_Tracker WHERE Assignment_Id = @id')
  return r.rowsAffected[0] > 0
}

async function fetchJson(url) {
  const res = await fetch(url)
  if (!res.ok) throw new Error(`${url} -> ${res.status}`)
  return res.json()
}

async function syncFromCockpit(pool, cockpitBase) {
  const base = cockpitBase.replace(/\/$/, '')
  const list = await fetchJson(`${base}/assignments`)
  const ids = (list?.assignment_ids ?? list ?? []).map(x => Number(x?.assignment_id ?? x)).filter(Boolean)

  // fetch agent2 + agent3 per id with small concurrency, skip failures
  const rows = []
  const CONC = 8
  for (let i = 0; i < ids.length; i += CONC) {
    const batch = ids.slice(i, i + CONC)
    const settled = await Promise.all(batch.map(async id => {
      try {
        const [a2, a3] = await Promise.all([
          fetchJson(`${base}/assignment/${id}/agent/2`).catch(() => null),
          fetchJson(`${base}/assignment/${id}/agent/3`).catch(() => null),
        ])
        if (!a2) return null
        const row = mapAgentToRow(a2, a3)
        return Number.isFinite(row.Assignment_Id) ? row : null
      } catch { return null }
    }))
    for (const r of settled) if (r) rows.push(r)
  }

  const existing = await pool.request().query('SELECT Assignment_Id FROM stg.Cred_Tracker')
  const existingIds = new Set(existing.recordset.map(r => r.Assignment_Id))
  const { toInsert, toRefresh } = buildUpsertPlan(rows, existingIds)
  for (const r of toInsert) await insertRow(pool, r)
  for (const r of toRefresh) await refreshRow(pool, r)
  return { synced: rows.length, inserted: toInsert.length, refreshed: toRefresh.length }
}

module.exports = {
  ensureCredTrackerTable, listRows, getRow, updateRow, deleteRow, syncFromCockpit,
}
```

- [ ] **Step 2: Verify the module loads (syntax check)**

Run: `cd excel-api && node -e "require('./credTracker.js'); console.log('ok')"`
Expected: prints `ok`

- [ ] **Step 3: Commit**

```bash
git add excel-api/credTracker.js
git commit -m "feat(tracker): Cred_Tracker DB layer + cockpit sync (upsert preserves edits)"
```

---

## Task 3: Wire excel-api routes

**Files:**
- Modify: `excel-api/index.js`

**Interfaces:**
- Consumes (Task 2): `ensureCredTrackerTable`, `listRows`, `getRow`, `updateRow`, `deleteRow`, `syncFromCockpit`.

- [ ] **Step 1: Add the import and JSON middleware**

In `excel-api/index.js`, after the existing `const { normalizeRow } = require('./normalize.js')` line, add:

```js
const credTracker = require('./credTracker.js')
```

After `app.use(cors())`, add:

```js
app.use(express.json())
const COCKPIT_API_BASE = process.env.COCKPIT_API_BASE || 'http://localhost:8001'
```

- [ ] **Step 2: Add the routes**

Insert before `app.listen(...)`:

```js
app.get('/cred-tracker', async (_req, res) => {
  try {
    const pool = await getPool()
    await credTracker.ensureCredTrackerTable(pool)
    res.json({ rows: await credTracker.listRows(pool) })
  } catch (e) {
    res.status(503).json({ error: 'Cred Tracker DB unavailable', detail: String(e.message || e) })
  }
})

app.get('/cred-tracker/:id', async (req, res) => {
  try {
    const pool = await getPool()
    await credTracker.ensureCredTrackerTable(pool)
    const row = await credTracker.getRow(pool, req.params.id)
    if (!row) return res.status(404).json({ error: 'not found' })
    res.json(row)
  } catch (e) {
    res.status(503).json({ error: 'Cred Tracker DB unavailable', detail: String(e.message || e) })
  }
})

app.post('/cred-tracker/sync', async (_req, res) => {
  let pool
  try { pool = await getPool(); await credTracker.ensureCredTrackerTable(pool) }
  catch (e) { return res.status(503).json({ error: 'Cred Tracker DB unavailable', detail: String(e.message || e) }) }
  try {
    const result = await credTracker.syncFromCockpit(pool, COCKPIT_API_BASE)
    res.json(result)
  } catch (e) {
    res.status(502).json({ error: 'Sync from cockpit failed', detail: String(e.message || e) })
  }
})

app.patch('/cred-tracker/:id', async (req, res) => {
  try {
    const pool = await getPool()
    await credTracker.ensureCredTrackerTable(pool)
    const { fields = {}, updated_by } = req.body || {}
    const row = await credTracker.updateRow(pool, req.params.id, fields, updated_by)
    if (!row) return res.status(404).json({ error: 'not found' })
    res.json(row)
  } catch (e) {
    res.status(503).json({ error: 'Cred Tracker update failed', detail: String(e.message || e) })
  }
})

app.delete('/cred-tracker/:id', async (req, res) => {
  try {
    const pool = await getPool()
    await credTracker.ensureCredTrackerTable(pool)
    const ok = await credTracker.deleteRow(pool, req.params.id)
    if (!ok) return res.status(404).json({ error: 'not found' })
    res.json({ deleted: true })
  } catch (e) {
    res.status(503).json({ error: 'Cred Tracker delete failed', detail: String(e.message || e) })
  }
})
```

- [ ] **Step 3: Manual smoke test (requires DB + cockpit :8001 running)**

Run: `cd excel-api && npm start` (in one terminal), then in another:

```bash
curl -s -X POST http://localhost:8002/cred-tracker/sync
curl -s http://localhost:8002/cred-tracker | head -c 400
curl -s -X PATCH http://localhost:8002/cred-tracker/<id> -H "Content-Type: application/json" -d '{"fields":{"lead":"Tina","onboarding_status":"docs pending"},"updated_by":"diyasha.kundu@aequor.com"}'
```

Expected: sync returns `{ synced, inserted, refreshed }`; list returns `{ rows: [...] }`; PATCH returns the updated row with `lead: "Tina"`. If no DB is available locally, note this and defer the smoke test — the routes are still committed.

- [ ] **Step 4: Commit**

```bash
git add excel-api/index.js
git commit -m "feat(tracker): mount /cred-tracker CRUD + sync routes"
```

---

## Task 4: Frontend react-query hooks

**Files:**
- Create: `src/api/credTracker.js`

**Interfaces:**
- Consumes (existing): `EXCEL_API_BASE` from `src/config.js`.
- Produces: `useCredTracker()`, `useSyncCredTracker()`, `useUpdateCredRow()`, `useDeleteCredRow()`.

- [ ] **Step 1: Write the module**

Create `src/api/credTracker.js`:

```js
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { EXCEL_API_BASE } from '../config.js'

const KEY = ['cred-tracker', 'rows']

async function jfetch(path, options) {
  const res = await fetch(`${EXCEL_API_BASE}${path}`, options)
  if (!res.ok) throw new Error(`Cred Tracker ${res.status}`)
  return res.json()
}

/** GET /cred-tracker → { rows: [...] } (reads stg.Cred_Tracker only). */
export function useCredTracker() {
  return useQuery({
    queryKey: KEY,
    queryFn: () => jfetch('/cred-tracker'),
    staleTime: 30_000,
    retry: 0,
  })
}

/** POST /cred-tracker/sync — pull agent data, upsert. Invalidates the list. */
export function useSyncCredTracker() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () => jfetch('/cred-tracker/sync', { method: 'POST' }),
    onSuccess: () => qc.invalidateQueries({ queryKey: KEY }),
  })
}

/** PATCH /cred-tracker/:id — update editable fields. */
export function useUpdateCredRow() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, fields, updated_by }) =>
      jfetch(`/cred-tracker/${id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ fields, updated_by }),
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: KEY }),
  })
}

/** DELETE /cred-tracker/:id. */
export function useDeleteCredRow() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id) => jfetch(`/cred-tracker/${id}`, { method: 'DELETE' }),
    onSuccess: () => qc.invalidateQueries({ queryKey: KEY }),
  })
}
```

- [ ] **Step 2: Commit**

```bash
git add src/api/credTracker.js
git commit -m "feat(tracker): react-query hooks for Cred_Tracker CRUD + sync"
```

---

## Task 5: Frontend column model + lib tests

**Files:**
- Create: `src/lib/credTracker.js`
- Test: `src/lib/__tests__/credTracker.test.js`

**Interfaces:**
- Produces: `CRED_COLUMNS` (15 entries), `EDITABLE_FIELDS` (7), `DATE_FIELDS` (Set), `buildCredRow(db)`.

- [ ] **Step 1: Write the failing test**

Create `src/lib/__tests__/credTracker.test.js`:

```js
import { describe, it, expect } from 'vitest'
import { CRED_COLUMNS, EDITABLE_FIELDS, buildCredRow } from '../credTracker.js'

describe('credTracker lib', () => {
  it('defines the 15 data columns in order', () => {
    expect(CRED_COLUMNS).toHaveLength(15)
    expect(CRED_COLUMNS[0].key).toBe('assignment_id')
    expect(CRED_COLUMNS.map(c => c.key)).toContain('onboarding_status')
  })

  it('marks exactly the 7 editable fields', () => {
    expect([...EDITABLE_FIELDS].sort()).toEqual(
      ['credentialer', 'date_confirmed', 'last_updated', 'lead', 'new_rebook_ext', 'onboarding_status', 'start_date'])
    for (const c of CRED_COLUMNS) {
      expect(c.editable).toBe(EDITABLE_FIELDS.includes(c.key))
    }
  })

  it('buildCredRow blanks null/undefined and keeps id', () => {
    const r = buildCredRow({ assignment_id: 7, candidate_name: 'Jane', state: null })
    expect(r.assignment_id).toBe(7)
    expect(r.candidate_name).toBe('Jane')
    expect(r.state).toBe('')
    expect(r.lead).toBe('')
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- src/lib/__tests__/credTracker.test.js`
Expected: FAIL — cannot resolve `../credTracker.js`

- [ ] **Step 3: Write the implementation**

Create `src/lib/credTracker.js`:

```js
// Column model for the Cred Tracker grid. React-free, unit-testable.

export const EDITABLE_FIELDS = [
  'start_date', 'credentialer', 'date_confirmed',
  'new_rebook_ext', 'last_updated', 'onboarding_status', 'lead',
]
export const DATE_FIELDS = new Set(['start_date', 'date_confirmed', 'initial_start_date', 'last_updated'])

export const CRED_COLUMNS = [
  { key: 'assignment_id',      label: 'ID',                editable: false, type: 'id' },
  { key: 'candidate_name',     label: 'Candidate',         editable: false, type: 'text' },
  { key: 'start_date',         label: 'Start Date',        editable: true,  type: 'date' },
  { key: 'credentialer',       label: 'Credentialer',      editable: true,  type: 'text' },
  { key: 'date_confirmed',     label: 'Date Confirmed',    editable: true,  type: 'date' },
  { key: 'initial_start_date', label: 'Initial Start',     editable: false, type: 'date' },
  { key: 'district',           label: 'District',          editable: false, type: 'text' },
  { key: 'state',              label: 'State',             editable: false, type: 'text' },
  { key: 'license_cert',       label: 'License/Cert',      editable: false, type: 'text' },
  { key: 'new_rebook_ext',     label: 'New/Rebook/Ext',    editable: true,  type: 'text' },
  { key: 'last_updated',       label: 'Last Updated',      editable: true,  type: 'date' },
  { key: 'onboarding_status',  label: 'Onboarding Status', editable: true,  type: 'textarea' },
  { key: 'am',                 label: 'AM',                editable: false, type: 'text' },
  { key: 'recruiter',          label: 'Recruiter',         editable: false, type: 'text' },
  { key: 'lead',               label: 'Lead',              editable: true,  type: 'text' },
]

/** Build a grid row from a normalized DB row; null/undefined → ''. */
export function buildCredRow(db) {
  const d = db || {}
  const row = {}
  for (const c of CRED_COLUMNS) row[c.key] = d[c.key] == null ? '' : String(d[c.key])
  row.assignment_id = d.assignment_id ?? null
  return row
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- src/lib/__tests__/credTracker.test.js`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add src/lib/credTracker.js src/lib/__tests__/credTracker.test.js
git commit -m "feat(tracker): Cred Tracker column model + lib tests"
```

---

## Task 6: Install table lib + scoped Lenis hook

**Files:**
- Modify: `package.json` (add `@tanstack/react-table`)
- Create: `src/hooks/useLenisScroll.js`

**Interfaces:**
- Produces: `useLenisScroll(ref)` — attaches a scoped Lenis instance to a scroll container.

- [ ] **Step 1: Install the dependency**

Run: `npm install @tanstack/react-table@^8`
Expected: `package.json` lists `@tanstack/react-table` under dependencies; install succeeds.

- [ ] **Step 2: Write the Lenis hook**

Create `src/hooks/useLenisScroll.js`:

```js
import { useEffect } from 'react'
import Lenis from 'lenis'

/** Scoped smooth-scroll on one container (vertical). Pass a ref to the scroll wrapper. */
export function useLenisScroll(wrapperRef) {
  useEffect(() => {
    const wrapper = wrapperRef.current
    if (!wrapper) return
    const content = wrapper.firstElementChild || wrapper
    const lenis = new Lenis({ wrapper, content, smoothWheel: true, duration: 0.9 })
    let raf
    const loop = (t) => { lenis.raf(t); raf = requestAnimationFrame(loop) }
    raf = requestAnimationFrame(loop)
    return () => { cancelAnimationFrame(raf); lenis.destroy() }
  }, [wrapperRef])
}
```

- [ ] **Step 3: Commit**

```bash
git add package.json package-lock.json src/hooks/useLenisScroll.js
git commit -m "chore(tracker): add @tanstack/react-table + scoped Lenis hook"
```

---

## Task 7: Rebuild TrackerPage UI

**Files:**
- Replace: `src/pages/TrackerPage.jsx`

**Interfaces:**
- Consumes: `useCredTracker`, `useSyncCredTracker`, `useUpdateCredRow`, `useDeleteCredRow` (Task 4); `CRED_COLUMNS`, `EDITABLE_FIELDS`, `DATE_FIELDS`, `buildCredRow` (Task 5); `useLenisScroll` (Task 6); `useTokens` (existing); `@tanstack/react-table`.

**During execution of this task, invoke the `frontend-design:frontend-design` skill** for visual treatment (typography scale, spacing rhythm, hover/press choreography) before finalizing styles. The code below is a complete, working baseline that satisfies all functional requirements; the design skill refines aesthetics on top of it without changing behavior.

- [ ] **Step 1: Write the component**

Replace `src/pages/TrackerPage.jsx` entirely with:

```jsx
import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { motion, AnimatePresence } from 'framer-motion'
import {
  useReactTable, getCoreRowModel, getSortedRowModel,
  getFilteredRowModel, getPaginationRowModel, flexRender,
} from '@tanstack/react-table'
import { Pencil, Trash2, Eye, Check, X, RefreshCw, ArrowUpDown, ArrowUp, ArrowDown } from 'lucide-react'
import { useTokens } from '../lib/theme.jsx'
import { useLenisScroll } from '../hooks/useLenisScroll.js'
import { CRED_COLUMNS, EDITABLE_FIELDS, DATE_FIELDS, buildCredRow } from '../lib/credTracker.js'
import {
  useCredTracker, useSyncCredTracker, useUpdateCredRow, useDeleteCredRow,
} from '../api/credTracker.js'

const currentUser = () =>
  (typeof localStorage !== 'undefined' && localStorage.getItem('user_email')) || 'credentialer'

export default function TrackerPage() {
  const t = useTokens()
  const navigate = useNavigate()
  const scrollRef = useRef(null)
  useLenisScroll(scrollRef)

  const { data, isLoading, isError } = useCredTracker()
  const sync = useSyncCredTracker()
  const update = useUpdateCredRow()
  const remove = useDeleteCredRow()

  // Auto-sync once on mount, then the list query refreshes.
  const synced = useRef(false)
  useEffect(() => {
    if (!synced.current) { synced.current = true; sync.mutate() }
  }, [sync])

  const rows = useMemo(() => (data?.rows || []).map(buildCredRow), [data])

  const [editingId, setEditingId] = useState(null)
  const [draft, setDraft] = useState({})
  const [sorting, setSorting] = useState([])
  const [columnFilters, setColumnFilters] = useState([])

  const startEdit = (row) => {
    setEditingId(row.assignment_id)
    const d = {}
    for (const k of EDITABLE_FIELDS) d[k] = row[k] ?? ''
    setDraft(d)
  }
  const cancelEdit = () => { setEditingId(null); setDraft({}) }
  const saveEdit = (id) => {
    update.mutate({ id, fields: draft, updated_by: currentUser() }, { onSuccess: cancelEdit })
  }
  const onRemove = (id) => {
    if (window.confirm(`Remove assignment ${id} from the tracker?`)) remove.mutate(id)
  }

  const columns = useMemo(() => {
    const dataCols = CRED_COLUMNS.map(c => ({
      accessorKey: c.key,
      header: c.label,
      enableColumnFilter: c.type !== 'id',
      cell: ({ row, getValue }) => {
        const isEditing = editingId === row.original.assignment_id
        if (isEditing && c.editable) {
          const common = {
            value: draft[c.key] ?? '',
            onChange: (e) => setDraft(d => ({ ...d, [c.key]: e.target.value })),
            onClick: (e) => e.stopPropagation(),
            className: 'w-full rounded-md px-2 py-1 text-[12px] outline-none',
            style: { background: t.inputBg, border: `1px solid ${t.accent}`, color: t.textStrong },
          }
          if (c.type === 'date') return <input type="date" {...common} />
          if (c.type === 'textarea') return <input type="text" {...common} />
          return <input type="text" {...common} />
        }
        const v = getValue()
        if (c.type === 'id') {
          return <span style={{ fontFamily: 'JetBrains Mono,monospace', color: t.muted }}>#{v}</span>
        }
        if (DATE_FIELDS.has(c.key) && v) {
          return <span style={{ fontFamily: 'JetBrains Mono,monospace' }}>{v}</span>
        }
        return v || <span style={{ color: t.muted }}>—</span>
      },
    }))

    const actionsCol = {
      id: 'actions', header: 'Actions', enableSorting: false, enableColumnFilter: false,
      cell: ({ row }) => {
        const id = row.original.assignment_id
        const isEditing = editingId === id
        const btn = (extra) => ({
          className: 'inline-flex items-center justify-center w-7 h-7 rounded-lg transition-all duration-150',
          onMouseEnter: e => { e.currentTarget.style.transform = 'translateY(-1px)' },
          onMouseLeave: e => { e.currentTarget.style.transform = '' },
          ...extra,
        })
        if (isEditing) {
          return (
            <div className="flex items-center gap-1.5" onClick={e => e.stopPropagation()}>
              <button {...btn({ onClick: () => saveEdit(id), title: 'Save' })}
                style={{ background: 'rgba(31,138,76,0.14)', color: '#1F8A4C' }}><Check size={15} /></button>
              <button {...btn({ onClick: cancelEdit, title: 'Cancel' })}
                style={{ background: 'rgba(192,57,43,0.12)', color: '#C0392B' }}><X size={15} /></button>
            </div>
          )
        }
        return (
          <div className="flex items-center gap-1.5" onClick={e => e.stopPropagation()}>
            <button {...btn({ onClick: () => navigate(`/review/${id}`), title: 'Review' })}
              style={{ background: t.tagBg, color: t.accent }}><Eye size={15} /></button>
            <button {...btn({ onClick: () => startEdit(row.original), title: 'Edit' })}
              style={{ background: t.tagBg, color: t.accentSky }}><Pencil size={14} /></button>
            <button {...btn({ onClick: () => onRemove(id), title: 'Remove' })}
              style={{ background: 'rgba(192,57,43,0.10)', color: '#C0392B' }}><Trash2 size={14} /></button>
          </div>
        )
      },
    }
    return [...dataCols, actionsCol]
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [editingId, draft, t])

  const table = useReactTable({
    data: rows,
    columns,
    state: { sorting, columnFilters },
    onSortingChange: setSorting,
    onColumnFiltersChange: setColumnFilters,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
    initialState: { pagination: { pageSize: 25 } },
  })

  if (isError) {
    return (
      <div className="flex items-center justify-center h-[60vh] text-sm"
        style={{ color: t.muted, fontFamily: 'Geist,sans-serif' }}>
        Cred Tracker DB unavailable — is the Excel service (:8002) running?
      </div>
    )
  }

  const pageRows = table.getRowModel().rows

  return (
    <div className="flex flex-col h-full gap-3 px-6 py-5" style={{ fontFamily: 'Geist,sans-serif' }}>
      {/* Header */}
      <div className="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <h1 className="m-0 font-bold tracking-tight"
            style={{ fontSize: 22, color: t.textStrong, letterSpacing: '-0.01em' }}>
            Onboarding Tracker
          </h1>
          <p className="mt-1 text-[11px]" style={{ color: t.muted }}>
            {rows.length} tracked assignments · sortable &amp; filterable · click ✏️ to edit a row inline.
          </p>
        </div>
        <button
          onClick={() => sync.mutate()}
          disabled={sync.isPending}
          className="inline-flex items-center gap-2 px-3.5 py-2 rounded-xl text-[12px] font-semibold transition-all duration-150 btn-press"
          style={{ background: t.tagBg, color: t.accent, border: `1px solid ${t.tagBorder}`, cursor: sync.isPending ? 'wait' : 'pointer' }}>
          <RefreshCw size={14} className={sync.isPending ? 'animate-spin' : ''} />
          {sync.isPending ? 'Syncing…' : 'Sync'}
        </button>
      </div>

      {/* Table card */}
      <div className="flex-1 min-h-0 rounded-2xl overflow-hidden"
        style={{ background: t.cardBg, border: `1px solid ${t.cardBorder}`, boxShadow: t.cardShadow }}>
        <div ref={scrollRef} className="h-full overflow-auto" data-lenis-prevent>
          <table className="w-full border-collapse text-[12.5px]" style={{ color: t.text }}>
            <thead className="sticky top-0 z-10" style={{ background: t.isDark ? '#0E1524' : '#F1F5FB' }}>
              {table.getHeaderGroups().map(hg => (
                <tr key={hg.id}>
                  {hg.headers.map(header => {
                    const canSort = header.column.getCanSort()
                    const sorted = header.column.getIsSorted()
                    const canFilter = header.column.getCanFilter()
                    return (
                      <th key={header.id} className="text-left px-3 py-2.5 font-semibold whitespace-nowrap align-top"
                        style={{ color: t.label, borderBottom: `1px solid ${t.cardBorder}` }}>
                        <div
                          className={`flex items-center gap-1.5 ${canSort ? 'cursor-pointer select-none' : ''}`}
                          onClick={canSort ? header.column.getToggleSortingHandler() : undefined}>
                          {flexRender(header.column.columnDef.header, header.getContext())}
                          {canSort && (sorted === 'asc' ? <ArrowUp size={12} />
                            : sorted === 'desc' ? <ArrowDown size={12} />
                            : <ArrowUpDown size={12} style={{ opacity: 0.4 }} />)}
                        </div>
                        {canFilter && (
                          <input
                            value={header.column.getFilterValue() ?? ''}
                            onChange={e => header.column.setFilterValue(e.target.value)}
                            onClick={e => e.stopPropagation()}
                            placeholder="filter…"
                            className="mt-1.5 w-full rounded-md px-2 py-1 text-[11px] font-normal outline-none"
                            style={{ background: t.inputBg, border: `1px solid ${t.inputBorder}`, color: t.text }}
                          />
                        )}
                      </th>
                    )
                  })}
                </tr>
              ))}
            </thead>
            <tbody>
              <AnimatePresence initial={false}>
                {isLoading && rows.length === 0 && Array.from({ length: 8 }).map((_, i) => (
                  <tr key={`sk-${i}`}>
                    {columns.map((_, j) => (
                      <td key={j} className="px-3 py-3" style={{ borderBottom: `1px solid ${t.divider}` }}>
                        <div className="skeleton h-3 rounded" />
                      </td>
                    ))}
                  </tr>
                ))}
                {pageRows.map((row, i) => {
                  const isEditing = editingId === row.original.assignment_id
                  return (
                    <motion.tr key={row.original.assignment_id}
                      initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }}
                      transition={{ duration: 0.18, delay: Math.min(i, 12) * 0.012 }}
                      onClick={() => !isEditing && navigate(`/review/${row.original.assignment_id}`)}
                      style={{
                        cursor: isEditing ? 'default' : 'pointer',
                        background: isEditing ? (t.isDark ? 'rgba(91,168,255,0.07)' : 'rgba(30,111,224,0.05)') : 'transparent',
                      }}
                      onMouseEnter={e => { if (!isEditing) e.currentTarget.style.background = t.isDark ? 'rgba(91,168,255,0.05)' : 'rgba(30,111,224,0.035)' }}
                      onMouseLeave={e => { if (!isEditing) e.currentTarget.style.background = 'transparent' }}>
                      {row.getVisibleCells().map(cell => (
                        <td key={cell.id} className="px-3 py-2.5 whitespace-nowrap align-middle"
                          style={{ borderBottom: `1px solid ${t.divider}` }}>
                          {flexRender(cell.column.columnDef.cell, cell.getContext())}
                        </td>
                      ))}
                    </motion.tr>
                  )
                })}
              </AnimatePresence>
              {!isLoading && rows.length === 0 && (
                <tr><td colSpan={columns.length} className="px-3 py-10 text-center text-[13px]" style={{ color: t.muted }}>
                  No tracked assignments yet — run a sync.
                </td></tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Pagination */}
      <div className="flex items-center justify-between gap-2 text-[11px]" style={{ color: t.muted }}>
        <span>
          {table.getFilteredRowModel().rows.length} rows
          {table.getFilteredRowModel().rows.length !== rows.length && ` (of ${rows.length})`}
        </span>
        <div className="flex items-center gap-2">
          <PageBtn t={t} disabled={!table.getCanPreviousPage()} onClick={() => table.previousPage()}>← Prev</PageBtn>
          <span style={{ fontFamily: 'JetBrains Mono,monospace' }}>
            {table.getState().pagination.pageIndex + 1} / {Math.max(1, table.getPageCount())}
          </span>
          <PageBtn t={t} disabled={!table.getCanNextPage()} onClick={() => table.nextPage()}>Next →</PageBtn>
          <select
            value={table.getState().pagination.pageSize}
            onChange={e => table.setPageSize(Number(e.target.value))}
            className="rounded-lg px-2 py-1 text-[11px] outline-none"
            style={{ background: t.inputBg, border: `1px solid ${t.inputBorder}`, color: t.text }}>
            {[25, 50, 100].map(s => <option key={s} value={s}>{s}/page</option>)}
          </select>
        </div>
      </div>
    </div>
  )
}

function PageBtn({ t, disabled, onClick, children }) {
  return (
    <button onClick={onClick} disabled={disabled}
      className="px-2.5 py-1 rounded-lg btn-press"
      style={{
        border: `1px solid ${t.cardBorder}`, background: 'transparent', color: t.text,
        cursor: disabled ? 'not-allowed' : 'pointer', opacity: disabled ? 0.45 : 1,
      }}>
      {children}
    </button>
  )
}
```

- [ ] **Step 2: Verify it builds / lints**

Run: `npm run lint`
Expected: no new errors in `src/pages/TrackerPage.jsx`, `src/hooks/useLenisScroll.js`, `src/api/credTracker.js`, `src/lib/credTracker.js`.

- [ ] **Step 3: Apply frontend-design polish**

Invoke `frontend-design:frontend-design`. Refine (without changing behavior or breaking tests): header hierarchy, sticky-header contrast, row density, the edit-row highlight, and button choreography. Keep all styling in Tailwind + `useTokens()` tokens.

- [ ] **Step 4: Commit**

```bash
git add src/pages/TrackerPage.jsx
git commit -m "feat(tracker): redesigned DB-backed table — sort/filter/paginate, inline edit, Lenis, framer-motion"
```

---

## Task 8: Frontend TrackerPage tests

**Files:**
- Replace: `src/pages/__tests__/TrackerPage.test.jsx`

**Interfaces:**
- Consumes: mocked `../../api/credTracker.js`, the real `TrackerPage`.

- [ ] **Step 1: Write the tests**

Replace `src/pages/__tests__/TrackerPage.test.jsx` with:

```jsx
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, fireEvent, within } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { renderWithProviders } from '../../test-utils/render.jsx'

const navigate = vi.fn()
vi.mock('react-router-dom', async (orig) => ({ ...(await orig()), useNavigate: () => navigate }))

const syncMutate = vi.fn()
const updateMutate = vi.fn()
const deleteMutate = vi.fn()
vi.mock('../../api/credTracker.js', () => ({
  useCredTracker: () => ({
    data: { rows: [
      { assignment_id: 149035, candidate_name: 'Jane Doe', start_date: '2026-08-18',
        credentialer: 'Sophia Gray', district: 'Twin Rivers USD', state: 'California',
        license_cert: 'Paraprofessional (PARA)', new_rebook_ext: 'Rebook', lead: '',
        onboarding_status: '', am: '', recruiter: 'Kristin Gergen' },
    ] }, isLoading: false, isError: false,
  }),
  useSyncCredTracker: () => ({ mutate: syncMutate, isPending: false }),
  useUpdateCredRow: () => ({ mutate: updateMutate }),
  useDeleteCredRow: () => ({ mutate: deleteMutate }),
}))

// Lenis touches the DOM/raf — stub it.
vi.mock('../../hooks/useLenisScroll.js', () => ({ useLenisScroll: () => {} }))

import TrackerPage from '../TrackerPage.jsx'

const renderPage = () => renderWithProviders(<MemoryRouter><TrackerPage /></MemoryRouter>)

describe('TrackerPage (Cred Tracker)', () => {
  beforeEach(() => { syncMutate.mockClear(); updateMutate.mockClear(); deleteMutate.mockClear(); navigate.mockClear() })

  it('auto-syncs on mount and renders rows', () => {
    renderPage()
    expect(syncMutate).toHaveBeenCalled()
    expect(screen.getByText(/Onboarding Tracker/i)).toBeInTheDocument()
    expect(screen.getByText('Jane Doe')).toBeInTheDocument()
    expect(screen.getByText('Kristin Gergen')).toBeInTheDocument()
  })

  it('Edit turns editable cells into inputs; non-editable stay static', () => {
    renderPage()
    fireEvent.click(screen.getByTitle('Edit'))
    // editable: lead becomes an input (empty value)
    expect(screen.getByDisplayValue('Sophia Gray')).toBeInTheDocument() // credentialer editable
    expect(screen.getByDisplayValue('2026-08-18')).toBeInTheDocument()  // start_date editable (date)
    // non-editable: recruiter stays as text, not an input
    expect(screen.queryByDisplayValue('Kristin Gergen')).toBeNull()
    expect(screen.getByText('Kristin Gergen')).toBeInTheDocument()
  })

  it('Save calls update with edited fields only', () => {
    renderPage()
    fireEvent.click(screen.getByTitle('Edit'))
    fireEvent.change(screen.getByDisplayValue('Sophia Gray'), { target: { value: 'New Cred' } })
    fireEvent.click(screen.getByTitle('Save'))
    expect(updateMutate).toHaveBeenCalledTimes(1)
    const arg = updateMutate.mock.calls[0][0]
    expect(arg.id).toBe(149035)
    expect(arg.fields.credentialer).toBe('New Cred')
    // only editable keys present
    expect(Object.keys(arg.fields).sort()).toEqual(
      ['credentialer', 'date_confirmed', 'last_updated', 'lead', 'new_rebook_ext', 'onboarding_status', 'start_date'])
    expect('recruiter' in arg.fields).toBe(false)
  })

  it('Remove confirms then calls delete', () => {
    const confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(true)
    renderPage()
    fireEvent.click(screen.getByTitle('Remove'))
    expect(confirmSpy).toHaveBeenCalled()
    expect(deleteMutate).toHaveBeenCalledWith(149035)
    confirmSpy.mockRestore()
  })

  it('Review navigates to the review page', () => {
    renderPage()
    fireEvent.click(screen.getByTitle('Review'))
    expect(navigate).toHaveBeenCalledWith('/review/149035')
  })
})
```

- [ ] **Step 2: Run the tests**

Run: `npm test -- src/pages/__tests__/TrackerPage.test.jsx`
Expected: PASS (5 tests). If the row-click handler interferes with a button click, the button handlers call `e.stopPropagation()` — verify that's present (it is in Task 7).

- [ ] **Step 3: Run the full suite**

Run: `npm test`
Expected: all tests pass (no regressions from removing the AG-Grid tracker).

- [ ] **Step 4: Commit**

```bash
git add src/pages/__tests__/TrackerPage.test.jsx
git commit -m "test(tracker): Cred Tracker UI — render, inline edit, save/remove/review"
```

---

## Self-Review Notes

- **Spec coverage:** table `stg.Cred_Tracker` (Task 2 DDL); 18 columns incl. Review/Edit/Remove (Tasks 5,7); agent-sourced vs editable split (Tasks 1,5); CRUD in excel-api (Tasks 2,3); auto-sync on load (Task 7 Step 1); audit `Updated_By/At` (Task 2 `updateRow`); dark/light + Tailwind + Lenis + framer-motion + pagination + inline edit (Tasks 6,7); tests (Tasks 1,5,8). All present.
- **Old code removal:** `src/lib/tracker.js` and its test stay in the repo (harmless, no longer imported by TrackerPage). Leaving them avoids breaking `src/lib/__tests__/tracker.test.js`. If a reviewer wants them gone, that's a trivial follow-up — out of scope here.
- **Cleaning rule:** `clean()` strips `MISSING:`/`REDACT`; verified by Task 1 tests.
- **Known soft spot:** the agent-2 `verifier.checks` location for the real candidate name is handled defensively (checks both `output.verifier` and top-level `verifier`, falls back to non-redacted `candidate_name`, else null). Confirm against the live endpoint during Task 3 smoke test.
- **updated_by source:** UI sends `localStorage.user_email` or `'credentialer'`. If the app has a real auth/user context, wire it in Task 7 Step 3; not a blocker.

# Background Batch Pipeline Runs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user pick 1–10 assignments (new or done) on the Run Pipeline page and run the full agent pipeline for them, with the run continuing in the background across navigation and full browser refresh, an Abort ("Stop watching") control, and auto-sync into the Tracker on completion — plus fix the Tracker vertical scroll.

**Architecture:** A global `RunProvider` mounted above the router owns the batch `jobId` + SSE-derived state, so navigation/unmount never kills the live view; it re-attaches a still-running job on load via `GET /jobs`. The Run Pipeline page is just a view of that state (picker when idle, live view when running). SSE event reduction is a pure tested function.

**Tech Stack:** React 19, react-query, framer-motion, lenis, Tailwind v4, vitest. Cockpit API `POST /run` `{ids,wipe,reread,backup}`→`{job_id}`, SSE `/stream/:job`, `GET /jobs`. Cred Tracker sync `POST {EXCEL_API_BASE}/cred-tracker/sync`.

## Global Constraints

- All styling in Tailwind + `useTokens()` tokens (dark/light). Brand accents `#5BA8FF` (dark) / `#1E6FE0` (light). Geist / JetBrains Mono fonts. No GSAP.
- Selection is hard-capped at **10**; an 11th cannot be selected.
- Abort is **frontend "Stop watching" only** — it never calls a backend cancel (none exists). Label it honestly.
- The provider must live ABOVE the router (in `main.jsx`), inside `QueryClientProvider` and `ConsoleModeProvider`.
- On `job_complete`, POST `{EXCEL_API_BASE}/cred-tracker/sync` (best-effort) and invalidate the `['cred-tracker','rows']` query.
- Terminal SSE events: `job_complete`, `job_failed`.
- localStorage key for the active run: `acap.activeRun` holding `{ job_id, ids }`.
- Frontend tests: vitest (`npm test`). Reuse existing patterns (`renderWithProviders`, mocked hooks).

---

## File Structure

- `src/run/sseReducer.js` (NEW) — pure `INITIAL_SSE_STATE` + `reduceSseEvent(state, type, data)`; `TERMINAL_EVENTS`.
- `src/run/__tests__/sseReducer.test.js` (NEW) — reducer unit tests.
- `src/run/RunProvider.jsx` (NEW) — context, SSE subscription, `startRun`/`stopWatching`/resume, completion→sync; `useRunState()`.
- `src/run/__tests__/RunProvider.test.jsx` (NEW) — provider behavior with mocked fetch/SSE.
- `src/main.jsx` (MODIFY) — wrap `<App/>` with `<RunProvider>`.
- `src/components/run/AssignmentPicker.jsx` (NEW) — selectable list, cap 10, Confirm & Run.
- `src/components/run/__tests__/AssignmentPicker.test.jsx` (NEW).
- `src/components/run/RunLiveView.jsx` (NEW) — live progress + Stop watching + done summary.
- `src/pages/RunPage.jsx` (REWRITE) — picker (idle) vs live view (active).
- `src/components/shell/TopBar.jsx` (MODIFY) — "pipeline running" pill.
- `src/pages/TrackerPage.jsx` (MODIFY) — scroll fix (one line).

---

## Task 1: SSE event reducer (pure)

**Files:**
- Create: `src/run/sseReducer.js`
- Test: `src/run/__tests__/sseReducer.test.js`

**Interfaces:**
- Produces:
  - `INITIAL_SSE_STATE` → `{ status:'running', events:[], agentsByAid:{}, logLines:[], results:[] }`
  - `reduceSseEvent(state, type, data) -> newState`
  - `TERMINAL_EVENTS` → `Set(['job_complete','job_failed'])`

- [ ] **Step 1: Write the failing test**

Create `src/run/__tests__/sseReducer.test.js`:

```js
import { describe, it, expect } from 'vitest'
import { INITIAL_SSE_STATE, reduceSseEvent, TERMINAL_EVENTS } from '../sseReducer.js'

const run = (events) => events.reduce((s, [type, data]) => reduceSseEvent(s, type, data), INITIAL_SSE_STATE)

describe('reduceSseEvent', () => {
  it('accumulates agent events per assignment id', () => {
    const s = run([
      ['agent_1_complete', { assignment_id: 149035, duration_s: 1.2 }],
      ['agent_2_complete', { assignment_id: 149035 }],
      ['agent_1_complete', { assignment_id: 149036 }],
    ])
    expect(s.agentsByAid['149035']).toHaveLength(2)
    expect(s.agentsByAid['149036']).toHaveLength(1)
    // each agent event also logs a labelled line
    expect(s.logLines.some(l => l.includes('Agent 1'))).toBe(true)
  })

  it('appends assignment_done to results', () => {
    const s = run([['assignment_done', { assignment_id: 149035, ready: true }]])
    expect(s.results).toHaveLength(1)
    expect(s.results[0].assignment_id).toBe(149035)
  })

  it('sets terminal status on job_complete / job_failed', () => {
    expect(reduceSseEvent(INITIAL_SSE_STATE, 'job_complete', {}).status).toBe('done')
    expect(reduceSseEvent(INITIAL_SSE_STATE, 'job_failed', {}).status).toBe('failed')
  })

  it('caps log lines at 1000', () => {
    let s = INITIAL_SSE_STATE
    for (let i = 0; i < 1100; i++) s = reduceSseEvent(s, 'log', { line: `l${i}` })
    expect(s.logLines.length).toBe(1000)
    expect(s.logLines[s.logLines.length - 1]).toBe('l1099')
  })

  it('TERMINAL_EVENTS lists the two terminal events', () => {
    expect([...TERMINAL_EVENTS].sort()).toEqual(['job_complete', 'job_failed'])
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- src/run/__tests__/sseReducer.test.js`
Expected: FAIL — cannot resolve `../sseReducer.js`

- [ ] **Step 3: Write the implementation**

Create `src/run/sseReducer.js`:

```js
// Pure reduction of pipeline SSE events into view state. No React, no sockets —
// unit-testable. Mirrors the event handling that used to live in useSSE.js.
import { sseLine } from '../lib/sse.js'

const MAX_LOG_LINES = 1000

const AGENT_LOG_LABELS = {
  agent_1_complete:   'Agent 1 — Document Scan',
  agent_2_complete:   'Agent 2 — Assignment Parser',
  agent_3_complete:   'Agent 3 — Requirement Mapper',
  agent_4_complete:   'Agent 4 — Document Matcher',
  agent_5_complete:   'Agent 5 — Checklist Builder',
  agent_5_5_complete: 'Agent 5.5 — Triage Gate',
  agent_6_complete:   'Agent 6 — Final Reviewer',
}

export const TERMINAL_EVENTS = new Set(['job_complete', 'job_failed'])

export const INITIAL_SSE_STATE = {
  status: 'running',          // running | done | failed
  events: [],
  agentsByAid: {},
  logLines: [],
  results: [],
}

function pushLog(logLines, line) {
  const next = [...logLines, line]
  return next.length > MAX_LOG_LINES ? next.slice(-MAX_LOG_LINES) : next
}

/** Normalize an assignment id (backend may send number, string, or nested object). */
function normalizeAid(raw) {
  if (raw == null) return null
  if (typeof raw === 'object') return String(raw.id ?? raw.assignment_id ?? Object.values(raw)[0] ?? raw)
  return String(raw)
}

/** Reduce one SSE event into new state. Returns a new object (never mutates). */
export function reduceSseEvent(state, type, data = {}) {
  switch (type) {
    case 'batch_start':
    case 'assignment_start':
      return { ...state, events: [...state.events, { type, ...data }] }
    case 'log':
      return { ...state, logLines: pushLog(state.logLines, sseLine(data)) }
    case 'assignment_done':
      return {
        ...state,
        results: [...state.results, data],
        events: [...state.events, { type, ...data }],
      }
    case 'assignment_failed':
      return { ...state, events: [...state.events, { type, ...data }] }
    case 'job_complete':
      return { ...state, status: 'done', events: [...state.events, { type, ...data }] }
    case 'job_failed':
      return { ...state, status: 'failed', events: [...state.events, { type, ...data }] }
    default:
      if (type.startsWith('agent_')) {
        const aid = normalizeAid(data.assignment_id)
        let next = { ...state, events: [...state.events, { type, ...data }] }
        if (aid) {
          next.agentsByAid = { ...state.agentsByAid, [aid]: [...(state.agentsByAid[aid] ?? []), { type, ...data }] }
        }
        const label = AGENT_LOG_LABELS[type]
        if (label) {
          const dur = data.duration_s != null ? ` (${Number(data.duration_s).toFixed(1)}s)` : ''
          const idTag = aid ? ` [#${aid}]` : ''
          next.logLines = pushLog(state.logLines, `✓ ${label}${dur}${idTag}`)
        }
        return next
      }
      return state
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- src/run/__tests__/sseReducer.test.js`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add src/run/sseReducer.js src/run/__tests__/sseReducer.test.js
git commit -m "feat(run): pure SSE event reducer for pipeline run state"
```

---

## Task 2: RunProvider (global background run state)

**Files:**
- Create: `src/run/RunProvider.jsx`
- Modify: `src/main.jsx`
- Test: `src/run/__tests__/RunProvider.test.jsx`

**Interfaces:**
- Consumes (Task 1): `INITIAL_SSE_STATE`, `reduceSseEvent`, `TERMINAL_EVENTS`.
- Consumes (existing): `openSSE` from `src/lib/sse.js`; `apiClient` from `src/lib/apiClient.js`; `EXCEL_API_BASE` from `src/config.js`; `useQueryClient` from `@tanstack/react-query`.
- Produces: `RunProvider` component; `useRunState()` → `{ jobId, status, events, agentsByAid, logLines, results, selectedIds, startedAt, error, isRunning, startRun(ids, opts?), stopWatching() }`.

- [ ] **Step 1: Write the failing test**

Create `src/run/__tests__/RunProvider.test.jsx`:

```jsx
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen, act, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

// Mock the cockpit apiClient (POST /run, GET /jobs)
const post = vi.fn()
const get = vi.fn()
vi.mock('../../lib/apiClient.js', () => ({ apiClient: { post: (...a) => post(...a), get: (...a) => get(...a) } }))

// Mock the SSE opener — capture handlers so the test can emit events
let sseHandlers = null
const closeSSE = vi.fn()
vi.mock('../../lib/sse.js', async (orig) => ({
  ...(await orig()),
  openSSE: (jobId, handlers) => { sseHandlers = handlers; return closeSSE },
}))

import { RunProvider, useRunState } from '../RunProvider.jsx'

function Probe() {
  const r = useRunState()
  return (
    <div>
      <span data-testid="status">{r.status}</span>
      <span data-testid="job">{r.jobId ?? ''}</span>
      <span data-testid="sel">{r.selectedIds.join(',')}</span>
      <button onClick={() => r.startRun(['149035', '149036'])}>start</button>
      <button onClick={() => r.stopWatching()}>stop</button>
    </div>
  )
}

const renderProvider = () => {
  const qc = new QueryClient()
  return render(<QueryClientProvider client={qc}><RunProvider><Probe /></RunProvider></QueryClientProvider>)
}

describe('RunProvider', () => {
  beforeEach(() => {
    post.mockReset(); get.mockReset(); closeSSE.mockReset(); sseHandlers = null
    localStorage.clear()
    get.mockResolvedValue({ jobs: [] })            // no running job on load
    global.fetch = vi.fn().mockResolvedValue({ ok: true, json: async () => ({}) })
  })

  it('startRun posts ids, opens the stream, and goes running', async () => {
    post.mockResolvedValue({ job_id: 'job-1' })
    renderProvider()
    await act(async () => { screen.getByText('start').click() })
    expect(post).toHaveBeenCalledWith('/run', expect.objectContaining({ ids: ['149035', '149036'] }))
    await waitFor(() => expect(screen.getByTestId('status').textContent).toBe('running'))
    expect(screen.getByTestId('job').textContent).toBe('job-1')
    expect(JSON.parse(localStorage.getItem('acap.activeRun')).job_id).toBe('job-1')
  })

  it('job_complete triggers a cred-tracker sync and goes done', async () => {
    post.mockResolvedValue({ job_id: 'job-1' })
    renderProvider()
    await act(async () => { screen.getByText('start').click() })
    await waitFor(() => expect(sseHandlers).toBeTruthy())
    await act(async () => { sseHandlers.job_complete({}) })
    await waitFor(() => expect(screen.getByTestId('status').textContent).toBe('done'))
    expect(global.fetch).toHaveBeenCalledWith(expect.stringContaining('/cred-tracker/sync'), expect.objectContaining({ method: 'POST' }))
  })

  it('stopWatching closes the stream and resets to idle', async () => {
    post.mockResolvedValue({ job_id: 'job-1' })
    renderProvider()
    await act(async () => { screen.getByText('start').click() })
    await waitFor(() => expect(screen.getByTestId('status').textContent).toBe('running'))
    await act(async () => { screen.getByText('stop').click() })
    expect(screen.getByTestId('status').textContent).toBe('idle')
    expect(localStorage.getItem('acap.activeRun')).toBeNull()
  })

  it('on load, adopts a still-running job from GET /jobs', async () => {
    get.mockResolvedValue({ jobs: [{ job_id: 'job-9', last_event: 'agent_2_complete', metadata: { assignment_ids: ['149040'] } }] })
    renderProvider()
    await waitFor(() => expect(screen.getByTestId('job').textContent).toBe('job-9'))
    expect(screen.getByTestId('status').textContent).toBe('running')
    expect(screen.getByTestId('sel').textContent).toBe('149040')
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- src/run/__tests__/RunProvider.test.jsx`
Expected: FAIL — cannot resolve `../RunProvider.jsx`

- [ ] **Step 3: Write the implementation**

Create `src/run/RunProvider.jsx`:

```jsx
import { createContext, useContext, useReducer, useRef, useEffect, useCallback } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { openSSE } from '../lib/sse.js'
import { apiClient } from '../lib/apiClient.js'
import { EXCEL_API_BASE } from '../config.js'
import { INITIAL_SSE_STATE, reduceSseEvent, TERMINAL_EVENTS } from './sseReducer.js'

const RunCtx = createContext(null)
const STORAGE_KEY = 'acap.activeRun'

const INITIAL = {
  jobId: null, status: 'idle',           // idle | running | done | failed
  events: [], agentsByAid: {}, logLines: [], results: [],
  selectedIds: [], startedAt: null, error: '',
}

function reducer(state, action) {
  switch (action.kind) {
    case 'start':
      return { ...INITIAL, status: 'running', jobId: action.jobId, selectedIds: action.ids, startedAt: action.startedAt }
    case 'attach':
      return { ...INITIAL, status: 'running', jobId: action.jobId, selectedIds: action.ids }
    case 'stop':
      return { ...INITIAL }
    case 'error':
      return { ...state, status: 'failed', error: action.error }
    case 'sse': {
      const next = reduceSseEvent(
        { status: state.status === 'idle' ? 'running' : state.status, events: state.events, agentsByAid: state.agentsByAid, logLines: state.logLines, results: state.results },
        action.type, action.data,
      )
      return { ...state, ...next }
    }
    default:
      return state
  }
}

export function RunProvider({ children }) {
  const [state, dispatch] = useReducer(reducer, INITIAL)
  const qc = useQueryClient()
  const closeRef = useRef(null)
  const syncedRef = useRef(false)

  // Open/replace the SSE subscription whenever the active jobId changes.
  useEffect(() => {
    if (!state.jobId) return
    syncedRef.current = false
    const close = openSSE(state.jobId, {
      '*': (type, data) => dispatch({ kind: 'sse', type, data }),
    }, () => dispatch({ kind: 'error', error: 'stream error' }))
    closeRef.current = close
    return () => { close?.(); if (closeRef.current === close) closeRef.current = null }
  }, [state.jobId])

  // On completion: sync the Cred Tracker (best-effort) + clear the persisted run.
  useEffect(() => {
    if (state.status === 'done' && !syncedRef.current) {
      syncedRef.current = true
      fetch(`${EXCEL_API_BASE}/cred-tracker/sync`, { method: 'POST' })
        .then(() => qc.invalidateQueries({ queryKey: ['cred-tracker', 'rows'] }))
        .catch(() => {})
      try { localStorage.removeItem(STORAGE_KEY) } catch { /* ignore */ }
    }
  }, [state.status, qc])

  // On load: re-attach a still-running job (survives full browser refresh).
  useEffect(() => {
    let cancelled = false
    ;(async () => {
      let saved = null
      try { saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null') } catch { /* ignore */ }
      try {
        const { jobs = [] } = await apiClient.get('/jobs')
        const running = jobs.find(j => j.job_id === saved?.job_id && !TERMINAL_EVENTS.has(j.last_event))
          || jobs.find(j => !TERMINAL_EVENTS.has(j.last_event))
        if (cancelled) return
        if (running) {
          dispatch({ kind: 'attach', jobId: running.job_id, ids: running.metadata?.assignment_ids ?? saved?.ids ?? [] })
        } else {
          try { localStorage.removeItem(STORAGE_KEY) } catch { /* ignore */ }
        }
      } catch { /* offline / no jobs endpoint — stay idle */ }
    })()
    return () => { cancelled = true }
  }, [])

  const startRun = useCallback(async (ids, opts = {}) => {
    const res = await apiClient.post('/run', { ids, wipe: false, reread: false, backup: true, ...opts })
    if (res?.job_id) {
      try { localStorage.setItem(STORAGE_KEY, JSON.stringify({ job_id: res.job_id, ids })) } catch { /* ignore */ }
      dispatch({ kind: 'start', jobId: res.job_id, ids, startedAt: Date.now() })
    }
    return res
  }, [])

  const stopWatching = useCallback(() => {
    if (closeRef.current) { closeRef.current(); closeRef.current = null }
    try { localStorage.removeItem(STORAGE_KEY) } catch { /* ignore */ }
    dispatch({ kind: 'stop' })
  }, [])

  const value = { ...state, isRunning: state.status === 'running', startRun, stopWatching }
  return <RunCtx.Provider value={value}>{children}</RunCtx.Provider>
}

export function useRunState() {
  const ctx = useContext(RunCtx)
  if (!ctx) throw new Error('useRunState must be used inside RunProvider')
  return ctx
}
```

- [ ] **Step 4: Wire the provider into `main.jsx`**

In `src/main.jsx`, add the import after the `ConsoleModeProvider` import:

```jsx
import { RunProvider } from './run/RunProvider.jsx'
```

Then wrap `<App />` (inside `ConsoleModeProvider`):

```jsx
          <ConsoleModeProvider>
            <RunProvider>
              <App />
            </RunProvider>
          </ConsoleModeProvider>
```

- [ ] **Step 5: Run tests**

Run: `npm test -- src/run/__tests__/RunProvider.test.jsx`
Expected: PASS (4 tests). Then `npm run build` — expected: succeeds.

- [ ] **Step 6: Commit**

```bash
git add src/run/RunProvider.jsx src/main.jsx src/run/__tests__/RunProvider.test.jsx
git commit -m "feat(run): global RunProvider — background runs, refresh-resume, completion sync"
```

---

## Task 3: AssignmentPicker (select 1–10)

**Files:**
- Create: `src/components/run/AssignmentPicker.jsx`
- Test: `src/components/run/__tests__/AssignmentPicker.test.jsx`

**Interfaces:**
- Consumes (existing): `useAssignments` from `src/api/assignments.js`; `apiClient` for per-id `/review`; `useQueries` from react-query; `mk` from `src/console/modeKey.js`; `useTokens`; `realCandidateName` from `src/lib/redact.js`.
- Consumes (Task 2): `useRunState()` → `startRun`.
- Produces: default-export `AssignmentPicker` component. Renders rows with `data-testid="pick-row"`, a checkbox per row, a counter `data-testid="sel-count"`, and a `Confirm & Run` button.

- [ ] **Step 1: Write the failing test**

Create `src/components/run/__tests__/AssignmentPicker.test.jsx`:

```jsx
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, fireEvent, within } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'

const startRun = vi.fn()
vi.mock('../../../run/RunProvider.jsx', () => ({ useRunState: () => ({ startRun }) }))

// 12 ids so we can test the cap of 10
const IDS = Array.from({ length: 12 }, (_, i) => String(149000 + i))
vi.mock('../../../api/assignments.js', () => ({
  useAssignments: () => ({ data: { assignment_ids: IDS }, isLoading: false }),
  useTestIds: () => ({ data: { test_ids: [] } }),
}))
// Every /review resolves to minimal data (processed = DONE)
vi.mock('@tanstack/react-query', async (orig) => ({
  ...(await orig()),
  useQueries: ({ queries }) => queries.map(() => ({ data: { candidate: 'Jane', district: 'PS 1', hitl_tier: 'GREEN' }, isLoading: false })),
}))

import AssignmentPicker from '../AssignmentPicker.jsx'

describe('AssignmentPicker', () => {
  beforeEach(() => startRun.mockReset())

  it('renders a row per assignment', () => {
    renderWithProviders(<AssignmentPicker />)
    expect(screen.getAllByTestId('pick-row')).toHaveLength(12)
  })

  it('caps selection at 10', () => {
    renderWithProviders(<AssignmentPicker />)
    const boxes = screen.getAllByRole('checkbox')
    boxes.forEach(b => fireEvent.click(b))            // try to select all 12
    const checked = boxes.filter(b => b.checked)
    expect(checked.length).toBe(10)
    expect(screen.getByTestId('sel-count').textContent).toContain('10')
  })

  it('Confirm & Run calls startRun with the selected ids', () => {
    renderWithProviders(<AssignmentPicker />)
    const boxes = screen.getAllByRole('checkbox')
    fireEvent.click(boxes[0]); fireEvent.click(boxes[1])
    fireEvent.click(screen.getByRole('button', { name: /confirm & run/i }))
    expect(startRun).toHaveBeenCalledTimes(1)
    expect(startRun.mock.calls[0][0]).toHaveLength(2)
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test -- src/components/run/__tests__/AssignmentPicker.test.jsx`
Expected: FAIL — cannot resolve `../AssignmentPicker.jsx`

- [ ] **Step 3: Write the implementation**

Create `src/components/run/AssignmentPicker.jsx`:

```jsx
import { useMemo, useState } from 'react'
import { motion } from 'framer-motion'
import { useQueries } from '@tanstack/react-query'
import { useAssignments } from '../../api/assignments.js'
import { apiClient } from '../../lib/apiClient.js'
import { mk } from '../../console/modeKey.js'
import { useTokens } from '../../lib/theme.jsx'
import { realCandidateName } from '../../lib/redact.js'
import { useRunState } from '../../run/RunProvider.jsx'

const MAX_SELECT = 10

export default function AssignmentPicker() {
  const t = useTokens()
  const { startRun } = useRunState()
  const { data, isLoading } = useAssignments()
  const ids = useMemo(() => (data?.assignment_ids ?? data ?? []).map(String), [data])

  const reviews = useQueries({
    queries: ids.map(id => ({ queryKey: mk('review', id), queryFn: () => apiClient.get(`/review/${id}`), enabled: !!id, staleTime: 30_000, retry: 0 })),
  })
  const meta = useMemo(() => Object.fromEntries(ids.map((id, i) => [id, reviews[i]?.data])), [ids, reviews])

  const [selected, setSelected] = useState([])     // array of ids (order = click order)
  const [q, setQ] = useState('')
  const [starting, setStarting] = useState(false)

  const atCap = selected.length >= MAX_SELECT
  const toggle = (id) => setSelected(prev =>
    prev.includes(id) ? prev.filter(x => x !== id) : (prev.length >= MAX_SELECT ? prev : [...prev, id]))

  const rows = ids.filter(id => {
    if (!q) return true
    const m = meta[id] || {}
    const name = realCandidateName(null, m.candidate) ?? m.candidate ?? ''
    return `${name} ${m.district ?? ''} ${id}`.toLowerCase().includes(q.toLowerCase())
  })

  async function confirm() {
    if (!selected.length) return
    setStarting(true)
    try { await startRun(selected) } finally { setStarting(false) }
  }

  return (
    <div className="flex flex-col gap-3" style={{ fontFamily: 'Geist,sans-serif' }}>
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <input
          value={q} onChange={e => setQ(e.target.value)}
          placeholder="Search candidate, district, id…"
          className="rounded-xl px-3 py-2 text-xs outline-none"
          style={{ background: t.inputBg, border: `1px solid ${t.inputBorder}`, color: t.textStrong, width: 260 }}
        />
        <span data-testid="sel-count" className="text-xs font-semibold"
          style={{ color: atCap ? '#C9871A' : t.muted }}>
          {selected.length} / {MAX_SELECT} selected
        </span>
      </div>

      <div className="flex flex-col gap-2 max-h-[calc(100vh-260px)] overflow-y-auto pr-1">
        {isLoading && rows.length === 0 && <div className="text-xs" style={{ color: t.muted }}>Loading assignments…</div>}
        {rows.map((id, i) => {
          const m = meta[id] || {}
          const done = !!m && !!meta[id]
          const checked = selected.includes(id)
          const disabled = !checked && atCap
          const name = realCandidateName(null, m.candidate) ?? m.candidate ?? `Assignment ${id}`
          return (
            <motion.label
              key={id} data-testid="pick-row"
              initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.16, delay: Math.min(i, 12) * 0.015 }}
              className="flex items-center gap-3 rounded-xl px-3 py-2.5 cursor-pointer transition-all duration-150"
              style={{
                background: checked ? (t.isDark ? 'rgba(91,168,255,0.10)' : 'rgba(30,111,224,0.06)') : t.cardBg,
                border: `1px solid ${checked ? t.accent : t.cardBorder}`,
                opacity: disabled ? 0.5 : 1, cursor: disabled ? 'not-allowed' : 'pointer',
              }}>
              <input type="checkbox" checked={checked} disabled={disabled} onChange={() => toggle(id)}
                style={{ accentColor: t.accent, flexShrink: 0 }} />
              <div className="min-w-0 flex-1">
                <div className="text-[13px] font-semibold truncate" style={{ color: t.textStrong }}>{name}</div>
                <div className="text-[10.5px] mt-0.5 truncate" style={{ color: t.muted }}>
                  <span style={{ fontFamily: 'JetBrains Mono,monospace' }}>#{id}</span>
                  {m.district ? ` · ${m.district}` : ''}
                </div>
              </div>
              <span className="text-[8.5px] font-bold tracking-wider px-2 py-0.5 rounded-full shrink-0"
                style={{ color: done ? '#1F8A4C' : t.accent, border: `1px solid ${done ? '#1F8A4C' : t.accent}` }}>
                {done ? 'DONE' : 'NEW'}
              </span>
            </motion.label>
          )
        })}
      </div>

      <button
        onClick={confirm} disabled={!selected.length || starting}
        className="w-full py-3 rounded-xl font-bold text-sm btn-press transition-all duration-200"
        style={{
          background: selected.length ? 'linear-gradient(135deg,#103B69,#005280,#1DAEEF)' : (t.isDark ? 'rgba(91,168,255,0.08)' : 'rgba(30,111,224,0.07)'),
          color: selected.length ? '#fff' : t.muted,
          cursor: selected.length && !starting ? 'pointer' : 'not-allowed',
          boxShadow: selected.length ? '0 4px 20px rgba(29,174,239,0.3)' : 'none', border: 'none',
        }}>
        {starting ? 'Starting…' : `Confirm & Run${selected.length ? ` (${selected.length})` : ''}`}
      </button>
    </div>
  )
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test -- src/components/run/__tests__/AssignmentPicker.test.jsx`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add src/components/run/AssignmentPicker.jsx src/components/run/__tests__/AssignmentPicker.test.jsx
git commit -m "feat(run): AssignmentPicker — select 1-10 new/done assignments"
```

---

## Task 4: RunLiveView (live progress + Stop watching)

**Files:**
- Create: `src/components/run/RunLiveView.jsx`

**Interfaces:**
- Consumes (Task 2): `useRunState()` → `{ status, results, selectedIds, agentsByAid, logLines, events, stopWatching }`.
- Consumes (existing): `LiveStream` from `src/components/run/LiveStream.jsx`; `useTokens`; `useNavigate`.
- Produces: default-export `RunLiveView` component. Includes a button titled `Stop watching` and, when `status === 'done'`, a button titled `Run another batch` that calls `stopWatching`.

- [ ] **Step 1: Write the component**

Create `src/components/run/RunLiveView.jsx`:

```jsx
import { useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { useRunState } from '../../run/RunProvider.jsx'
import { useTokens } from '../../lib/theme.jsx'
import LiveStream from './LiveStream.jsx'

export default function RunLiveView() {
  const t = useTokens()
  const navigate = useNavigate()
  const { status, results, selectedIds, agentsByAid, logLines, events, stopWatching } = useRunState()

  const total = selectedIds.length || Object.keys(agentsByAid).length || 0
  const done = results.length
  const pct = total ? Math.round((done / total) * 100) : 0
  const isDone = status === 'done'
  const isFailed = status === 'failed'

  return (
    <motion.div initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.22 }}
      className="flex flex-col gap-4" style={{ fontFamily: 'Geist,sans-serif' }}>

      {/* Status header + progress */}
      <div className="rounded-2xl p-5" style={{ background: t.cardBg, border: `1px solid ${t.cardBorder}`, boxShadow: t.cardShadow }}>
        <div className="flex items-center justify-between gap-3 mb-3 flex-wrap">
          <div>
            <div className="text-[15px] font-bold" style={{ color: t.textStrong }}>
              {isDone ? '✅ Batch complete' : isFailed ? '⚠ Batch failed' : 'Running pipeline…'}
            </div>
            <div className="text-[11px] mt-0.5" style={{ color: t.muted }}>
              {done} / {total} assignments processed
            </div>
          </div>
          <div className="flex items-center gap-2">
            {isDone && (
              <button onClick={() => navigate('/tracker')} className="px-3.5 py-2 rounded-xl text-[12px] font-semibold btn-press"
                style={{ background: t.tagBg, color: t.accent, border: `1px solid ${t.tagBorder}`, cursor: 'pointer' }}>
                View in Tracker →
              </button>
            )}
            <button
              onClick={stopWatching}
              title="The backend may finish in-flight assignments — there is no server-side cancel yet."
              className="px-3.5 py-2 rounded-xl text-[12px] font-semibold btn-press"
              style={{ background: 'rgba(192,57,43,0.10)', color: '#C0392B', border: '1px solid rgba(192,57,43,0.25)', cursor: 'pointer' }}>
              {isDone || isFailed ? 'Run another batch' : 'Stop watching'}
            </button>
          </div>
        </div>

        {/* Progress bar */}
        <div className="h-2 rounded-full overflow-hidden" style={{ background: t.isDark ? 'rgba(124,164,255,0.12)' : 'rgba(30,111,224,0.1)' }}>
          <motion.div animate={{ width: `${pct}%` }} transition={{ duration: 0.4 }}
            style={{ height: '100%', background: 'linear-gradient(90deg,#005280,#1DAEEF)' }} />
        </div>
      </div>

      {/* Live stream (reuses the existing renderer) */}
      <div className="rounded-2xl p-5" style={{ background: t.cardBg, border: `1px solid ${t.cardBorder}`, boxShadow: t.cardShadow }}>
        <div className="text-[10px] font-bold tracking-widest uppercase mb-3" style={{ color: t.sectionLabel }}>Live Output</div>
        <LiveStream status={status} events={events} agentsByAid={agentsByAid} logLines={logLines} results={results} />
      </div>
    </motion.div>
  )
}
```

- [ ] **Step 2: Verify build**

Run: `npm run build`
Expected: succeeds (imports resolve, JSX compiles).

- [ ] **Step 3: Commit**

```bash
git add src/components/run/RunLiveView.jsx
git commit -m "feat(run): RunLiveView — batch progress, live stream, stop watching"
```

---

## Task 5: RunPage rewrite (picker vs live)

**Files:**
- Modify (rewrite): `src/pages/RunPage.jsx`

**Interfaces:**
- Consumes (Task 2): `useRunState()` → `status`.
- Consumes (Tasks 3,4): `AssignmentPicker`, `RunLiveView`.
- Consumes (existing): `useTokens`.

- [ ] **Step 1: Rewrite the page**

Replace `src/pages/RunPage.jsx` entirely:

```jsx
import { AnimatePresence, motion } from 'framer-motion'
import { useRunState } from '../run/RunProvider.jsx'
import { useTokens } from '../lib/theme.jsx'
import AssignmentPicker from '../components/run/AssignmentPicker.jsx'
import RunLiveView from '../components/run/RunLiveView.jsx'

export default function RunPage() {
  const t = useTokens()
  const { status } = useRunState()
  const showPicker = status === 'idle'

  return (
    <div style={{ padding: '24px 28px', maxWidth: 920, margin: '0 auto' }} className="animate-fade-up">
      <div style={{ marginBottom: 20 }}>
        <div style={{ fontSize: 24, fontWeight: 700, color: t.textStrong, fontFamily: 'Geist,sans-serif', letterSpacing: '-0.01em', marginBottom: 4 }}>
          Run Pipeline
        </div>
        <div style={{ fontSize: 12, color: t.muted, fontFamily: 'Geist,sans-serif' }}>
          {showPicker
            ? 'Select up to 10 assignments and run the full credentialing pipeline. It keeps running if you switch pages.'
            : 'Pipeline running in the background — you can navigate away and come back; it will keep going until you stop watching.'}
        </div>
      </div>

      <AnimatePresence mode="wait">
        <motion.div key={showPicker ? 'picker' : 'live'}
          initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.18 }}>
          {showPicker ? <AssignmentPicker /> : <RunLiveView />}
        </motion.div>
      </AnimatePresence>
    </div>
  )
}
```

- [ ] **Step 2: Verify build + full suite**

Run: `npm run build` (expected: succeeds), then `npm test` (expected: all pass — the old RunPage had no test).

- [ ] **Step 3: Commit**

```bash
git add src/pages/RunPage.jsx
git commit -m "feat(run): RunPage shows picker when idle, live view when a batch is active"
```

---

## Task 6: TopBar "pipeline running" pill

**Files:**
- Modify: `src/components/shell/TopBar.jsx`

**Interfaces:**
- Consumes (Task 2): `useRunState()` → `{ status, results, selectedIds }`.
- Consumes (existing): `useNavigate` (react-router), `motion` (framer-motion is already a dep).

- [ ] **Step 1: Add the pill**

In `src/components/shell/TopBar.jsx`, add imports at the top (keep existing imports):

```jsx
import { useNavigate } from 'react-router-dom'
import { motion, AnimatePresence } from 'framer-motion'
import { useRunState } from '../../run/RunProvider.jsx'
```

Inside the `TopBar` component body, near the other hooks, add:

```jsx
  const navigate = useNavigate()
  const { status, results, selectedIds } = useRunState()
  const running = status === 'running'
```

Then render the pill in the TopBar's left or center area (place it just before the theme toggle / right-side controls — pick the existing right-side flex container and add this as its first child):

```jsx
        <AnimatePresence>
          {running && (
            <motion.button
              key="run-pill"
              initial={{ opacity: 0, scale: 0.9 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.9 }}
              onClick={() => navigate('/run')}
              title="Pipeline running — click to view"
              style={{
                display: 'flex', alignItems: 'center', gap: 8, padding: '5px 12px', borderRadius: 999,
                border: '1px solid rgba(29,174,239,0.35)', background: 'rgba(29,174,239,0.12)',
                color: '#1DAEEF', fontFamily: 'Geist,sans-serif', fontSize: 11, fontWeight: 700, cursor: 'pointer',
              }}>
              <span className="animate-pulse-dot" style={{ width: 7, height: 7, borderRadius: 999, background: '#1DAEEF', boxShadow: '0 0 8px #1DAEEF' }} />
              Running {results.length}/{selectedIds.length || '…'}
            </motion.button>
          )}
        </AnimatePresence>
```

(If the file has no obvious right-side flex container, add the snippet immediately before the theme-toggle block — the implementer should place it so it sits inline with the top-bar controls and matches their spacing.)

- [ ] **Step 2: Verify build**

Run: `npm run build`
Expected: succeeds. Manually confirm (or via lint) no unused-import errors.

- [ ] **Step 3: Commit**

```bash
git add src/components/shell/TopBar.jsx
git commit -m "feat(run): TopBar pill shows a running batch from any page"
```

---

## Task 7: Fix Tracker vertical scroll

**Files:**
- Modify: `src/pages/TrackerPage.jsx`

**Interfaces:** none new — a one-line layout fix.

- [ ] **Step 1: Bound the page height**

In `src/pages/TrackerPage.jsx`, the root element is currently:

```jsx
    <div className="flex flex-col h-full gap-3 px-6 py-5" style={{ fontFamily: 'Geist,sans-serif' }}>
```

`h-full` does not resolve because the AppShell content wrapper is auto-height, so the inner
`overflow-auto` table container is content-tall and never scrolls (and the scoped Lenis then
swallows wheel events). Bound the page to the viewport minus the 54px TopBar. Change it to:

```jsx
    <div className="flex flex-col gap-3 px-6 py-5" style={{ fontFamily: 'Geist,sans-serif', height: 'calc(100vh - 54px)' }}>
```

Leave the rest of the file unchanged — `flex-1 min-h-0` on the table card now bounds the
`ref={scrollRef}` container, so Lenis drives internal scrolling.

- [ ] **Step 2: Verify**

Run: `npm test -- src/pages/__tests__/TrackerPage.test.jsx` (expected: PASS — style-only change), then `npm run build` (expected: succeeds).

Manual check (if a dev server is available): open the Tracker, confirm the rows scroll vertically within the card and the sticky header stays put.

- [ ] **Step 3: Commit**

```bash
git add src/pages/TrackerPage.jsx
git commit -m "fix(tracker): bound table height to viewport so vertical scroll works"
```

---

## Self-Review Notes

- **Spec coverage:** global provider above router (Task 2 + main.jsx) ✓; picker NEW+DONE select 1–10 (Task 3) ✓; background across navigation (provider lives above router) ✓; refresh-resume via /jobs (Task 2 load effect) ✓; Abort = stop watching (Task 4 button + provider.stopWatching) ✓; completion → cred-tracker sync (Task 2 effect) ✓; TopBar running pill (Task 6) ✓; animations/Tailwind (Tasks 3–6) ✓; tracker scroll fix (Task 7) ✓; tests (Tasks 1–3, plus build/suite checks) ✓.
- **Type/name consistency:** `useRunState()` shape (`status`, `isRunning`, `startRun`, `stopWatching`, `results`, `selectedIds`, `agentsByAid`, `logLines`, `events`) is identical across Tasks 2–6. `reduceSseEvent`/`INITIAL_SSE_STATE`/`TERMINAL_EVENTS` names match between Task 1 and Task 2. localStorage key `acap.activeRun` consistent. Query key `['cred-tracker','rows']` matches `src/api/credTracker.js`.
- **Known notes:** `useSSE.js` is left intact (still used by `RerunBanner`); the provider uses the new reducer rather than that hook, so there's a small overlap by design (no shared-state risk). The provider's load-effect adopts the most-recent running job if the saved job_id is gone — acceptable per spec. `realCandidateName(null, fallback)` is called with a null agent-2 payload in the picker (only the fallback path is used there) — matches its signature in `src/lib/redact.js`.
# Dashboard History, Activity Feed & Agent-3 Verify — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist a daily dashboard snapshot to SQL Server and let users view any date range (with 30/60/90-day presets); replace the raw "Live telemetry" terminal in the Cockpit step-run and Run-Pipeline views with a polished loading state + realtime activity feed; and verify the Agent-3 credentialer reassign control.

**Architecture:** The in-repo `excel-api` (Node/Express/`mssql`, schema `stg`) gains two tables (`stg.Cred_Dashboard` aggregate + `stg.Cred_Dashboard_Detail` per-assignment) and two routes (`POST /dashboard/snapshot`, `GET /dashboard`). The dashboard computes today's snapshot client-side (it already holds all review data) and upserts it once per load; historical views read detail rows back and reshape them into the exact `{ assignment_id, review }` shape the existing chart components consume, so no chart is rewritten. The activity feed is a shared component driven by the existing SSE-derived state (`events`/`agentsByAid`/`results`), with `useStepRun` extended to accumulate structured events via the existing `reduceSseEvent`.

**Tech Stack:** React 18, `@tanstack/react-query`, Vite, Vitest + Testing Library (frontend); Node + Express + `mssql`, `node --test` (excel-api). CommonJS in excel-api, ESM in `src/`.

## Global Constraints

- excel-api is **CommonJS** (`require`/`module.exports`), tests use `node --test` (`node:test` + `node:assert`), run with `cd excel-api && npm test`. Pure helpers get unit tests; DB/route code is verified manually (follows the existing `credTracker`/`normalize` precedent — no DB in the test env).
- Frontend is **ESM** (`import`/`export`), tests use **Vitest** + `@testing-library/react`, run with `npm test` (or `npx vitest run <path>`). Use `renderWithProviders` from `src/test-utils/render.jsx` for component tests.
- Write endpoints on excel-api are guarded by the `X-Cred-Tracker-Token` header via `requireToken` from `excel-api/auth.js`; the browser sends `VITE_CRED_TRACKER_TOKEN`. Reuse this exact mechanism — do **not** invent a new token.
- Frontend calls excel-api at `EXCEL_API_BASE` (from `src/config.js`) and MUST include `NGROK_SKIP_HEADER` on every request (see `src/api/tracker.js`).
- The snapshot write is **best-effort and fire-and-forget** — a failed snapshot must never break the dashboard render, and it fires **at most once per page mount** (guarded by a ref), never on the 15s refetch.
- Review payload field names (verbatim, do not rename): `hitl_tier` (`'RED'|'YELLOW'|'GREEN'`), `ready` (bool), `cost.total_usd` (number), `cost.by_agent` (object keyed by agent id string → number), `counts.{valid,expiring,expired,missing,unreadable,auditor_flags}` (numbers), `candidate` (string), `district` (string).
- "Total Candidates" = the triaged set = count of assignments whose `hitl_tier` is RED/YELLOW/GREEN (matches `DashboardStats`).
- Dates are ISO `YYYY-MM-DD` strings everywhere on the wire; SQL Server column type `DATE`.
- Follow existing styling: `useTokens()` for theme, `fontFamily: 'Geist,sans-serif'`, existing animation classes. No new UI libraries.

---

## File Structure

**excel-api (new/modified):**
- Create `excel-api/dashboard.js` — table DDL, snapshot upsert, range read, pure `validateSnapshot`.
- Create `excel-api/test/dashboard.test.js` — unit tests for `validateSnapshot`.
- Modify `excel-api/index.js` — register `POST /dashboard/snapshot`, `GET /dashboard`.
- Modify `excel-api/README.md` — document the new endpoints.

**Frontend (new/modified):**
- Create `src/lib/dashboardHistory.js` — pure helpers: `buildSnapshotPayload`, `detailRowsToAssignments`, `presetRange`, `addDays`, `todayISO`.
- Create `src/lib/__tests__/dashboardHistory.test.js`.
- Create `src/api/dashboardHistory.js` — `useDashboardRange`, `postSnapshot`.
- Create `src/components/dashboard/DateRangeControl.jsx` — preset tabs + custom pickers.
- Create `src/components/dashboard/__tests__/DateRangeControl.test.jsx`.
- Modify `src/pages/DashboardPage.jsx` — view state, snapshot-on-load, data-source switch.
- Create `src/lib/activityLog.js` — pure `parseDocsFromLog`, `documentsFromReview`.
- Create `src/lib/__tests__/activityLog.test.js`.
- Create `src/components/run/ActivityFeed.jsx`.
- Create `src/components/run/__tests__/ActivityFeed.test.jsx`.
- Modify `src/hooks/useStepRun.js` — accumulate structured events.
- Modify `src/components/cockpit/StepRunPanel.jsx` — swap TerminalLog → ActivityFeed.
- Modify `src/components/run/LiveStream.jsx` — swap TerminalLog → ActivityFeed.
- Modify `src/components/cockpit/__tests__/GatePanel.test.jsx` — Agent-3 coverage.

---

## FEATURE 1 — Historical dashboard

### Task 1: excel-api dashboard module (`validateSnapshot` + DB functions)

**Files:**
- Create: `excel-api/dashboard.js`
- Test: `excel-api/test/dashboard.test.js`

**Interfaces:**
- Consumes: `sql` from `./db.js`.
- Produces:
  - `validateSnapshot(payload)` → `{ date: string, aggregate: {...}, detail: [...] }` (throws `Error` on invalid input). Pure.
  - `ensureDashboardTables(pool)` → `Promise<void>`
  - `upsertSnapshot(pool, payload)` → `Promise<{ date, rows }>`
  - `getRange(pool, start, end)` → `Promise<{ aggregates, detail }>` where each detail row has keys `snapshot_date, assignment_id, candidate, district, tier, ready, cost, cost_by_agent (object), valid, expiring, expired, missing, unreadable, auditor_flags`.

- [ ] **Step 1: Write the failing test** — `excel-api/test/dashboard.test.js`

```js
const { test } = require('node:test')
const assert = require('node:assert')
const { validateSnapshot } = require('../dashboard.js')

test('validateSnapshot accepts a well-formed payload and coerces numbers', () => {
  const out = validateSnapshot({
    date: '2026-07-06',
    aggregate: { total: 2, red: 1, yellow: 0, green: 1, ready: 1, cost: 0.5, missing: 3, flags: 2 },
    detail: [
      { assignment_id: 149036, candidate: 'Jane', district: 'Loudoun', tier: 'RED', ready: false,
        cost: 0.25, cost_by_agent: { '1': 0.1, '2': 0.15 },
        valid: 4, expiring: 0, expired: 1, missing: 2, unreadable: 0, auditor_flags: 1 },
      { assignment_id: '149037', tier: 'GREEN', ready: true, cost: 0.25 },
    ],
  })
  assert.equal(out.date, '2026-07-06')
  assert.equal(out.aggregate.total, 2)
  assert.equal(out.detail.length, 2)
  assert.equal(out.detail[1].assignment_id, 149037) // coerced to number
  assert.equal(out.detail[1].valid, 0)              // missing counts default to 0
  assert.deepEqual(out.detail[0].cost_by_agent, { '1': 0.1, '2': 0.15 })
})

test('validateSnapshot rejects a bad date', () => {
  assert.throws(() => validateSnapshot({ date: '07/06/2026', aggregate: {}, detail: [] }), /date/i)
})

test('validateSnapshot rejects a non-array detail', () => {
  assert.throws(() => validateSnapshot({ date: '2026-07-06', aggregate: {}, detail: {} }), /detail/i)
})

test('validateSnapshot drops detail rows with no numeric assignment_id', () => {
  const out = validateSnapshot({
    date: '2026-07-06', aggregate: {},
    detail: [{ assignment_id: 'abc' }, { assignment_id: 5, tier: 'YELLOW' }],
  })
  assert.equal(out.detail.length, 1)
  assert.equal(out.detail[0].assignment_id, 5)
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd excel-api && node --test test/dashboard.test.js`
Expected: FAIL — `Cannot find module '../dashboard.js'` / `validateSnapshot is not a function`.

- [ ] **Step 3: Write minimal implementation** — `excel-api/dashboard.js`

```js
const { sql } = require('./db.js')

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/
const num = (v) => (Number.isFinite(Number(v)) ? Number(v) : 0)
const AGG_KEYS = ['total', 'red', 'yellow', 'green', 'ready', 'cost', 'missing', 'flags']
const COUNT_KEYS = ['valid', 'expiring', 'expired', 'missing', 'unreadable', 'auditor_flags']

/** Validate + normalize an incoming snapshot payload. Pure; throws on bad shape. */
function validateSnapshot(payload) {
  const p = payload || {}
  if (!ISO_DATE.test(String(p.date || ''))) throw new Error('invalid date — expected YYYY-MM-DD')
  if (!Array.isArray(p.detail)) throw new Error('detail must be an array')
  const aggregate = {}
  for (const k of AGG_KEYS) aggregate[k] = num(p.aggregate?.[k])
  const detail = p.detail
    .map((d) => {
      const id = Number(d?.assignment_id)
      if (!Number.isFinite(id)) return null
      const row = {
        assignment_id: id,
        candidate: d.candidate == null ? null : String(d.candidate),
        district: d.district == null ? null : String(d.district),
        tier: ['RED', 'YELLOW', 'GREEN'].includes(d.tier) ? d.tier : null,
        ready: !!d.ready,
        cost: num(d.cost),
        cost_by_agent: (d.cost_by_agent && typeof d.cost_by_agent === 'object') ? d.cost_by_agent : {},
      }
      for (const k of COUNT_KEYS) row[k] = num(d[k])
      return row
    })
    .filter(Boolean)
  return { date: p.date, aggregate, detail }
}

async function ensureDashboardTables(pool) {
  await pool.request().batch(`
    IF OBJECT_ID('stg.Cred_Dashboard','U') IS NULL
    CREATE TABLE stg.Cred_Dashboard (
      Snapshot_Date    DATE          NOT NULL PRIMARY KEY,
      Total_Candidates INT           NULL,
      Red              INT           NULL,
      Yellow           INT           NULL,
      Green            INT           NULL,
      Ready            INT           NULL,
      Total_Cost_USD   DECIMAL(12,4) NULL,
      Docs_Missing     INT           NULL,
      Auditor_Flags    INT           NULL,
      Updated_At       DATETIME2     NULL
    );`)
  await pool.request().batch(`
    IF OBJECT_ID('stg.Cred_Dashboard_Detail','U') IS NULL
    CREATE TABLE stg.Cred_Dashboard_Detail (
      Snapshot_Date  DATE          NOT NULL,
      Assignment_Id  INT           NOT NULL,
      Candidate_Name NVARCHAR(200) NULL,
      District       NVARCHAR(300) NULL,
      Tier           NVARCHAR(10)  NULL,
      Ready          BIT           NULL,
      Cost_USD       DECIMAL(12,4) NULL,
      Cost_By_Agent  NVARCHAR(MAX) NULL,
      Valid          INT           NULL,
      Expiring       INT           NULL,
      Expired        INT           NULL,
      Missing        INT           NULL,
      Unreadable     INT           NULL,
      Auditor_Flags  INT           NULL,
      CONSTRAINT PK_Cred_Dashboard_Detail PRIMARY KEY (Snapshot_Date, Assignment_Id)
    );`)
}

/** Delete-then-insert today's rows inside a transaction (idempotent per date). */
async function upsertSnapshot(pool, payload) {
  const { date, aggregate, detail } = validateSnapshot(payload)
  const tx = new sql.Transaction(pool)
  await tx.begin()
  try {
    await new sql.Request(tx)
      .input('d', sql.Date, date)
      .input('total', sql.Int, aggregate.total)
      .input('red', sql.Int, aggregate.red)
      .input('yellow', sql.Int, aggregate.yellow)
      .input('green', sql.Int, aggregate.green)
      .input('ready', sql.Int, aggregate.ready)
      .input('cost', sql.Decimal(12, 4), aggregate.cost)
      .input('missing', sql.Int, aggregate.missing)
      .input('flags', sql.Int, aggregate.flags)
      .query(`
        DELETE FROM stg.Cred_Dashboard WHERE Snapshot_Date = @d;
        INSERT INTO stg.Cred_Dashboard
          (Snapshot_Date, Total_Candidates, Red, Yellow, Green, Ready, Total_Cost_USD, Docs_Missing, Auditor_Flags, Updated_At)
        VALUES (@d, @total, @red, @yellow, @green, @ready, @cost, @missing, @flags, SYSUTCDATETIME());`)

    await new sql.Request(tx).input('d', sql.Date, date)
      .query('DELETE FROM stg.Cred_Dashboard_Detail WHERE Snapshot_Date = @d')

    for (const row of detail) {
      await new sql.Request(tx)
        .input('d', sql.Date, date)
        .input('id', sql.Int, row.assignment_id)
        .input('cand', sql.NVarChar, row.candidate)
        .input('dist', sql.NVarChar, row.district)
        .input('tier', sql.NVarChar, row.tier)
        .input('ready', sql.Bit, row.ready ? 1 : 0)
        .input('cost', sql.Decimal(12, 4), row.cost)
        .input('cba', sql.NVarChar, JSON.stringify(row.cost_by_agent || {}))
        .input('valid', sql.Int, row.valid)
        .input('expiring', sql.Int, row.expiring)
        .input('expired', sql.Int, row.expired)
        .input('missing', sql.Int, row.missing)
        .input('unreadable', sql.Int, row.unreadable)
        .input('flags', sql.Int, row.auditor_flags)
        .query(`
          INSERT INTO stg.Cred_Dashboard_Detail
            (Snapshot_Date, Assignment_Id, Candidate_Name, District, Tier, Ready, Cost_USD,
             Cost_By_Agent, Valid, Expiring, Expired, Missing, Unreadable, Auditor_Flags)
          VALUES (@d, @id, @cand, @dist, @tier, @ready, @cost, @cba, @valid, @expiring, @expired, @missing, @unreadable, @flags);`)
    }
    await tx.commit()
    return { date, rows: detail.length }
  } catch (e) {
    await tx.rollback()
    throw e
  }
}

const AGG_SELECT = `
  CONVERT(char(10), Snapshot_Date, 23) AS snapshot_date,
  Total_Candidates AS total, Red AS red, Yellow AS yellow, Green AS green,
  Ready AS ready, Total_Cost_USD AS cost, Docs_Missing AS missing, Auditor_Flags AS flags`

const DETAIL_SELECT = `
  CONVERT(char(10), Snapshot_Date, 23) AS snapshot_date,
  Assignment_Id AS assignment_id, Candidate_Name AS candidate, District AS district,
  Tier AS tier, Ready AS ready, Cost_USD AS cost, Cost_By_Agent AS cost_by_agent,
  Valid AS valid, Expiring AS expiring, Expired AS expired, Missing AS missing,
  Unreadable AS unreadable, Auditor_Flags AS auditor_flags`

async function getRange(pool, start, end) {
  if (!ISO_DATE.test(String(start)) || !ISO_DATE.test(String(end))) {
    throw new Error('start and end must be YYYY-MM-DD')
  }
  const aggReq = pool.request().input('s', sql.Date, start).input('e', sql.Date, end)
  const agg = await aggReq.query(
    `SELECT ${AGG_SELECT} FROM stg.Cred_Dashboard
     WHERE Snapshot_Date BETWEEN @s AND @e ORDER BY Snapshot_Date`)
  const detReq = pool.request().input('s', sql.Date, start).input('e', sql.Date, end)
  const det = await detReq.query(
    `SELECT ${DETAIL_SELECT} FROM stg.Cred_Dashboard_Detail
     WHERE Snapshot_Date BETWEEN @s AND @e ORDER BY Snapshot_Date, Assignment_Id`)
  const detail = det.recordset.map((r) => ({
    ...r,
    ready: !!r.ready,
    cost_by_agent: parseJsonObj(r.cost_by_agent),
  }))
  return { aggregates: agg.recordset, detail }
}

function parseJsonObj(s) {
  if (!s) return {}
  try { const o = JSON.parse(s); return o && typeof o === 'object' ? o : {} } catch { return {} }
}

module.exports = { validateSnapshot, ensureDashboardTables, upsertSnapshot, getRange }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd excel-api && node --test test/dashboard.test.js`
Expected: PASS — 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add excel-api/dashboard.js excel-api/test/dashboard.test.js
git commit -m "feat(excel-api): dashboard snapshot module — tables, upsert, range, validateSnapshot"
```

---

### Task 2: excel-api routes for snapshot write + range read

**Files:**
- Modify: `excel-api/index.js`
- Modify: `excel-api/README.md`

**Interfaces:**
- Consumes: `ensureDashboardTables`, `upsertSnapshot`, `getRange` from `./dashboard.js`; `requireToken` from `./auth.js`.
- Produces HTTP: `POST /dashboard/snapshot` (token-guarded) → `{ ok, date, rows }`; `GET /dashboard?start=&end=` → `{ aggregates, detail }`.

- [ ] **Step 1: Add the require** — top of `excel-api/index.js`, after the `credTracker` require (line 11):

```js
const dashboard = require('./dashboard.js')
```

- [ ] **Step 2: Add the routes** — in `excel-api/index.js`, immediately before `app.listen(...)` (currently line 116):

```js
app.get('/dashboard', async (req, res) => {
  const { start, end } = req.query
  if (!start || !end) return res.status(400).json({ error: 'start and end query params required (YYYY-MM-DD)' })
  try {
    const pool = await getPool()
    await dashboard.ensureDashboardTables(pool)
    res.json(await dashboard.getRange(pool, String(start), String(end)))
  } catch (e) {
    console.error('[excel-api] GET /dashboard failed:', e)
    res.status(503).json({ error: 'Dashboard DB unavailable', detail: String(e.message || e) })
  }
})

app.post('/dashboard/snapshot', requireToken, async (req, res) => {
  let pool
  try { pool = await getPool(); await dashboard.ensureDashboardTables(pool) }
  catch (e) { return res.status(503).json({ error: 'Dashboard DB unavailable', detail: String(e.message || e) }) }
  try {
    const result = await dashboard.upsertSnapshot(pool, req.body || {})
    res.json({ ok: true, ...result })
  } catch (e) {
    console.error('[excel-api] POST /dashboard/snapshot failed:', e)
    res.status(400).json({ error: 'Snapshot rejected', detail: String(e.message || e) })
  }
})
```

- [ ] **Step 3: Document the endpoints** — append to the endpoints section of `excel-api/README.md`:

```markdown
### Dashboard history

- `GET /dashboard?start=YYYY-MM-DD&end=YYYY-MM-DD` — read persisted dashboard snapshots
  in a date range. Returns `{ aggregates: [...daily rows...], detail: [...per-assignment rows...] }`.
  Auto-creates `stg.Cred_Dashboard` and `stg.Cred_Dashboard_Detail` on first call.
- `POST /dashboard/snapshot` *(requires `X-Cred-Tracker-Token`)* — upsert today's snapshot.
  Body: `{ date: "YYYY-MM-DD", aggregate: { total, red, yellow, green, ready, cost, missing, flags },
  detail: [ { assignment_id, candidate, district, tier, ready, cost, cost_by_agent, valid, expiring,
  expired, missing, unreadable, auditor_flags } ] }`. Idempotent per date (delete-then-insert).
```

- [ ] **Step 4: Verify it starts and the route shape is right**

Run: `cd excel-api && node -e "require('./index.js')" & sleep 2 && curl -s "http://localhost:8002/dashboard" ; kill %1`
Expected: `{"error":"start and end query params required (YYYY-MM-DD)"}` (400 — proves the route is wired even without a DB). If DB is configured, `curl "http://localhost:8002/dashboard?start=2026-07-01&end=2026-07-06"` returns `{"aggregates":[],"detail":[]}`.

- [ ] **Step 5: Commit**

```bash
git add excel-api/index.js excel-api/README.md
git commit -m "feat(excel-api): GET /dashboard + POST /dashboard/snapshot routes"
```

---

### Task 3: Frontend pure helpers (`dashboardHistory.js`)

**Files:**
- Create: `src/lib/dashboardHistory.js`
- Test: `src/lib/__tests__/dashboardHistory.test.js`

**Interfaces:**
- Produces:
  - `todayISO(now = new Date())` → `'YYYY-MM-DD'`
  - `addDays(iso, n)` → `'YYYY-MM-DD'`
  - `presetRange(preset, todayIso)` → `{ start, end }` for preset `'30'|'60'|'90'` (inclusive last-N-days ending today).
  - `buildSnapshotPayload(assignments, todayIso)` → the exact POST body shape from Task 2. `assignments` is `[{ assignment_id, review }]`.
  - `detailRowsToAssignments(rows)` → `[{ assignment_id, review: {...} }]` — reverse of a detail row into chart-consumable shape, de-duplicated by `assignment_id` (last row wins) so a multi-day range renders one card per candidate.

- [ ] **Step 1: Write the failing test** — `src/lib/__tests__/dashboardHistory.test.js`

```js
import { describe, it, expect } from 'vitest'
import {
  todayISO, addDays, presetRange, buildSnapshotPayload, detailRowsToAssignments,
} from '../dashboardHistory.js'

describe('date helpers', () => {
  it('addDays handles month/year rollover', () => {
    expect(addDays('2026-07-06', -30)).toBe('2026-06-06')
    expect(addDays('2026-01-01', -1)).toBe('2025-12-31')
  })
  it('presetRange returns inclusive last-N-days ending today', () => {
    expect(presetRange('30', '2026-07-06')).toEqual({ start: '2026-06-07', end: '2026-07-06' })
    expect(presetRange('90', '2026-07-06')).toEqual({ start: '2026-04-08', end: '2026-07-06' })
  })
  it('todayISO formats a Date as YYYY-MM-DD', () => {
    expect(todayISO(new Date('2026-07-06T15:00:00Z'))).toBe('2026-07-06')
  })
})

describe('buildSnapshotPayload', () => {
  it('aggregates tiers/cost/counts and builds detail rows', () => {
    const assignments = [
      { assignment_id: 1, review: { hitl_tier: 'RED', ready: false, candidate: 'A', district: 'D1',
        cost: { total_usd: 0.2, by_agent: { '1': 0.1, '2': 0.1 } },
        counts: { valid: 3, expiring: 1, expired: 0, missing: 2, unreadable: 0, auditor_flags: 1 } } },
      { assignment_id: 2, review: { hitl_tier: 'GREEN', ready: true, candidate: 'B', district: 'D2',
        cost: { total_usd: 0.3, by_agent: { '1': 0.3 } },
        counts: { valid: 5, expiring: 0, expired: 0, missing: 0, unreadable: 0, auditor_flags: 0 } } },
      { assignment_id: 3, review: {} }, // no tier — excluded from `total`, still a detail row
    ]
    const p = buildSnapshotPayload(assignments, '2026-07-06')
    expect(p.date).toBe('2026-07-06')
    expect(p.aggregate).toEqual({ total: 2, red: 1, yellow: 0, green: 1, ready: 1, cost: 0.5, missing: 2, flags: 1 })
    expect(p.detail).toHaveLength(3)
    expect(p.detail[0]).toMatchObject({ assignment_id: 1, tier: 'RED', cost: 0.2, missing: 2, cost_by_agent: { '1': 0.1, '2': 0.1 } })
  })
})

describe('detailRowsToAssignments', () => {
  it('reshapes DB rows into { assignment_id, review } and dedupes by id (last wins)', () => {
    const rows = [
      { snapshot_date: '2026-07-05', assignment_id: 1, candidate: 'A', district: 'D1', tier: 'YELLOW',
        ready: false, cost: 0.2, cost_by_agent: { '1': 0.2 }, valid: 1, expiring: 0, expired: 0, missing: 1, unreadable: 0, auditor_flags: 0 },
      { snapshot_date: '2026-07-06', assignment_id: 1, candidate: 'A', district: 'D1', tier: 'RED',
        ready: false, cost: 0.4, cost_by_agent: { '1': 0.4 }, valid: 2, expiring: 0, expired: 0, missing: 0, unreadable: 0, auditor_flags: 2 },
    ]
    const out = detailRowsToAssignments(rows)
    expect(out).toHaveLength(1)
    expect(out[0].assignment_id).toBe(1)
    expect(out[0].review.hitl_tier).toBe('RED') // last row wins
    expect(out[0].review.cost.total_usd).toBe(0.4)
    expect(out[0].review.cost.by_agent).toEqual({ '1': 0.4 })
    expect(out[0].review.counts.auditor_flags).toBe(2)
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/lib/__tests__/dashboardHistory.test.js`
Expected: FAIL — module not found / exports undefined.

- [ ] **Step 3: Write minimal implementation** — `src/lib/dashboardHistory.js`

```js
// Pure helpers for the historical dashboard. No React, no I/O — unit-tested.

const pad = (n) => String(n).padStart(2, '0')

/** A Date → 'YYYY-MM-DD' in UTC (stable, tz-independent). */
export function todayISO(now = new Date()) {
  return `${now.getUTCFullYear()}-${pad(now.getUTCMonth() + 1)}-${pad(now.getUTCDate())}`
}

/** Shift an ISO date by n days (can be negative). Returns 'YYYY-MM-DD'. */
export function addDays(iso, n) {
  const [y, m, d] = iso.split('-').map(Number)
  const dt = new Date(Date.UTC(y, m - 1, d))
  dt.setUTCDate(dt.getUTCDate() + n)
  return todayISO(dt)
}

/** Inclusive last-N-days window ending today. preset ∈ '30' | '60' | '90'. */
export function presetRange(preset, todayIso) {
  const days = Number(preset)
  return { start: addDays(todayIso, -(days - 1)), end: todayIso }
}

const numOr0 = (v) => (Number.isFinite(Number(v)) ? Number(v) : 0)

/** Build the POST /dashboard/snapshot body from loaded assignments. */
export function buildSnapshotPayload(assignments, todayIso) {
  let total = 0, red = 0, yellow = 0, green = 0, ready = 0, cost = 0, missing = 0, flags = 0
  const detail = []
  for (const a of assignments ?? []) {
    const r = a.review || {}
    const c = r.counts || {}
    const tier = ['RED', 'YELLOW', 'GREEN'].includes(r.hitl_tier) ? r.hitl_tier : null
    if (tier === 'RED') red++
    if (tier === 'YELLOW') yellow++
    if (tier === 'GREEN') green++
    if (tier) total++
    if (r.ready) ready++
    cost += numOr0(r.cost?.total_usd)
    missing += numOr0(c.missing)
    flags += numOr0(c.auditor_flags)
    detail.push({
      assignment_id: a.assignment_id,
      candidate: r.candidate ?? null,
      district: r.district ?? null,
      tier,
      ready: !!r.ready,
      cost: numOr0(r.cost?.total_usd),
      cost_by_agent: (r.cost?.by_agent && typeof r.cost.by_agent === 'object') ? r.cost.by_agent : {},
      valid: numOr0(c.valid),
      expiring: numOr0(c.expiring),
      expired: numOr0(c.expired),
      missing: numOr0(c.missing),
      unreadable: numOr0(c.unreadable),
      auditor_flags: numOr0(c.auditor_flags),
    })
  }
  // round cost to avoid float drift in the aggregate tile
  return { date: todayIso, aggregate: { total, red, yellow, green, ready, cost: Number(cost.toFixed(4)), missing, flags }, detail }
}

/** Reverse a detail row into the { assignment_id, review } shape charts consume. */
export function detailRowsToAssignments(rows) {
  const byId = new Map()
  for (const row of rows ?? []) {
    byId.set(row.assignment_id, {
      assignment_id: row.assignment_id,
      review: {
        hitl_tier: row.tier ?? null,
        ready: !!row.ready,
        candidate: row.candidate ?? null,
        district: row.district ?? null,
        cost: { total_usd: numOr0(row.cost), by_agent: (row.cost_by_agent && typeof row.cost_by_agent === 'object') ? row.cost_by_agent : {} },
        counts: {
          valid: numOr0(row.valid), expiring: numOr0(row.expiring), expired: numOr0(row.expired),
          missing: numOr0(row.missing), unreadable: numOr0(row.unreadable), auditor_flags: numOr0(row.auditor_flags),
        },
      },
    })
  }
  return [...byId.values()]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/lib/__tests__/dashboardHistory.test.js`
Expected: PASS — all tests green.

- [ ] **Step 5: Commit**

```bash
git add src/lib/dashboardHistory.js src/lib/__tests__/dashboardHistory.test.js
git commit -m "feat(dashboard): pure helpers for snapshot payload, range presets, row reshape"
```

---

### Task 4: Frontend API hooks (`api/dashboardHistory.js`)

**Files:**
- Create: `src/api/dashboardHistory.js`

**Interfaces:**
- Consumes: `EXCEL_API_BASE`, `NGROK_SKIP_HEADER` from `../config.js`.
- Produces:
  - `useDashboardRange(start, end, enabled)` → react-query result of `GET {EXCEL_API_BASE}/dashboard?start=&end=` → `{ aggregates, detail }`.
  - `postSnapshot(payload)` → `Promise` POSTing to `/dashboard/snapshot` with token + ngrok headers (best-effort; resolves regardless).

- [ ] **Step 1: Write the implementation** — `src/api/dashboardHistory.js`

(No unit test — this is thin I/O over `fetch`, matching `src/api/tracker.js` which is also untested. It is exercised via the DashboardPage integration in Task 6.)

```js
import { useQuery } from '@tanstack/react-query'
import { EXCEL_API_BASE, NGROK_SKIP_HEADER } from '../config.js'

const TOKEN = import.meta.env.VITE_CRED_TRACKER_TOKEN ?? ''

/** GET {EXCEL_API_BASE}/dashboard?start=&end= → { aggregates, detail }. */
export function useDashboardRange(start, end, enabled = true) {
  return useQuery({
    queryKey: ['dashboard-range', start, end],
    enabled: enabled && !!start && !!end,
    staleTime: 5 * 60 * 1000,
    retry: 0,
    queryFn: async () => {
      const url = `${EXCEL_API_BASE}/dashboard?start=${start}&end=${end}`
      const res = await fetch(url, { headers: NGROK_SKIP_HEADER })
      if (!res.ok) throw new Error(`Dashboard API ${res.status}`)
      return res.json()
    },
  })
}

/** Best-effort upsert of today's snapshot. Never throws to the caller. */
export function postSnapshot(payload) {
  return fetch(`${EXCEL_API_BASE}/dashboard/snapshot`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...NGROK_SKIP_HEADER,
      ...(TOKEN ? { 'X-Cred-Tracker-Token': TOKEN } : {}),
    },
    body: JSON.stringify(payload),
  }).then(() => {}).catch(() => {})
}
```

- [ ] **Step 2: Verify it imports cleanly (lint/build)**

Run: `npx eslint src/api/dashboardHistory.js`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add src/api/dashboardHistory.js
git commit -m "feat(dashboard): api hooks — useDashboardRange + postSnapshot"
```

---

### Task 5: DateRangeControl component

**Files:**
- Create: `src/components/dashboard/DateRangeControl.jsx`
- Test: `src/components/dashboard/__tests__/DateRangeControl.test.jsx`

**Interfaces:**
- Consumes: `useTokens` from `../../lib/theme.jsx`.
- Produces: `<DateRangeControl value={{ preset, start, end }} onChange={(next) => …} />`.
  - `preset` ∈ `'today' | '30' | '60' | '90' | 'custom'`.
  - Emits `onChange` with the full next `{ preset, start, end }`. For `'custom'`, `start`/`end` come from the two date inputs; for presets, the parent computes start/end (control just emits `{ preset }` and the parent fills the range) — to keep the control dumb, it emits `{ preset }` for non-custom and `{ preset: 'custom', start, end }` for custom edits.

- [ ] **Step 1: Write the failing test** — `src/components/dashboard/__tests__/DateRangeControl.test.jsx`

```jsx
import { describe, it, expect, vi } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'
import DateRangeControl from '../DateRangeControl.jsx'

describe('DateRangeControl', () => {
  it('renders the preset tabs', () => {
    renderWithProviders(<DateRangeControl value={{ preset: 'today', start: '', end: '' }} onChange={() => {}} />)
    expect(screen.getByRole('button', { name: /today/i })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /30 days/i })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /60 days/i })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /90 days/i })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /custom/i })).toBeInTheDocument()
  })

  it('emits the preset on tab click', () => {
    const onChange = vi.fn()
    renderWithProviders(<DateRangeControl value={{ preset: 'today', start: '', end: '' }} onChange={onChange} />)
    fireEvent.click(screen.getByRole('button', { name: /30 days/i }))
    expect(onChange).toHaveBeenCalledWith({ preset: '30' })
  })

  it('shows date inputs only in custom mode and emits custom range edits', () => {
    const onChange = vi.fn()
    renderWithProviders(<DateRangeControl value={{ preset: 'custom', start: '2026-07-01', end: '2026-07-06' }} onChange={onChange} />)
    const start = screen.getByLabelText(/start/i)
    expect(start).toBeInTheDocument()
    fireEvent.change(start, { target: { value: '2026-06-15' } })
    expect(onChange).toHaveBeenCalledWith({ preset: 'custom', start: '2026-06-15', end: '2026-07-06' })
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/components/dashboard/__tests__/DateRangeControl.test.jsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Write minimal implementation** — `src/components/dashboard/DateRangeControl.jsx`

```jsx
import { useTokens } from '../../lib/theme.jsx'

const TABS = [
  { key: 'today',  label: 'Today (Live)' },
  { key: '30',     label: 'Last 30 days' },
  { key: '60',     label: 'Last 60 days' },
  { key: '90',     label: 'Last 90 days' },
  { key: 'custom', label: 'Custom' },
]

export default function DateRangeControl({ value, onChange }) {
  const t = useTokens()
  const preset = value?.preset ?? 'today'

  const tab = (key, label) => {
    const active = preset === key
    return (
      <button
        key={key}
        onClick={() => onChange(key === 'custom'
          ? { preset: 'custom', start: value?.start || '', end: value?.end || '' }
          : { preset: key })}
        className="px-3 py-1.5 rounded-lg text-xs font-semibold transition-all"
        style={{
          background: active ? t.accent : 'transparent',
          color: active ? '#fff' : t.muted,
          border: `1px solid ${active ? t.accent : t.cardBorder}`,
          cursor: 'pointer',
          fontFamily: 'Geist,sans-serif',
        }}
      >
        {label}
      </button>
    )
  }

  return (
    <div className="flex items-center gap-2 flex-wrap">
      {TABS.map(({ key, label }) => tab(key, label))}
      {preset === 'custom' && (
        <div className="flex items-center gap-2 ml-1">
          <label className="text-[10px] uppercase tracking-wider" style={{ color: t.muted }} htmlFor="dr-start">Start</label>
          <input id="dr-start" type="date" value={value?.start || ''}
            onChange={(e) => onChange({ preset: 'custom', start: e.target.value, end: value?.end || '' })}
            className="rounded-lg px-2 py-1 text-xs"
            style={{ background: t.inputBg, border: `1px solid ${t.inputBorder}`, color: t.text }} />
          <label className="text-[10px] uppercase tracking-wider" style={{ color: t.muted }} htmlFor="dr-end">End</label>
          <input id="dr-end" type="date" value={value?.end || ''}
            onChange={(e) => onChange({ preset: 'custom', start: value?.start || '', end: e.target.value })}
            className="rounded-lg px-2 py-1 text-xs"
            style={{ background: t.inputBg, border: `1px solid ${t.inputBorder}`, color: t.text }} />
        </div>
      )}
    </div>
  )
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/components/dashboard/__tests__/DateRangeControl.test.jsx`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/dashboard/DateRangeControl.jsx src/components/dashboard/__tests__/DateRangeControl.test.jsx
git commit -m "feat(dashboard): DateRangeControl — preset tabs + custom date pickers"
```

---

### Task 6: Wire history into DashboardPage

**Files:**
- Modify: `src/pages/DashboardPage.jsx`

**Interfaces:**
- Consumes: `DateRangeControl`, `useDashboardRange`, `postSnapshot`, `buildSnapshotPayload`, `detailRowsToAssignments`, `presetRange`, `todayISO`.
- Produces: DashboardPage that renders live data + snapshots on load in "today" mode, and reshaped historical data in preset/custom modes.

- [ ] **Step 1: Add imports** — top of `src/pages/DashboardPage.jsx`, with the other imports:

```jsx
import { useRef, useState, useEffect } from 'react'
import DateRangeControl from '../components/dashboard/DateRangeControl.jsx'
import { useDashboardRange, postSnapshot } from '../api/dashboardHistory.js'
import { buildSnapshotPayload, detailRowsToAssignments, presetRange, todayISO } from '../lib/dashboardHistory.js'
```

- [ ] **Step 2: Snapshot-on-load in `DashboardContent`** — in `DashboardContent({ ids })`, after the `assignments` array is built (currently line ~64) and `anyLoading` is computed, add:

```jsx
  // Persist today's snapshot once, after all reviews have loaded. Best-effort;
  // never blocks or breaks the render. Fires once per mount (ref-guarded).
  const snapshotSent = useRef(false)
  useEffect(() => {
    if (!snapshotSent.current && ids.length > 0 && !anyLoading && assignments.length === ids.length) {
      snapshotSent.current = true
      postSnapshot(buildSnapshotPayload(assignments, todayISO()))
    }
  }, [anyLoading, assignments.length, ids.length]) // eslint-disable-line react-hooks/exhaustive-deps
```

- [ ] **Step 3: Lift the view state into `DashboardPage`** — replace the `DashboardPage` default export body so it owns range state and chooses the data source. Replace the current `export default function DashboardPage()` (lines ~136-159) with:

```jsx
function HistoryContent({ start, end }) {
  const { data, isLoading, error } = useDashboardRange(start, end)
  const t = useTokens()
  const rows = data?.detail ?? []
  const assignments = detailRowsToAssignments(rows)

  if (isLoading) return (
    <div className="flex flex-col items-center justify-center h-[40vh] gap-4">
      <Spinner size={32} color={t.accent} />
      <div className="text-sm" style={{ color: t.muted, fontFamily: 'Geist,sans-serif' }}>Loading history…</div>
    </div>
  )
  if (error) return (
    <div className="p-6"><EmptyState icon="⚡" title="Cannot load history"
      message={`${error.message}. Ensure the Dashboard API (excel-api :8002) is running.`} /></div>
  )
  if (!assignments.length) return (
    <div className="p-6"><EmptyState icon="🗓" title="No history yet"
      message={`No snapshots between ${start} and ${end}. Historical data accumulates from the first day the dashboard is opened — check back after a few days of runs.`} /></div>
  )
  return <DashboardBody assignments={assignments} rangeLabel={`${start} → ${end}`} anyLoading={false} loadedCount={assignments.length} idCount={assignments.length} />
}

export default function DashboardPage() {
  const t = useTokens()
  const { mode } = useConsoleMode()
  const [range, setRange] = useState({ preset: 'today', start: '', end: '' })

  // Resolve preset → concrete start/end (today is handled by the live path).
  const resolved = range.preset === 'custom'
    ? { start: range.start, end: range.end }
    : range.preset === 'today'
    ? null
    : presetRange(range.preset, todayISO())

  const { data: assignmentsData, isLoading, error } = useAssignments({ refetchInterval: 15_000, refetchIntervalInBackground: false })
  const ids = (assignmentsData?.assignment_ids ?? assignmentsData ?? []).map(String)
  const apiLabel = mode === 'live' ? 'Live Pipeline API (:5001)' : 'Cockpit API (:8001)'

  return (
    <div className="flex flex-col gap-4 p-6 max-w-[1400px] mx-auto">
      <DateRangeControl value={range} onChange={(next) => setRange((prev) => ({ ...prev, ...next }))} />

      {range.preset === 'today' ? (
        isLoading ? (
          <div className="flex flex-col items-center justify-center h-[40vh] gap-4">
            <Spinner size={32} color={t.accent} />
            <div className="text-sm" style={{ color: t.muted, fontFamily: 'Geist,sans-serif' }}>Connecting to {apiLabel}…</div>
          </div>
        ) : error ? (
          <div className="p-4"><EmptyState icon="⚡" title="Cannot connect to backend"
            message={`${error.message}. Ensure the ${apiLabel} is running.`} /></div>
        ) : (
          <DashboardContent ids={ids} />
        )
      ) : resolved?.start && resolved?.end ? (
        <HistoryContent start={resolved.start} end={resolved.end} />
      ) : (
        <div className="p-4"><EmptyState icon="🗓" title="Pick a date range" message="Choose a start and end date." /></div>
      )}
    </div>
  )
}
```

- [ ] **Step 4: Extract the shared body** — the current `DashboardContent` return JSX (the header + `DashboardStats` + the grids) is reused by both live and history. Refactor: keep `DashboardContent({ ids })` for the live path (it computes `assignments` from `useQueries` and calls the snapshot effect), and have it render a new `DashboardBody`. Extract the presentational part (everything currently returned by `DashboardContent`, lines ~73-132) into:

```jsx
function DashboardBody({ assignments, rangeLabel, anyLoading, loadedCount, idCount }) {
  const t = useTokens()
  const processedCount = assignments.filter(a => ['RED', 'YELLOW', 'GREEN'].includes(a.review?.hitl_tier)).length
  const today = new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' })
  const dateLine = rangeLabel ?? today
  return (
    <div className="flex flex-col gap-5 animate-fade-up">
      {/* ── Page header ── */}
      <div className="flex items-end justify-between gap-4">
        <div>
          <div className="flex items-center gap-3 mb-1">
            <span className="relative flex h-2 w-2">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full opacity-75"
                style={{ background: anyLoading ? '#C9871A' : '#1F8A4C' }} />
              <span className="relative inline-flex rounded-full h-2 w-2"
                style={{ background: anyLoading ? '#C9871A' : '#1F8A4C' }} />
            </span>
            <span className="text-[10px] font-bold tracking-[0.15em] uppercase"
              style={{ color: anyLoading ? '#C9871A' : '#1F8A4C', fontFamily: 'Geist,sans-serif' }}>
              {anyLoading ? `Loading ${loadedCount}/${idCount}` : (rangeLabel ? 'History' : 'Live')}
            </span>
          </div>
          <h1 className="font-bold leading-tight"
            style={{ fontSize: 30, color: t.textStrong, fontFamily: 'Geist,sans-serif', letterSpacing: '-0.01em', fontWeight: 700 }}>
            Credentialing Intelligence
          </h1>
          <p className="mt-1 text-sm" style={{ color: t.muted, fontFamily: 'Geist,sans-serif' }}>
            Portfolio overview · {processedCount} candidates processed
          </p>
        </div>
        <div className="text-right shrink-0">
          <div className="text-sm font-semibold tabnum" style={{ color: t.text, fontFamily: 'Geist,sans-serif' }}>{dateLine}</div>
          <div className="text-xs mt-1 tabnum" style={{ color: t.muted, fontFamily: 'JetBrains Mono,monospace' }}>
            {anyLoading ? `${loadedCount}/${idCount} loaded` : `${processedCount} candidates`}
          </div>
        </div>
      </div>

      <DashboardStats assignments={assignments} />

      <div className="grid gap-4" style={{ gridTemplateColumns: 'minmax(360px, 420px) 1fr' }}>
        <SectionCard title="Tier Distribution" accentColor="linear-gradient(180deg,#C0392B,#C9871A,#1F8A4C)" fullHeight>
          <TierDonut assignments={assignments} />
        </SectionCard>
        <SectionCard title="Act Now — Needs Review" accentColor="#EE6C4D" fullHeight>
          <NeedsReviewList assignments={assignments} />
        </SectionCard>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <SectionCard title="Document Status Breakdown" accentColor="#1DAEEF">
          <StatusBreakdown assignments={assignments} />
        </SectionCard>
        <SectionCard title="Pipeline Cost by Agent" accentColor="#3FC8EF">
          <CostByAgentBar assignments={assignments} />
        </SectionCard>
      </div>
    </div>
  )
}
```

And make `DashboardContent`'s return be:

```jsx
  return <DashboardBody assignments={assignments} anyLoading={anyLoading} loadedCount={loadedCount} idCount={ids.length} />
```

(Remove the now-duplicated header/grid JSX and the now-unused `today`/`processedCount` locals from `DashboardContent`, since `DashboardBody` owns them. Keep the `useQueries`, `assignments`, `loadedCount`, `anyLoading`, and the snapshot `useEffect` in `DashboardContent`. Note the outer padding/max-width moved to `DashboardPage`, so `DashboardBody` no longer sets `p-6 max-w-[1400px] mx-auto`.)

- [ ] **Step 5: Run the full frontend test suite + build**

Run: `npx vitest run && npm run build`
Expected: all tests pass; build succeeds. (No existing test imports `DashboardContent` directly — confirm with `grep -r "DashboardContent\|DashboardPage" src/**/__tests__` → no matches; if any exist, update them.)

- [ ] **Step 6: Manual verification**

Run the app (`npm run dev`) with excel-api up. Confirm: Today (Live) renders as before; opening it writes a row (`GET http://localhost:8002/dashboard?start=<today>&end=<today>` returns one aggregate + N detail rows); switching to "Last 30 days" shows history or the empty-state; Custom reveals two date pickers and querying a range renders the charts.

- [ ] **Step 7: Commit**

```bash
git add src/pages/DashboardPage.jsx
git commit -m "feat(dashboard): date-range tabs, snapshot-on-load, historical view via reshaped rows"
```

---

## FEATURE 2 — Realtime activity feed

### Task 7: Extend `useStepRun` to accumulate structured events

**Files:**
- Modify: `src/hooks/useStepRun.js`
- Test: `src/hooks/__tests__/useStepRun.events.test.js` (create)

**Interfaces:**
- Consumes: `reduceSseEvent`, `INITIAL_SSE_STATE` from `../run/sseReducer.js`.
- Produces: `useStepRun()` return object gains `events`, `agentsByAid`, `results` (in addition to existing `logLines`, `status`, etc.), derived from the SSE stream via `reduceSseEvent`.

- [ ] **Step 1: Write the failing test** — `src/hooks/__tests__/useStepRun.events.test.js`

We test the reducer wiring in isolation by importing the same reducer the hook uses, proving the accumulation contract the hook relies on. (The hook itself is thin glue over `openSSE` + this reducer; the reducer is the logic under test.)

```js
import { describe, it, expect } from 'vitest'
import { reduceSseEvent, INITIAL_SSE_STATE } from '../../run/sseReducer.js'

describe('step-run event accumulation (reducer used by useStepRun)', () => {
  it('accumulates agent events per assignment and completed results', () => {
    let s = { ...INITIAL_SSE_STATE }
    s = reduceSseEvent(s, 'assignment_start', { assignment_id: 42 })
    s = reduceSseEvent(s, 'agent_1_complete', { assignment_id: 42, duration_s: 1.2 })
    s = reduceSseEvent(s, 'agent_2_complete', { assignment_id: 42, duration_s: 0.8 })
    s = reduceSseEvent(s, 'assignment_done', { assignment_id: 42, review: { hitl_tier: 'GREEN' } })
    expect(s.agentsByAid['42']).toHaveLength(2)
    expect(s.results).toHaveLength(1)
    expect(s.results[0].review.hitl_tier).toBe('GREEN')
  })
})
```

- [ ] **Step 2: Run test to verify it passes already** (reducer exists)

Run: `npx vitest run src/hooks/__tests__/useStepRun.events.test.js`
Expected: PASS — this locks the reducer contract before we wire it into the hook.

- [ ] **Step 3: Wire the reducer into `useStepRun`** — modify `src/hooks/useStepRun.js`:

Add import at top:

```js
import { reduceSseEvent, INITIAL_SSE_STATE } from '../run/sseReducer.js'
```

Add SSE-derived state alongside `logLines` (after the `logLines` useState, ~line with `useState([])`):

```js
  const [sse, setSse] = useState(() => ({ ...INITIAL_SSE_STATE }))
```

In `connect`, replace the handlers so every event also feeds the reducer (keep the existing log behavior). Replace the `handlers` object in `connect` with:

```js
    const handlers = {
      log: (d) => { pushLog(sseLine(d)); setSse((s) => reduceSseEvent(s, 'log', d)) },
      '*': (type, d) => {
        if (type !== 'log') { pushLog(eventLogLine(type, d)); setSse((s) => reduceSseEvent(s, type, d)) }
      },
    }
```

Reset `sse` when a run starts and on resume — in `start`, after `setLogLines([])` add `setSse({ ...INITIAL_SSE_STATE })`; in `resume`, after `setLogLines([])` add `setSse({ ...INITIAL_SSE_STATE })`.

Add the new fields to the returned object (extend the existing `return {…}`):

```js
    events: sse.events,
    agentsByAid: sse.agentsByAid,
    results: sse.results,
```

- [ ] **Step 4: Run tests + build**

Run: `npx vitest run src/hooks && npm run build`
Expected: PASS; build OK.

- [ ] **Step 5: Commit**

```bash
git add src/hooks/useStepRun.js src/hooks/__tests__/useStepRun.events.test.js
git commit -m "feat(cockpit): useStepRun accumulates structured SSE events for the activity feed"
```

---

### Task 8: Pure activity/document helpers (`activityLog.js`)

**Files:**
- Create: `src/lib/activityLog.js`
- Test: `src/lib/__tests__/activityLog.test.js`

**Interfaces:**
- Produces:
  - `parseDocsFromLog(logLines)` → `string[]` of de-duplicated document filenames found in log text (matches file extensions, or lines mentioning download/saved).
  - `documentsFromReview(review)` → `string[]` of document basenames from a completed review payload (`checklist[].matched_files` + `unmatched_documents`), de-duplicated.
  - `basename(path)` → last path segment.

- [ ] **Step 1: Write the failing test** — `src/lib/__tests__/activityLog.test.js`

```js
import { describe, it, expect } from 'vitest'
import { parseDocsFromLog, documentsFromReview, basename } from '../activityLog.js'

describe('basename', () => {
  it('takes the last segment of a windows or posix path', () => {
    expect(basename('C:\\docs\\tb_test.pdf')).toBe('tb_test.pdf')
    expect(basename('folder/id_card.png')).toBe('id_card.png')
  })
})

describe('parseDocsFromLog', () => {
  it('extracts filenames with known extensions and dedupes', () => {
    const lines = [
      'Downloading TB_Test.pdf ...',
      '✓ saved folder/id_card.PNG',
      'Agent 4 — Doc Matcher (3.2s)',
      'Downloading TB_Test.pdf ...', // dup
    ]
    expect(parseDocsFromLog(lines)).toEqual(['TB_Test.pdf', 'id_card.PNG'])
  })
  it('returns [] when nothing matches', () => {
    expect(parseDocsFromLog(['Agent 1 complete', 'starting run'])).toEqual([])
  })
})

describe('documentsFromReview', () => {
  it('collects matched_files across checklist plus unmatched_documents, deduped by basename', () => {
    const review = {
      checklist: [
        { requirement: 'TB', matched_files: ['a/tb.pdf'] },
        { requirement: 'ID', matched_file: 'b/id.png' },
      ],
      unmatched_documents: ['c/extra.pdf', 'a/tb.pdf'],
    }
    expect(documentsFromReview(review)).toEqual(['tb.pdf', 'id.png', 'extra.pdf'])
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/lib/__tests__/activityLog.test.js`
Expected: FAIL — module not found.

- [ ] **Step 3: Write minimal implementation** — `src/lib/activityLog.js`

```js
// Pure helpers for the activity feed. No React. Unit-tested.

const DOC_RE = /[\w .()\-]+\.(pdf|png|jpe?g|docx?|tiff?)\b/gi

export function basename(p) {
  return String(p || '').split(/[\\/]/).pop()
}

/** Best-effort: pull document filenames out of raw log lines. Heuristic. */
export function parseDocsFromLog(logLines) {
  const seen = new Set()
  const out = []
  for (const line of logLines ?? []) {
    const matches = String(line).match(DOC_RE)
    if (!matches) continue
    for (const m of matches) {
      const name = basename(m.trim())
      if (!seen.has(name)) { seen.add(name); out.push(name) }
    }
  }
  return out
}

/** Reliable: documents referenced by a completed review payload. */
export function documentsFromReview(review) {
  const seen = new Set()
  const out = []
  const add = (f) => {
    const name = basename(f)
    if (name && !seen.has(name)) { seen.add(name); out.push(name) }
  }
  for (const c of review?.checklist ?? []) {
    if (Array.isArray(c.matched_files)) c.matched_files.forEach(add)
    else if (c.matched_file) add(c.matched_file)
  }
  for (const d of review?.unmatched_documents ?? []) add(d)
  return out
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/lib/__tests__/activityLog.test.js`
Expected: PASS.

> Note: the `parseDocsFromLog` regex is deliberately conservative (extension-anchored). If real backend logs use a different phrasing, this only affects the *live* best-effort list; the reliable `documentsFromReview` list is unaffected. Confirm against real logs during manual verification in Task 10.

- [ ] **Step 5: Commit**

```bash
git add src/lib/activityLog.js src/lib/__tests__/activityLog.test.js
git commit -m "feat(activity): pure helpers to extract documents from logs and review payloads"
```

---

### Task 9: ActivityFeed component

**Files:**
- Create: `src/components/run/ActivityFeed.jsx`
- Test: `src/components/run/__tests__/ActivityFeed.test.jsx`

**Interfaces:**
- Consumes: `useTokens`, `Spinner`, `parseDocsFromLog`, `documentsFromReview`.
- Produces: `<ActivityFeed status={…} events={[]} agentsByAid={{}} results={[]} logLines={[]} />`.
  - `status`: `'idle' | 'running' | 'paused' | 'complete' | 'done' | 'failed' | 'aborted'` (accepts both step-run and batch status vocab).
  - Shows a loading state when `running` and no events yet; otherwise a timeline built from `events`, plus a documents list per completed assignment from `results`.

- [ ] **Step 1: Write the failing test** — `src/components/run/__tests__/ActivityFeed.test.jsx`

```jsx
import { describe, it, expect } from 'vitest'
import { screen } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'
import ActivityFeed from '../ActivityFeed.jsx'

describe('ActivityFeed', () => {
  it('shows a loading state when running with no events', () => {
    renderWithProviders(<ActivityFeed status="running" events={[]} agentsByAid={{}} results={[]} logLines={[]} />)
    expect(screen.getByText(/waiting for the pipeline/i)).toBeInTheDocument()
  })

  it('renders timeline entries for started + agent-complete + done events', () => {
    const events = [
      { type: 'assignment_start', assignment_id: 42 },
      { type: 'agent_4_complete', assignment_id: 42, duration_s: 3.2 },
      { type: 'assignment_done', assignment_id: 42, review: { hitl_tier: 'GREEN' } },
    ]
    const results = [{ assignment_id: 42, review: { hitl_tier: 'GREEN', checklist: [{ matched_files: ['x/tb.pdf'] }], unmatched_documents: [] } }]
    renderWithProviders(<ActivityFeed status="complete" events={events} agentsByAid={{ 42: events.filter(e => e.type.startsWith('agent_')) }} results={results} logLines={[]} />)
    expect(screen.getByText(/#42/)).toBeInTheDocument()
    expect(screen.getByText(/document matcher/i)).toBeInTheDocument()
    expect(screen.getByText(/tb\.pdf/i)).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/components/run/__tests__/ActivityFeed.test.jsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Write minimal implementation** — `src/components/run/ActivityFeed.jsx`

```jsx
import { useTokens } from '../../lib/theme.jsx'
import Spinner from '../common/Spinner.jsx'
import { parseDocsFromLog, documentsFromReview } from '../../lib/activityLog.js'

const AGENT_NAMES = {
  agent_1_complete: 'Document Scan',
  agent_2_complete: 'Assignment Parser',
  agent_3_complete: 'Requirement Mapper',
  agent_4_complete: 'Document Matcher',
  agent_5_complete: 'Checklist Builder',
  agent_5_5_complete: 'Triage Gate',
  agent_6_complete: 'Final Reviewer',
}
const TIER_EMOJI = { RED: '🔴', YELLOW: '🟡', GREEN: '🟢' }

function aidOf(e) {
  const raw = e.assignment_id
  if (raw == null) return null
  return typeof raw === 'object' ? String(raw.id ?? raw.assignment_id ?? '') : String(raw)
}

/** Turn one SSE event into a display row, or null to skip. */
function describe(e) {
  const aid = aidOf(e)
  const tag = aid ? `#${aid}` : ''
  if (e.type === 'assignment_start') return { color: '#1DAEEF', icon: '▶', text: `Assignment ${tag} — processing started` }
  if (e.type === 'assignment_done' || e.type === 'assignment_complete') {
    const tier = e.review?.hitl_tier
    return { color: '#1F8A4C', icon: '✓', text: `Assignment ${tag} complete${tier ? ` — ${TIER_EMOJI[tier] ?? ''} ${tier}` : ''}` }
  }
  if (e.type === 'assignment_failed') return { color: '#C0392B', icon: '✕', text: `Assignment ${tag} failed` }
  if (e.type === 'assignment_aborted') return { color: '#C0392B', icon: '■', text: `Assignment ${tag} aborted` }
  const name = AGENT_NAMES[e.type]
  if (name) {
    const n = e.type.replace('agent_', '').replace('_complete', '').replace('_', '.')
    const dur = e.duration_s != null ? ` — ${Number(e.duration_s).toFixed(1)}s` : ''
    return { color: '#3FC8EF', icon: '✓', text: `Agent ${n} · ${name}${tag ? ` ${tag}` : ''}${dur}` }
  }
  return null
}

function DocChips({ docs, t }) {
  if (!docs.length) return null
  return (
    <div className="flex flex-wrap gap-1.5 mt-1.5">
      {docs.map((d, i) => (
        <span key={i} className="text-[10px] px-2 py-0.5 rounded-lg"
          style={{ color: t.accent, border: `1px solid ${t.accent}44`, fontFamily: 'JetBrains Mono,monospace' }}>
          📄 {d}
        </span>
      ))}
    </div>
  )
}

export default function ActivityFeed({ status, events = [], agentsByAid = {}, results = [], logLines = [] }) {
  const t = useTokens()
  const running = status === 'running' || status === 'paused'
  const rows = events.map(describe).filter(Boolean)

  // Loading state: running but nothing has streamed yet.
  if (running && rows.length === 0) {
    return (
      <div className="rounded-2xl p-8 flex flex-col items-center justify-center gap-4"
        style={{ background: t.cardBg, border: `1px solid ${t.cardBorder}`, minHeight: 200 }}>
        <Spinner size={28} color={t.accent} />
        <div className="text-sm font-semibold" style={{ color: t.textStrong, fontFamily: 'Geist,sans-serif' }}>
          Waiting for the pipeline…
        </div>
        <div className="flex flex-col gap-2 w-full max-w-sm mt-2">
          {[0, 1, 2].map((i) => (
            <div key={i} className="h-3 rounded animate-pulse"
              style={{ background: t.isDark ? 'rgba(29,174,239,0.10)' : 'rgba(0,82,128,0.07)', width: `${90 - i * 15}%` }} />
          ))}
        </div>
      </div>
    )
  }

  // Documents by assignment: reliable from completed reviews, plus best-effort from logs.
  const doneDocs = {}
  for (const r of results) {
    const aid = String(r.assignment_id)
    doneDocs[aid] = documentsFromReview(r.review)
  }
  const liveDocs = running ? parseDocsFromLog(logLines) : []

  return (
    <div className="rounded-2xl p-4" style={{ background: t.cardBg, border: `1px solid ${t.cardBorder}` }}>
      <div className="text-[10px] font-bold tracking-widest uppercase mb-3" style={{ color: t.sectionLabel }}>
        Activity
      </div>
      <div className="flex flex-col gap-2">
        {rows.map((r, i) => {
          // Attach the reliable doc list to completion rows.
          const isDone = /complete/.test(r.text)
          const aidMatch = r.text.match(/#(\d+)/)
          const docs = isDone && aidMatch ? (doneDocs[aidMatch[1]] ?? []) : []
          return (
            <div key={i} className="flex items-start gap-2 animate-log-line">
              <span className="shrink-0 w-4 text-center" style={{ color: r.color }}>{r.icon}</span>
              <div className="min-w-0">
                <span className="text-[12px]" style={{ color: t.text, fontFamily: 'Geist,sans-serif' }}>{r.text}</span>
                {docs.length > 0 && (
                  <>
                    <div className="text-[10px] mt-1" style={{ color: t.muted }}>Documents processed ({docs.length})</div>
                    <DocChips docs={docs} t={t} />
                  </>
                )}
              </div>
            </div>
          )
        })}
        {rows.length === 0 && (
          <div className="text-xs py-4 text-center" style={{ color: t.muted }}>No activity yet.</div>
        )}
      </div>

      {liveDocs.length > 0 && (
        <div className="mt-3 pt-3" style={{ borderTop: `1px solid ${t.divider}` }}>
          <div className="text-[10px] font-bold tracking-widest uppercase mb-1.5" style={{ color: t.sectionLabel }}>
            Documents seen (live)
          </div>
          <DocChips docs={liveDocs} t={t} />
        </div>
      )}
    </div>
  )
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/components/run/__tests__/ActivityFeed.test.jsx`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/run/ActivityFeed.jsx src/components/run/__tests__/ActivityFeed.test.jsx
git commit -m "feat(activity): ActivityFeed component — loading state, event timeline, document chips"
```

---

### Task 10: Swap TerminalLog → ActivityFeed in both views

**Files:**
- Modify: `src/components/cockpit/StepRunPanel.jsx`
- Modify: `src/components/run/LiveStream.jsx`

**Interfaces:**
- Consumes: `ActivityFeed` (Task 9); `useStepRun` now exposes `events/agentsByAid/results` (Task 7).

- [ ] **Step 1: StepRunPanel — replace the telemetry block.** In `src/components/cockpit/StepRunPanel.jsx`:

Remove the `TerminalLog` import (line 7) and add:

```jsx
import ActivityFeed from '../run/ActivityFeed.jsx'
```

Remove the `logCollapsed` state (line 50) — no longer used.

Replace the `<div>` "Live telemetry" block (lines ~85-89) with:

```jsx
          <ActivityFeed
            status={s?.status}
            events={run.events}
            agentsByAid={run.agentsByAid}
            results={run.results}
            logLines={run.logLines}
          />
```

Update the failed-status copy (line 14): change `sub: 'Check the live telemetry below.'` to `sub: 'See the activity feed below.'`.

- [ ] **Step 2: LiveStream — replace the terminal log.** In `src/components/run/LiveStream.jsx`:

Remove the `TerminalLog` import (line 4) and add:

```jsx
import ActivityFeed from './ActivityFeed.jsx'
```

Remove the `logCollapsed` state (line 219). Replace the closing `{/* ── Terminal log ── */}` block (line ~331-332, `<TerminalLog .../>`) with:

```jsx
      {/* ── Activity feed ── */}
      <ActivityFeed status={status} events={events} agentsByAid={agentsByAid} results={results} logLines={logLines} />
```

- [ ] **Step 3: Check for other TerminalLog importers**

Run: `grep -rl "TerminalLog" src`
Expected: only `src/components/run/TerminalLog.jsx` itself remains (its former importers are now migrated). If any test referenced the "Live telemetry" text or TerminalLog, update it. Leave `TerminalLog.jsx` in place (unused) — deleting it is optional and out of scope.

- [ ] **Step 4: Run tests + build**

Run: `npx vitest run && npm run build`
Expected: PASS; build OK. If a `StepRunPanel`/`LiveStream` test asserted on "Live telemetry"/"Pipeline Log", update it to assert on "Activity".

- [ ] **Step 5: Manual verification**

`npm run dev`, start a step-run in the Cockpit and a batch on the Run page. Confirm: the raw terminal is gone; a loading state shows before events; the activity timeline lists assignment start, each agent completing with timing, and completion with tier; completed assignments show a "Documents processed" chip list; if the backend logs filenames, the "Documents seen (live)" strip appears during the run.

- [ ] **Step 6: Commit**

```bash
git add src/components/cockpit/StepRunPanel.jsx src/components/run/LiveStream.jsx
git commit -m "feat(activity): replace raw telemetry with ActivityFeed in step-run and run-pipeline views"
```

---

## FEATURE 3 — Agent-3 credentialer button verify

### Task 11: Verify + test the Agent-3 reassign control

**Files:**
- Modify: `src/components/cockpit/__tests__/GatePanel.test.jsx`

**Interfaces:**
- Consumes: existing `GatePanel` with `Agent3Reassign` (renders when `awaiting.agent === '3'`), `useCredentialers` mock.

- [ ] **Step 1: Strengthen the credentialers mock + add the Agent-3 test.** In `src/components/cockpit/__tests__/GatePanel.test.jsx`:

Change the credentialers mock (line 5) so the roster is non-empty:

```jsx
vi.mock('../../../api/credentialers.js', () => ({ useCredentialers: () => ({ data: { credentialers: [
  { name: 'Pat Cortez', email: 'pat@aequor.com', workload: 12 },
] } }) }))
```

Add this test inside the `describe('GatePanel', …)` block:

```jsx
  it('Agent-3 gate renders the reassign dropdown and queues credentialer overrides on approve', () => {
    const onApprove = vi.fn()
    const a3 = { agent: '3', name: 'Assign', output: {}, verifier: { verdict: 'PASS', checks: [] } }
    renderWithProviders(<GatePanel aid="42" awaiting={a3} by="me@x.com" onApprove={onApprove} onAbort={() => {}} onOpenDoc={() => {}} />)

    // The reassign control is present at the Agent-3 gate.
    const select = screen.getByRole('combobox')
    expect(screen.getByText(/reassign credentialer/i)).toBeInTheDocument()

    // Choosing a credentialer then approving sends name + email overrides.
    fireEvent.change(select, { target: { value: JSON.stringify({ name: 'Pat Cortez', email: 'pat@aequor.com', workload: 12 }) } })
    fireEvent.click(screen.getByRole('button', { name: /approve/i }))
    expect(onApprove).toHaveBeenCalledWith(expect.objectContaining({
      credentialer_name: 'Pat Cortez',
      credentialer_email: 'pat@aequor.com',
    }))
  })
```

- [ ] **Step 2: Run the test**

Run: `npx vitest run src/components/cockpit/__tests__/GatePanel.test.jsx`
Expected: PASS. If it FAILS, the reassign control has a real defect — inspect `Agent3Reassign` in `src/components/cockpit/GatePanel.jsx` (verify it renders under `ag === '3'`, the `<select>` `onChange` parses the option value and calls `setOv('credentialer_name', …)` / `setOv('credentialer_email', …)`), fix the defect, and re-run until green. Confirm the option value is a JSON string of `{ name, email, workload }` (matches the roster shape) so the test's `value` matches an actual `<option>`.

- [ ] **Step 3: Manual verification**

`npm run dev`, drive an assignment in the Cockpit step-run to the **Agent 3** gate (or use an assignment already paused there). Confirm the "Reassign credentialer" dropdown lists the roster with workload, and selecting one shows the "⚡ fix(es) queued" banner. Approving proceeds to the next agent with the chosen credentialer.

- [ ] **Step 4: Commit**

```bash
git add src/components/cockpit/__tests__/GatePanel.test.jsx
git commit -m "test(cockpit): verify Agent-3 credentialer reassign queues name+email overrides"
```

---

## Self-Review (completed during authoring)

- **Spec coverage:** stg.Cred_Dashboard + Detail (Task 1) ✓; snapshot write auto-on-load (Tasks 2,4,6) ✓; date range + 30/60/90 + custom (Tasks 5,6) ✓; both aggregate+detail tables (Task 1) ✓; empty-state caveat (Task 6) ✓; remove raw telemetry entirely from both views (Task 10) ✓; loading state + activity timeline (Task 9) ✓; docs from review + best-effort log parse (Tasks 8,9) ✓; useStepRun structured events (Task 7) ✓; Agent-3 verify + test (Task 11) ✓.
- **Placeholder scan:** none — every code/step is concrete.
- **Type consistency:** `buildSnapshotPayload`/`detailRowsToAssignments` (Task 3) shapes match `validateSnapshot`/`getRange` (Task 1) and the POST body (Task 2); `useStepRun` fields `events/agentsByAid/results` (Task 7) match `ActivityFeed` props (Task 9) and its wiring (Task 10). Review field names match the Global Constraints.
- **Known heuristic:** `parseDocsFromLog` reliability depends on backend log phrasing (flagged in Task 8/10); reliable doc list comes from the review payload.

# Cockpit Run+Review / Batch / Watchdog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three new cockpit tabs (RUN + REVIEW, BATCH, WATCHDOG) and repair STEP RUN / MAIL drift vs `src/context.html`, reusing the existing cockpit component + API-hook foundation.

**Architecture:** New React-Query API hooks (`api/*.js`) feed small focused presentational components (`components/cockpit/**`). A shared `useRunJob` hook drives non-gated `/run` jobs over the existing SSE plumbing for both Batch and Run+Review. Shared components (`RequirementsTable`, `ChecklistReview`, `CostTierSummary`) serve the new Run+Review tab AND heal the Agent-4/Agent-5 gate + step-run completion drift.

**Tech Stack:** React 19, `@tanstack/react-query` v5, react-router-dom v7, Tailwind CSS v4 (`@tailwindcss/vite`), Vitest v4 + `@testing-library/react`.

## Global Constraints

- **Do NOT modify `.env` or `src/config.js` base-URL selection.** All calls go through `apiClient` (`src/lib/apiClient.js`): `apiClient.get(path)`, `apiClient.post(path, body)`, `apiClient.del(path, body)`; `documentUrl(aid, file)` for raw docs.
- **Every React-Query key is namespaced with `mk(...)`** from `src/console/modeKey.js` (e.g. `mk('watchdog_results')`).
- **Styling — pure Tailwind classes in every NEW file.** No `useTokens()`, no inline `style={{}}` color objects in new files. Use theme-aware color utilities from `src/styles/globals.css` `@theme`: `bg-brand-surface`, `bg-brand-bg-2`, `text-brand-sky`, `text-brand-primary`, `text-text-strong`, `text-text`, `text-text-muted`, status utils `text-status-valid` / `text-status-expired` / `text-status-missing`, tier utils `text-tier-red` / `tier-yellow` / `tier-green` (and `/15` opacity bg variants), fonts `font-mono`. For the themed hairline border use the arbitrary value `border-[var(--border)]` (the `--border` CSS var flips on `[data-theme="dark"]`). Terminals stay dark on purpose: `bg-[#020409] text-[#41e58c]`.
- **Edits to EXISTING `useTokens`-based files** (MailPanel, StepRunPanel, GatePanel, AssignmentRail, PendingEmailPreview) follow that file's existing `useTokens()` convention for the small glue they add — do NOT rewrite them to pure Tailwind. Purity is required only in new files.
- **Never regress STEP RUN / MAIL.** Existing tests in `src/components/cockpit/__tests__/` must stay green.
- **Test runner:** `npm test` (= `vitest run`). Single file: `npx vitest run <path>`. Render via `renderWithProviders` from `src/test-utils/render.jsx` (wraps QueryClient + ThemeProvider). Mock hooks with `vi.mock(...)` at module top; import the component AFTER the mock.
- **Reused SSE events already registered** in `src/lib/sse.js` `EVENTS` (`batch_start`, `assignment_done`, `agent_*_complete`, `job_complete`, `job_failed`, `log`) — no SSE changes needed.
- Commit after each task with the shown message.

---

## Task 1: Watchdog API hooks

**Files:**
- Create: `src/api/watchdog.js`
- Test: `src/api/__tests__/watchdog.test.js`

**Interfaces:**
- Produces: `useWatchdogStatus()`, `useWatchdogResults()`, `useWatchdogResult(aid)`, `useWatchdogScan()`.

- [ ] **Step 1: Write the failing test**

```js
// src/api/__tests__/watchdog.test.js
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

const get = vi.fn()
const post = vi.fn()
vi.mock('../../lib/apiClient.js', () => ({ apiClient: { get: (...a) => get(...a), post: (...a) => post(...a) } }))

import { useWatchdogStatus, useWatchdogResults, useWatchdogResult, useWatchdogScan } from '../watchdog.js'

function wrap() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return ({ children }) => <QueryClientProvider client={qc}>{children}</QueryClientProvider>
}

describe('watchdog api', () => {
  beforeEach(() => { get.mockReset(); post.mockReset(); get.mockResolvedValue({}); post.mockResolvedValue({ ok: true }) })

  it('useWatchdogStatus hits /watchdog/status', async () => {
    get.mockResolvedValue({ scanner_thread_alive: true, interval_min: 15 })
    const { result } = renderHook(() => useWatchdogStatus(), { wrapper: wrap() })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(get).toHaveBeenCalledWith('/watchdog/status')
  })

  it('useWatchdogResults hits /watchdog/results', async () => {
    get.mockResolvedValue({ results: [] })
    const { result } = renderHook(() => useWatchdogResults(), { wrapper: wrap() })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(get).toHaveBeenCalledWith('/watchdog/results')
  })

  it('useWatchdogResult hits /watchdog/results/<aid> and is disabled without aid', async () => {
    const { result: off } = renderHook(() => useWatchdogResult(null), { wrapper: wrap() })
    expect(off.current.fetchStatus).toBe('idle')
    get.mockResolvedValue({ found: true })
    const { result } = renderHook(() => useWatchdogResult(42), { wrapper: wrap() })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(get).toHaveBeenCalledWith('/watchdog/results/42')
  })

  it('useWatchdogScan posts /watchdog/scan', async () => {
    const { result } = renderHook(() => useWatchdogScan(), { wrapper: wrap() })
    await result.current.mutateAsync()
    expect(post).toHaveBeenCalledWith('/watchdog/scan', {})
  })
})
```

- [ ] **Step 2: Run the test — expect failure**

Run: `npx vitest run src/api/__tests__/watchdog.test.js`
Expected: FAIL — cannot resolve `../watchdog.js`.

- [ ] **Step 3: Implement**

```js
// src/api/watchdog.js
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { apiClient } from '../lib/apiClient.js'
import { mk } from '../console/modeKey.js'

/** GET /watchdog/status — scanner heartbeat. */
export function useWatchdogStatus() {
  return useQuery({
    queryKey: mk('watchdog_status'),
    queryFn: () => apiClient.get('/watchdog/status'),
    refetchInterval: 30_000,
    staleTime: 10_000,
    retry: 0,
  })
}

/** GET /watchdog/results — cases with re-reconciled document changes. */
export function useWatchdogResults() {
  return useQuery({
    queryKey: mk('watchdog_results'),
    queryFn: () => apiClient.get('/watchdog/results'),
    staleTime: 15_000,
  })
}

/** GET /watchdog/results/<aid> — one case's document deltas. */
export function useWatchdogResult(aid) {
  return useQuery({
    queryKey: mk('watchdog_result', aid),
    queryFn: () => apiClient.get(`/watchdog/results/${aid}`),
    enabled: !!aid,
    staleTime: 15_000,
  })
}

/** POST /watchdog/scan — force a Bullhorn document rescan. */
export function useWatchdogScan() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () => apiClient.post('/watchdog/scan', {}),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: mk('watchdog_results') })
      qc.invalidateQueries({ queryKey: mk('watchdog_status') })
    },
  })
}
```

- [ ] **Step 4: Run the test — expect pass**

Run: `npx vitest run src/api/__tests__/watchdog.test.js`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/api/watchdog.js src/api/__tests__/watchdog.test.js
git commit -m "feat(cockpit): watchdog api hooks"
```

---

## Task 2: Lookup + Requirements API hooks

**Files:**
- Create: `src/api/lookup.js`, `src/api/requirements.js`
- Test: `src/api/__tests__/lookup.test.js`

**Interfaces:**
- Produces: `useLookupId()` (mutation, `mutateAsync(id)` → `GET /lookup/<id>`), `useRequirements(aid)` (`GET /requirements/<aid>`).

- [ ] **Step 1: Write the failing test**

```js
// src/api/__tests__/lookup.test.js
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

const get = vi.fn()
vi.mock('../../lib/apiClient.js', () => ({ apiClient: { get: (...a) => get(...a) } }))

import { useLookupId } from '../lookup.js'
import { useRequirements } from '../requirements.js'

function wrap() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return ({ children }) => <QueryClientProvider client={qc}>{children}</QueryClientProvider>
}

describe('lookup + requirements api', () => {
  beforeEach(() => { get.mockReset(); get.mockResolvedValue({}) })

  it('useLookupId encodes the id into /lookup/<id>', async () => {
    get.mockResolvedValue({ kind: 'placement' })
    const { result } = renderHook(() => useLookupId(), { wrapper: wrap() })
    await result.current.mutateAsync('2670415')
    expect(get).toHaveBeenCalledWith('/lookup/2670415')
  })

  it('useRequirements hits /requirements/<aid> and is disabled without aid', async () => {
    const { result: off } = renderHook(() => useRequirements(null), { wrapper: wrap() })
    expect(off.current.fetchStatus).toBe('idle')
    get.mockResolvedValue({ requirements: [] })
    const { result } = renderHook(() => useRequirements(149142), { wrapper: wrap() })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(get).toHaveBeenCalledWith('/requirements/149142')
  })
})
```

- [ ] **Step 2: Run the test — expect failure**

Run: `npx vitest run src/api/__tests__/lookup.test.js`
Expected: FAIL — modules missing.

- [ ] **Step 3: Implement both files**

```js
// src/api/lookup.js
import { useMutation } from '@tanstack/react-query'
import { apiClient } from '../lib/apiClient.js'

/** GET /lookup/<id> — resolve a Bullhorn candidate id OR assignment/placement id.
 *  Returns { kind:'placement', placement } or { kind:'candidate', candidate, placements[] }. */
export function useLookupId() {
  return useMutation({
    mutationFn: (id) => apiClient.get(`/lookup/${encodeURIComponent(String(id).trim())}`),
  })
}
```

```js
// src/api/requirements.js
import { useQuery } from '@tanstack/react-query'
import { apiClient } from '../lib/apiClient.js'
import { mk } from '../console/modeKey.js'

/** GET /requirements/<aid> — the DB district checklist for the Agent-4 table. */
export function useRequirements(aid) {
  return useQuery({
    queryKey: mk('requirements', aid),
    queryFn: () => apiClient.get(`/requirements/${aid}`),
    enabled: !!aid,
    staleTime: 30_000,
  })
}
```

- [ ] **Step 4: Run the test — expect pass**

Run: `npx vitest run src/api/__tests__/lookup.test.js`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/api/lookup.js src/api/requirements.js src/api/__tests__/lookup.test.js
git commit -m "feat(cockpit): lookup + requirements api hooks"
```

---

## Task 3: Held Bullhorn Notes API hooks

**Files:**
- Create: `src/api/bullhornNotes.js`
- Test: `src/api/__tests__/bullhornNotes.test.js`

**Interfaces:**
- Produces: `usePendingBullhorn()`, `usePendingBullhornNote(aid)`, `useApproveBullhorn(aid)`, `useRejectBullhorn(aid)`.

- [ ] **Step 1: Write the failing test**

```js
// src/api/__tests__/bullhornNotes.test.js
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

const get = vi.fn()
const post = vi.fn()
vi.mock('../../lib/apiClient.js', () => ({ apiClient: { get: (...a) => get(...a), post: (...a) => post(...a) } }))

import { usePendingBullhorn, usePendingBullhornNote, useApproveBullhorn, useRejectBullhorn } from '../bullhornNotes.js'

function wrap() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return ({ children }) => <QueryClientProvider client={qc}>{children}</QueryClientProvider>
}

describe('bullhorn notes api', () => {
  beforeEach(() => { get.mockReset(); post.mockReset(); get.mockResolvedValue({}); post.mockResolvedValue({ ok: true }) })

  it('list hits /pending_bullhorn', async () => {
    get.mockResolvedValue({ pending: [] })
    const { result } = renderHook(() => usePendingBullhorn(), { wrapper: wrap() })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(get).toHaveBeenCalledWith('/pending_bullhorn')
  })

  it('single note hits /pending_bullhorn/<aid>', async () => {
    get.mockResolvedValue({ found: true })
    const { result } = renderHook(() => usePendingBullhornNote(7), { wrapper: wrap() })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(get).toHaveBeenCalledWith('/pending_bullhorn/7')
  })

  it('approve posts /pending_bullhorn/<aid>/approve', async () => {
    const { result } = renderHook(() => useApproveBullhorn(7), { wrapper: wrap() })
    await result.current.mutateAsync()
    expect(post).toHaveBeenCalledWith('/pending_bullhorn/7/approve', {})
  })

  it('reject posts /pending_bullhorn/<aid>/reject with reason', async () => {
    const { result } = renderHook(() => useRejectBullhorn(7), { wrapper: wrap() })
    await result.current.mutateAsync('bad note')
    expect(post).toHaveBeenCalledWith('/pending_bullhorn/7/reject', { reason: 'bad note' })
  })
})
```

- [ ] **Step 2: Run — expect failure**

Run: `npx vitest run src/api/__tests__/bullhornNotes.test.js`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement**

```js
// src/api/bullhornNotes.js
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { apiClient } from '../lib/apiClient.js'
import { mk } from '../console/modeKey.js'

/** GET /pending_bullhorn — held Bullhorn notes awaiting approval. */
export function usePendingBullhorn() {
  return useQuery({
    queryKey: mk('pending_bullhorn'),
    queryFn: () => apiClient.get('/pending_bullhorn'),
    staleTime: 15_000,
  })
}

/** GET /pending_bullhorn/<aid> — one held note with its comments. */
export function usePendingBullhornNote(aid) {
  return useQuery({
    queryKey: mk('pending_bullhorn', aid),
    queryFn: () => apiClient.get(`/pending_bullhorn/${aid}`),
    enabled: !!aid,
    staleTime: 15_000,
  })
}

/** POST /pending_bullhorn/<aid>/approve — write the note to Bullhorn. */
export function useApproveBullhorn(aid) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () => apiClient.post(`/pending_bullhorn/${aid}/approve`, {}),
    onSuccess: () => qc.invalidateQueries({ queryKey: mk('pending_bullhorn') }),
  })
}

/** POST /pending_bullhorn/<aid>/reject — discard the held note. */
export function useRejectBullhorn(aid) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (reason) => apiClient.post(`/pending_bullhorn/${aid}/reject`, { reason: reason || 'rejected via cockpit' }),
    onSuccess: () => qc.invalidateQueries({ queryKey: mk('pending_bullhorn') }),
  })
}
```

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/api/__tests__/bullhornNotes.test.js`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/api/bullhornNotes.js src/api/__tests__/bullhornNotes.test.js
git commit -m "feat(cockpit): held bullhorn notes api hooks"
```

---

## Task 4: Single-job status hook (`useJob`)

**Files:**
- Modify: `src/api/runs.js` (append)
- Test: `src/api/__tests__/runs.job.test.js`

**Interfaces:**
- Produces: `useJob(jobId)` — `GET /jobs/<jobId>`, polls every 3s until `status ∈ {complete, failed}`, `enabled: !!jobId`.

- [ ] **Step 1: Write the failing test**

```js
// src/api/__tests__/runs.job.test.js
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

const get = vi.fn()
vi.mock('../../lib/apiClient.js', () => ({ apiClient: { get: (...a) => get(...a) } }))

import { useJob } from '../runs.js'

function wrap() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return ({ children }) => <QueryClientProvider client={qc}>{children}</QueryClientProvider>
}

describe('useJob', () => {
  beforeEach(() => { get.mockReset() })

  it('is idle without a jobId', () => {
    const { result } = renderHook(() => useJob(null), { wrapper: wrap() })
    expect(result.current.fetchStatus).toBe('idle')
  })

  it('fetches /jobs/<id>', async () => {
    get.mockResolvedValue({ status: 'complete', result: { ok: 2, total: 2 } })
    const { result } = renderHook(() => useJob('job-1'), { wrapper: wrap() })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(get).toHaveBeenCalledWith('/jobs/job-1')
    expect(result.current.data.result.ok).toBe(2)
  })
})
```

- [ ] **Step 2: Run — expect failure**

Run: `npx vitest run src/api/__tests__/runs.job.test.js`
Expected: FAIL — `useJob` is not exported.

- [ ] **Step 3: Implement (append to `src/api/runs.js`)**

```js
// append to src/api/runs.js
const JOB_TERMINAL = new Set(['complete', 'failed'])

/** GET /jobs/<id> — a single run job; polls until terminal. */
export function useJob(jobId) {
  return useQuery({
    queryKey: mk('job', jobId),
    queryFn: () => apiClient.get(`/jobs/${jobId}`),
    enabled: !!jobId,
    refetchInterval: (query) => (JOB_TERMINAL.has(query.state.data?.status) ? false : 3_000),
  })
}
```

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/api/__tests__/runs.job.test.js`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/api/runs.js src/api/__tests__/runs.job.test.js
git commit -m "feat(cockpit): useJob single-job status hook"
```

---

## Task 5: `useRunJob` orchestration hook

**Files:**
- Create: `src/hooks/useRunJob.js`
- Test: `src/hooks/__tests__/useRunJob.test.jsx`

**Interfaces:**
- Consumes: `useRun` + `useJob` (`api/runs.js`), `openSSE`/`sseLine` (`lib/sse.js`), `reduceSseEvent`/`INITIAL_SSE_STATE` (`run/sseReducer.js`), `mk`.
- Produces: `useRunJob()` → `{ start(ids, wipe), reset(), jobId, status, logLines, agentsByAid, results, job }` where `status ∈ {'idle','running','complete','failed'}`.

- [ ] **Step 1: Write the failing test**

```jsx
// src/hooks/__tests__/useRunJob.test.jsx
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderHook, act, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

const post = vi.fn()
const get = vi.fn()
vi.mock('../../lib/apiClient.js', () => ({ apiClient: { post: (...a) => post(...a), get: (...a) => get(...a) } }))

// Capture the SSE handlers so the test can push events synchronously.
let sseHandlers = null
const closeSpy = vi.fn()
vi.mock('../../lib/sse.js', () => ({
  sseLine: (d) => (typeof d === 'string' ? d : d?.line ?? ''),
  openSSE: (_id, handlers) => { sseHandlers = handlers; return closeSpy },
}))

import { useRunJob } from '../useRunJob.js'

function wrap() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return ({ children }) => <QueryClientProvider client={qc}>{children}</QueryClientProvider>
}

describe('useRunJob', () => {
  beforeEach(() => { post.mockReset(); get.mockReset(); closeSpy.mockReset(); sseHandlers = null
    post.mockResolvedValue({ job_id: 'j1' }); get.mockResolvedValue({ status: 'running' }) })

  it('starts idle', () => {
    const { result } = renderHook(() => useRunJob(), { wrapper: wrap() })
    expect(result.current.status).toBe('idle')
    expect(result.current.jobId).toBe(null)
  })

  it('start() posts /run and opens the stream', async () => {
    const { result } = renderHook(() => useRunJob(), { wrapper: wrap() })
    await act(async () => { await result.current.start([149142], true) })
    expect(post).toHaveBeenCalledWith('/run', { ids: [149142], wipe: true })
    await waitFor(() => expect(result.current.jobId).toBe('j1'))
    expect(result.current.status).toBe('running')
  })

  it('accumulates log lines and results from SSE, flips to complete on job_complete', async () => {
    const { result } = renderHook(() => useRunJob(), { wrapper: wrap() })
    await act(async () => { await result.current.start([1], false) })
    act(() => { sseHandlers.log({ line: 'hello' }) })
    act(() => { sseHandlers['*']('assignment_done', { assignment_id: 1 }) })
    act(() => { sseHandlers['*']('job_complete', {}) })
    await waitFor(() => expect(result.current.status).toBe('complete'))
    expect(result.current.logLines).toContain('hello')
    expect(result.current.results.length).toBe(1)
  })
})
```

- [ ] **Step 2: Run — expect failure**

Run: `npx vitest run src/hooks/__tests__/useRunJob.test.jsx`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement**

```js
// src/hooks/useRunJob.js
import { useState, useRef, useCallback, useEffect } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { openSSE, sseLine } from '../lib/sse.js'
import { useRun, useJob } from '../api/runs.js'
import { reduceSseEvent, INITIAL_SSE_STATE } from '../run/sseReducer.js'
import { mk } from '../console/modeKey.js'

const MAX_LOG = 600

/** Drive a non-gated /run job (batch or run+review) to completion over SSE + job poll. */
export function useRunJob() {
  const [jobId, setJobId] = useState(null)
  const [logLines, setLogLines] = useState([])
  const [sse, setSse] = useState(() => ({ ...INITIAL_SSE_STATE }))
  const closeRef = useRef(null)
  const qc = useQueryClient()

  const runMut = useRun()
  const job = useJob(jobId)

  const pushLog = useCallback((line) => {
    setLogLines(p => { const n = [...p, line]; return n.length > MAX_LOG ? n.slice(-MAX_LOG) : n })
  }, [])

  const closeStream = useCallback(() => {
    if (closeRef.current) { closeRef.current(); closeRef.current = null }
  }, [])

  const connect = useCallback((id) => {
    closeStream()
    const handlers = {
      log: (d) => { pushLog(sseLine(d)); setSse(s => reduceSseEvent(s, 'log', d)) },
      '*': (type, d) => {
        if (type !== 'log') {
          pushLog(`━━ ${type.replace(/_/g, ' ').toUpperCase()}`)
          setSse(s => reduceSseEvent(s, type, d))
        }
      },
    }
    closeRef.current = openSSE(id, handlers, () => {})
  }, [pushLog, closeStream])

  const start = useCallback(async (ids, wipe) => {
    closeStream()
    setLogLines([])
    setSse({ ...INITIAL_SSE_STATE })
    const res = await runMut.mutateAsync({ ids, wipe: !!wipe })
    if (res?.job_id) { setJobId(res.job_id); connect(res.job_id) }
    return res
  }, [runMut.mutateAsync, connect, closeStream])

  const reset = useCallback(() => {
    closeStream(); setJobId(null); setLogLines([]); setSse({ ...INITIAL_SSE_STATE })
  }, [closeStream])

  // Terminal detection: job poll OR sse status. On terminal, close the stream + refresh rail.
  const jobStatus = job.data?.status
  const status = !jobId ? 'idle'
    : jobStatus === 'complete' || sse.status === 'done' ? 'complete'
    : jobStatus === 'failed' || sse.status === 'failed' ? 'failed'
    : 'running'

  useEffect(() => {
    if (status === 'complete' || status === 'failed') {
      closeStream()
      qc.invalidateQueries({ queryKey: mk('bullhorn_assignments') })
    }
  }, [status, closeStream, qc])

  useEffect(() => () => closeStream(), [closeStream])

  return {
    start, reset, jobId, status,
    logLines,
    agentsByAid: sse.agentsByAid,
    results: sse.results,
    job: job.data,
  }
}
```

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/hooks/__tests__/useRunJob.test.jsx`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/hooks/useRunJob.js src/hooks/__tests__/useRunJob.test.jsx
git commit -m "feat(cockpit): useRunJob orchestration hook"
```

---

## Task 6: `CostTierSummary` shared component

**Files:**
- Create: `src/components/cockpit/CostTierSummary.jsx`
- Test: `src/components/cockpit/__tests__/CostTierSummary.test.jsx`

**Interfaces:**
- Produces: `<CostTierSummary review={...} />` — renders tier badge + total cost badge + per-agent cost line. `review = { candidate, district, hitl_tier, cost: { total_usd, calls, by_agent } }`.

- [ ] **Step 1: Write the failing test**

```jsx
// src/components/cockpit/__tests__/CostTierSummary.test.jsx
import { describe, it, expect } from 'vitest'
import { screen } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'
import CostTierSummary from '../CostTierSummary.jsx'

describe('CostTierSummary', () => {
  it('shows tier, total cost and per-agent breakdown', () => {
    renderWithProviders(<CostTierSummary review={{
      candidate: 'Jane Doe', district: 'PS 1', hitl_tier: 'YELLOW',
      cost: { total_usd: 0.1234, calls: 5, by_agent: { 5: 0.05, 6: 0.0734 } },
    }} />)
    expect(screen.getByText(/TIER YELLOW/)).toBeInTheDocument()
    expect(screen.getByText(/\$0.1234/)).toBeInTheDocument()
    expect(screen.getByText(/A5/)).toBeInTheDocument()
  })

  it('renders without cost data', () => {
    renderWithProviders(<CostTierSummary review={{ candidate: 'X', district: 'Y', hitl_tier: 'GREEN' }} />)
    expect(screen.getByText(/TIER GREEN/)).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run — expect failure**

Run: `npx vitest run src/components/cockpit/__tests__/CostTierSummary.test.jsx`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement**

```jsx
// src/components/cockpit/CostTierSummary.jsx
const TIER_CLASS = {
  RED: 'text-tier-red border-tier-red bg-tier-red/10',
  YELLOW: 'text-tier-yellow border-tier-yellow bg-tier-yellow/10',
  GREEN: 'text-tier-green border-tier-green bg-tier-green/10',
}

export default function CostTierSummary({ review }) {
  if (!review) return null
  const tier = review.hitl_tier || '—'
  const cost = review.cost || {}
  const total = cost.total_usd
  const byAgent = cost.by_agent || {}
  const tierCls = TIER_CLASS[tier] || 'text-text-muted border-[var(--border)] bg-brand-bg-2'
  return (
    <div className="mb-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="rounded-full border border-tier-green bg-tier-green/10 px-2.5 py-0.5 text-[11px] font-bold text-tier-green">✓ ALL AGENTS RUN</span>
        <span className="text-[15px] font-bold text-text-strong">{review.candidate || ''}{review.district ? ` · ${review.district}` : ''}</span>
        <span className={`rounded-full border px-2.5 py-0.5 text-[11px] font-bold ${tierCls}`}>TIER {tier}</span>
        {total != null && (
          <span className="rounded-full border border-tier-yellow bg-tier-yellow/10 px-2.5 py-0.5 text-[11px] font-bold text-tier-yellow">💰 ${Number(total).toFixed(4)}</span>
        )}
      </div>
      {total != null && (
        <div className="mt-2 text-[12px] text-text-muted">
          OpenAI cost: <b className="text-text">${Number(total).toFixed(4)}</b> · {cost.calls || 0} call(s)
          {Object.keys(byAgent).length > 0 && (
            <> · {Object.entries(byAgent).map(([k, v]) => `A${k} $${Number(v).toFixed(4)}`).join(' · ')}</>
          )}
        </div>
      )}
    </div>
  )
}
```

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/components/cockpit/__tests__/CostTierSummary.test.jsx`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/CostTierSummary.jsx src/components/cockpit/__tests__/CostTierSummary.test.jsx
git commit -m "feat(cockpit): CostTierSummary component"
```

---

## Task 7: `RequirementsTable` shared component (Agent-4)

**Files:**
- Create: `src/components/cockpit/RequirementsTable.jsx`
- Test: `src/components/cockpit/__tests__/RequirementsTable.test.jsx`

**Interfaces:**
- Produces: `<RequirementsTable data={...} />`. `data = { matched_client_name, client_match_status, match_confidence, fuzzy_match_score, source, hitl_requirements[], requirements[] }`; each requirement `{ title, category, concept, validity_window_days, validity_anchor, fulfillment }`.

- [ ] **Step 1: Write the failing test**

```jsx
// src/components/cockpit/__tests__/RequirementsTable.test.jsx
import { describe, it, expect } from 'vitest'
import { screen } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'
import RequirementsTable from '../RequirementsTable.jsx'

describe('RequirementsTable', () => {
  it('renders matched district + requirement rows', () => {
    renderWithProviders(<RequirementsTable data={{
      matched_client_name: 'Springfield USD', client_match_status: 'MATCH',
      match_confidence: 'high', fuzzy_match_score: 92.5,
      requirements: [{ title: 'TB Test', category: 'Health', concept: 'tb', validity_window_days: 365, validity_anchor: 'test date' }],
    }} />)
    expect(screen.getByText('Springfield USD')).toBeInTheDocument()
    expect(screen.getByText('TB Test')).toBeInTheDocument()
    expect(screen.getByText(/1 requirement/)).toBeInTheDocument()
  })

  it('shows the NO_CLIENT_MATCH banner', () => {
    renderWithProviders(<RequirementsTable data={{ client_match_status: 'NO_CLIENT_MATCH', fuzzy_match_score: 40, requirements: [] }} />)
    expect(screen.getByText(/NO DISTRICT MATCH/i)).toBeInTheDocument()
  })

  it('handles missing data', () => {
    renderWithProviders(<RequirementsTable data={null} />)
    expect(screen.getByText(/no requirements data/i)).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run — expect failure**

Run: `npx vitest run src/components/cockpit/__tests__/RequirementsTable.test.jsx`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement**

```jsx
// src/components/cockpit/RequirementsTable.jsx
const CONF_CLASS = {
  high: 'text-tier-green border-tier-green bg-tier-green/10',
  ambiguous: 'text-tier-yellow border-tier-yellow bg-tier-yellow/10',
}
function statusClass(st) {
  if (st === 'FOUND_VALID') return 'text-tier-green border-tier-green bg-tier-green/10'
  if (st === 'MISSING' || st === 'FOUND_WRONG_PERSON' || st === 'FOUND_EXPIRED') return 'text-tier-red border-tier-red bg-tier-red/10'
  return 'text-tier-yellow border-tier-yellow bg-tier-yellow/10'
}

export default function RequirementsTable({ data }) {
  if (!data || typeof data !== 'object') return <div className="text-[12px] text-text-muted">no requirements data</div>
  const mc = data.match_confidence || 'none'
  const score = data.fuzzy_match_score != null ? `${Number(data.fuzzy_match_score).toFixed(1)}%` : '—'
  const reqs = data.requirements || []
  const hasFul = reqs.some(r => r.fulfillment !== undefined)
  return (
    <div>
      <div className="mb-2.5 rounded-xl border border-[var(--border)] bg-brand-bg-2 p-3 text-[12.5px]">
        <div className="text-text-muted">Matched District</div>
        <div className="text-text-strong">
          <b>{data.matched_client_name || '—'}</b>{' '}
          <span className={`ml-1 rounded-full border px-2 py-0.5 text-[11px] font-bold ${CONF_CLASS[mc] || 'text-tier-red border-tier-red bg-tier-red/10'}`}>{mc} · {score}</span>
        </div>
      </div>

      {(data.hitl_requirements || []).map((f, i) => (
        <div key={i} className="mb-2 rounded-xl border border-[var(--border)] border-l-2 border-l-tier-yellow bg-tier-yellow/5 px-4 py-2.5">
          <div className="text-[13px] font-bold text-text-strong">⚠ {f.flag || 'HITL'}</div>
          <div className="text-[11.5px] text-text-muted">{f.reason || ''}</div>
        </div>
      ))}

      {data.client_match_status === 'NO_CLIENT_MATCH' && (
        <div className="rounded-xl border border-tier-red bg-tier-red/10 px-4 py-2.5 text-[13px] font-bold text-tier-red">
          🛑 NO DISTRICT MATCH IN DB — best score {score}
          <div className="text-[11px] font-normal opacity-90">a human must confirm the district / supply requirements</div>
        </div>
      )}
      {data.client_match_status === 'FALLBACK_CHECKLIST' && (
        <div className="mb-2 rounded-xl border border-tier-yellow bg-tier-yellow/10 px-4 py-2.5 text-[13px] font-bold text-tier-yellow">
          ⚠ DISTRICT NOT IN DB — showing a default checklist
        </div>
      )}

      {reqs.length > 0 && (
        <div className="max-h-[360px] overflow-auto rounded-xl border border-[var(--border)] bg-brand-bg-2 p-1.5">
          <table className="w-full border-collapse text-[12.5px]">
            <thead>
              <tr className="text-left text-[10px] uppercase tracking-widest text-text-muted">
                <th className="p-2">#</th><th className="p-2">Required Document</th><th className="p-2">Category</th>
                <th className="p-2">Concept</th><th className="p-2">Validity</th>{hasFul && <th className="p-2">Doc Status</th>}
              </tr>
            </thead>
            <tbody>
              {reqs.map((r, i) => (
                <tr key={i} className="border-t border-[var(--border)]">
                  <td className="p-2 text-text-muted">{i + 1}</td>
                  <td className="p-2"><b className="text-brand-sky">{r.title || ''}</b></td>
                  <td className="p-2 text-text">{r.category || '—'}</td>
                  <td className="p-2 text-text">{r.concept || '—'}</td>
                  <td className="p-2 text-text">{r.validity_window_days != null ? `${r.validity_window_days} days${r.validity_anchor ? ` from ${r.validity_anchor}` : ''}` : '—'}</td>
                  {hasFul && <td className="p-2"><span className={`rounded-full border px-2 py-0.5 text-[10px] font-bold ${statusClass(r.fulfillment)}`}>{r.fulfillment || '—'}</span></td>}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <div className="mt-1 text-[12px] text-text-muted">{reqs.length} requirement(s) on this district's checklist</div>
    </div>
  )
}
```

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/components/cockpit/__tests__/RequirementsTable.test.jsx`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/RequirementsTable.jsx src/components/cockpit/__tests__/RequirementsTable.test.jsx
git commit -m "feat(cockpit): RequirementsTable (agent-4) component"
```

---

## Task 8: `UnmatchedDocsPanel` + `ChecklistReview` (Agent-5)

**Files:**
- Create: `src/components/cockpit/UnmatchedDocsPanel.jsx`, `src/components/cockpit/ChecklistReview.jsx`
- Test: `src/components/cockpit/__tests__/ChecklistReview.test.jsx`

**Interfaces:**
- Consumes: `OigBanner` (`./OigBanner.jsx`).
- Produces:
  - `<UnmatchedDocsPanel review={...} onOpenDoc={(file)=>{}} />`
  - `<ChecklistReview review={...} mode={'view'|'correct'} onOpenDoc={(file)=>{}} onQueue={(requirement, value)=>{}} />` — `review = { oig_screen, checklist: [{ requirement, status, confidence, matched_files[], reason, holder_name, expiration_date, auditor_concern, confidence_breakdown }], unmatched_documents[], unmatched_detail[] }`. In `correct` mode each item exposes a status `<select>` + a multi-file checkbox picker and calls `onQueue(requirement, { status?, matched_files?, matched_file? })`.

- [ ] **Step 1: Write the failing test**

```jsx
// src/components/cockpit/__tests__/ChecklistReview.test.jsx
import { describe, it, expect, vi } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'
import ChecklistReview from '../ChecklistReview.jsx'

const REVIEW = {
  oig_screen: { status: 'CLEAR' },
  checklist: [
    { requirement: 'TB Test', status: 'FOUND_VALID', confidence: 88, matched_files: ['tb.pdf'], reason: 'ok', holder_name: 'Jane', expiration_date: '2027-01-01' },
    { requirement: 'Background Check', status: 'MISSING', confidence: 10, matched_files: [] },
  ],
  unmatched_documents: ['random.pdf'],
}

describe('ChecklistReview', () => {
  it('renders items and statuses in view mode', () => {
    renderWithProviders(<ChecklistReview review={REVIEW} mode="view" />)
    expect(screen.getByText('TB Test')).toBeInTheDocument()
    expect(screen.getByText('Background Check')).toBeInTheDocument()
    expect(screen.getByText('FOUND_VALID')).toBeInTheDocument()
  })

  it('queues a fix in correct mode', () => {
    const onQueue = vi.fn()
    renderWithProviders(<ChecklistReview review={REVIEW} mode="correct" onQueue={onQueue} />)
    // expand the first item, change status, queue
    fireEvent.click(screen.getByText('TB Test'))
    const sel = screen.getAllByRole('combobox')[0]
    fireEvent.change(sel, { target: { value: 'FOUND_EXPIRED' } })
    fireEvent.click(screen.getAllByText('+ queue fix')[0])
    expect(onQueue).toHaveBeenCalledWith('TB Test', expect.objectContaining({ status: 'FOUND_EXPIRED' }))
  })
})
```

- [ ] **Step 2: Run — expect failure**

Run: `npx vitest run src/components/cockpit/__tests__/ChecklistReview.test.jsx`
Expected: FAIL — modules missing.

- [ ] **Step 3: Implement `UnmatchedDocsPanel.jsx`**

```jsx
// src/components/cockpit/UnmatchedDocsPanel.jsx
export default function UnmatchedDocsPanel({ review, onOpenDoc = () => {} }) {
  const cl = review?.checklist || []
  const um = review?.unmatched_detail || (review?.unmatched_documents || []).map(f => ({ file: f, bucket: 'NOT_REQUIRED', note: '' }))
  if (!um.length) return null
  const matched = new Set([].concat(...cl.map(c => c.matched_files || [])).map(f => String(f).toLowerCase()))
  const missing = cl.filter(c => c.status === 'MISSING').length
  const review0 = um.filter(d => d.bucket === 'REVIEW')
  return (
    <div className="mb-3 rounded-xl border border-[var(--border)] border-l-2 border-l-tier-yellow bg-tier-yellow/5 px-4 py-3">
      <div className="text-[13px] font-bold text-text-strong">
        📄 {matched.size + um.length} document(s) read · {matched.size} matched a requirement ·{' '}
        <span className="text-tier-yellow">{um.length} matched nothing</span> · {missing}/{cl.length} still missing
      </div>
      <div className="mt-1 text-[11.5px] text-text-muted">
        These files are on record but are not any of this assignment's required items{review0.length ? ` — ${review0.length} worth a closer look` : ''}.
      </div>
      {um.map((d, i) => (
        <div key={i} className="mt-1.5 flex items-center gap-2 border-t border-[var(--border)] pt-1.5 text-[12px]">
          <button onClick={() => onOpenDoc(d.file)} className="rounded-md border border-[var(--border)] px-2 py-0.5 text-brand-sky">👁</button>
          <span className="min-w-0 flex-[0_0_38%] truncate text-brand-sky">{d.file}</span>
          <span className="italic text-text opacity-80">{d.doc_type || 'unknown type'}</span>
          <span className={`rounded-full border px-2 py-0.5 text-[10px] font-bold ${d.bucket === 'REVIEW' ? 'text-tier-yellow border-tier-yellow bg-tier-yellow/10' : 'text-text-muted border-[var(--border)]'}`}>
            {d.bucket === 'REVIEW' ? 'REVIEW' : 'not required'}
          </span>
          <span className="ml-auto truncate text-text-muted">{d.note || ''}</span>
        </div>
      ))}
    </div>
  )
}
```

- [ ] **Step 4: Implement `ChecklistReview.jsx`**

```jsx
// src/components/cockpit/ChecklistReview.jsx
import { useState } from 'react'
import OigBanner from './OigBanner.jsx'
import UnmatchedDocsPanel from './UnmatchedDocsPanel.jsx'

const STATUSES = ['FOUND_VALID', 'MISSING', 'FOUND_EXPIRED', 'FOUND_EXPIRES_SOON', 'FOUND_EXPIRES_DURING', 'FOUND_WRONG_PERSON', 'UNREADABLE']
function statusClass(st) {
  if (st === 'FOUND_VALID') return 'text-tier-green border-tier-green bg-tier-green/10'
  if (st === 'MISSING' || st === 'FOUND_WRONG_PERSON' || st === 'FOUND_EXPIRED') return 'text-tier-red border-tier-red bg-tier-red/10'
  return 'text-tier-yellow border-tier-yellow bg-tier-yellow/10'
}
function ringColor(conf) { return conf >= 80 ? 'text-tier-green' : conf >= 50 ? 'text-tier-yellow' : 'text-tier-red' }

function ChecklistItem({ c, allDocs, mode, onOpenDoc, onQueue }) {
  const [open, setOpen] = useState(false)
  const [status, setStatus] = useState('')
  const [picked, setPicked] = useState(() => new Set((c.matched_files || []).map(f => String(f).toLowerCase())))
  const files = c.matched_files || []
  const toggle = (d) => setPicked(prev => { const n = new Set(prev); const k = String(d).toLowerCase(); n.has(k) ? n.delete(k) : n.add(k); return n })
  const queue = () => {
    const val = {}
    if (status) val.status = status
    const chosen = allDocs.filter(d => picked.has(String(d).toLowerCase()))
    if (chosen.length) { val.matched_files = chosen; val.matched_file = chosen[0] }
    if (Object.keys(val).length) onQueue?.(c.requirement, val)
  }
  return (
    <div className="mb-2.5 overflow-hidden rounded-xl border border-[var(--border)] bg-brand-bg-2">
      <div onClick={() => setOpen(o => !o)} className="flex cursor-pointer items-center gap-2.5 px-3.5 py-2.5">
        {c.confidence != null && (
          <span className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-full border border-[var(--border)] text-[10.5px] font-bold ${ringColor(c.confidence)}`}>{c.confidence}</span>
        )}
        <span className="flex-1 text-[13px] font-semibold text-text-strong">{c.requirement}</span>
        {files.length > 0 && <span className="max-w-[200px] truncate rounded-md border border-brand-sky/40 px-2 py-0.5 text-[10.5px] text-brand-sky">📎 {files[0]}{files.length > 1 ? ` +${files.length - 1}` : ''}</span>}
        <span className={`rounded-full border px-2 py-0.5 text-[10px] font-bold ${statusClass(c.status)}`}>{c.status || '?'}</span>
        <span className="text-[11px] text-text-muted">{open ? '▾' : '▸'}</span>
      </div>
      {open && (
        <div className="border-t border-[var(--border)] px-4 py-3">
          <div className="text-[11.5px] text-text-muted">{c.reason || ''}</div>
          <div className="mt-1.5 text-[11.5px] text-text-muted">holder: <b className="text-text">{c.holder_name || '—'}</b> · expires: <b className="text-text">{c.expiration_date || '—'}</b>{c.auditor_concern ? ` · ⚠ ${c.auditor_concern}` : ''}</div>
          {c.confidence_breakdown && (
            <div className="mt-1.5 text-[11.5px] text-text-muted">score: {Object.entries(c.confidence_breakdown).map(([k, v]) => `${k} ${v >= 0 ? '+' : ''}${v}`).join(' · ')}</div>
          )}
          <div className="mt-2 flex flex-wrap gap-2">
            {files.map((f, i) => (
              <button key={i} onClick={() => onOpenDoc?.(f)} className="rounded-md border border-[var(--border)] px-2.5 py-1 text-[11px] text-brand-sky">👁 {f}</button>
            ))}
          </div>
          {mode === 'correct' && (
            <div className="mt-3 flex flex-wrap items-start gap-2.5">
              <select value={status} onChange={e => setStatus(e.target.value)} className="rounded-lg border border-[var(--border)] bg-brand-surface px-2.5 py-1.5 text-[12px] text-text">
                <option value="">status: keep</option>
                {STATUSES.map(s => <option key={s} value={s}>{s}</option>)}
              </select>
              <div className="min-w-[240px] flex-1">
                <div className="mb-1 text-[10.5px] text-text-muted">documents (tick all that apply)</div>
                <div className="max-h-[130px] overflow-auto rounded-lg border border-[var(--border)] bg-brand-surface px-2 py-1">
                  {allDocs.map((d, j) => (
                    <label key={j} className="flex cursor-pointer items-center gap-2 py-0.5 text-[11px] text-text">
                      <input type="checkbox" checked={picked.has(String(d).toLowerCase())} onChange={() => toggle(d)} />
                      <span onClick={(e) => { e.preventDefault(); onOpenDoc?.(d) }} className="opacity-60">👁</span>
                      <span className="truncate">{d}</span>
                    </label>
                  ))}
                </div>
              </div>
              <button onClick={queue} className="rounded-lg border border-[var(--border)] px-3 py-1.5 text-[12px] text-text-muted hover:text-brand-sky">+ queue fix</button>
            </div>
          )}
        </div>
      )}
    </div>
  )
}

export default function ChecklistReview({ review, mode = 'view', onOpenDoc = () => {}, onQueue }) {
  if (!review) return <div className="text-[12px] text-text-muted">review unavailable</div>
  const checklist = review.checklist || []
  const allDocs = [...new Set([].concat(...checklist.map(c => c.matched_files || []), review.unmatched_documents || []))].sort()
  return (
    <div>
      <OigBanner oig={review.oig_screen} />
      <UnmatchedDocsPanel review={review} onOpenDoc={onOpenDoc} />
      <div className="mb-2 text-[10px] font-bold uppercase tracking-widest text-text-muted">Checklist — see the evidence</div>
      {checklist.map((c, i) => (
        <ChecklistItem key={i} c={c} allDocs={allDocs} mode={mode} onOpenDoc={onOpenDoc} onQueue={onQueue} />
      ))}
    </div>
  )
}
```

- [ ] **Step 5: Run — expect pass**

Run: `npx vitest run src/components/cockpit/__tests__/ChecklistReview.test.jsx`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add src/components/cockpit/UnmatchedDocsPanel.jsx src/components/cockpit/ChecklistReview.jsx src/components/cockpit/__tests__/ChecklistReview.test.jsx
git commit -m "feat(cockpit): ChecklistReview + UnmatchedDocsPanel (agent-5 evidence)"
```

---

## Task 9: `ThinkingCharacter` loading cartoon

**Files:**
- Create: `src/components/cockpit/ThinkingCharacter.jsx`
- Test: `src/components/cockpit/__tests__/ThinkingCharacter.test.jsx`

**Interfaces:**
- Produces: `<ThinkingCharacter label="Thinking…" />` — a friendly cartoon robot that visibly "thinks/loads" (bobbing body, blinking eyes, pinging antenna, a thought bubble with three bouncing dots) plus a caption. Shown by Batch (Task 10) and Run+Review (Task 13) while a run is processing, in place of a log terminal. Pure Tailwind (theme color utilities + built-in `animate-*`); inline SVG, no external assets.

- [ ] **Step 1: Write the failing test**

```jsx
// src/components/cockpit/__tests__/ThinkingCharacter.test.jsx
import { describe, it, expect } from 'vitest'
import { screen } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'
import ThinkingCharacter from '../ThinkingCharacter.jsx'

describe('ThinkingCharacter', () => {
  it('renders the default label', () => {
    renderWithProviders(<ThinkingCharacter />)
    expect(screen.getByText(/thinking/i)).toBeInTheDocument()
  })
  it('renders a custom label', () => {
    renderWithProviders(<ThinkingCharacter label="Running all agents…" />)
    expect(screen.getByText(/running all agents/i)).toBeInTheDocument()
  })
  it('exposes a status role for accessibility', () => {
    renderWithProviders(<ThinkingCharacter />)
    expect(screen.getByRole('status')).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run — expect failure**

Run: `npx vitest run src/components/cockpit/__tests__/ThinkingCharacter.test.jsx`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement**

```jsx
// src/components/cockpit/ThinkingCharacter.jsx
// A friendly cartoon robot shown while a run is processing. Pure Tailwind:
// theme color utilities + built-in animations, inline SVG, no external assets.
export default function ThinkingCharacter({ label = 'Thinking…' }) {
  return (
    <div className="flex flex-col items-center justify-center gap-4 rounded-2xl border border-[var(--border)] bg-brand-surface py-10"
      role="status" aria-live="polite">
      <div className="relative">
        {/* thought bubble with bouncing dots */}
        <div className="absolute -right-7 -top-4 flex items-center gap-1 rounded-full bg-brand-bg-2 px-2.5 py-1.5 shadow-sm">
          <span className="h-1.5 w-1.5 rounded-full bg-brand-sky animate-bounce [animation-delay:-300ms]" />
          <span className="h-1.5 w-1.5 rounded-full bg-brand-sky animate-bounce [animation-delay:-150ms]" />
          <span className="h-1.5 w-1.5 rounded-full bg-brand-sky animate-bounce" />
        </div>
        {/* robot, gently bobbing */}
        <svg width="104" height="104" viewBox="0 0 104 104" fill="none"
          className="animate-bounce [animation-duration:2.4s]" role="img" aria-label="thinking robot">
          {/* antenna */}
          <line x1="52" y1="16" x2="52" y2="28" className="stroke-brand-sky" strokeWidth="3" strokeLinecap="round" />
          <circle cx="52" cy="12" r="5" className="fill-brand-sky animate-ping" />
          <circle cx="52" cy="12" r="4" className="fill-brand-sky" />
          {/* ears */}
          <rect x="14" y="48" width="7" height="16" rx="3.5" className="fill-brand-mid" />
          <rect x="83" y="48" width="7" height="16" rx="3.5" className="fill-brand-mid" />
          {/* head */}
          <rect x="21" y="28" width="62" height="50" rx="16" className="fill-brand-bg-2 stroke-brand-sky" strokeWidth="2.5" />
          {/* eyes (blink via pulse) */}
          <circle cx="40" cy="50" r="6" className="fill-brand-sky animate-pulse" />
          <circle cx="64" cy="50" r="6" className="fill-brand-sky animate-pulse [animation-delay:250ms]" />
          {/* cheeks */}
          <circle cx="33" cy="62" r="3" className="fill-brand-accent opacity-60" />
          <circle cx="71" cy="62" r="3" className="fill-brand-accent opacity-60" />
          {/* smile */}
          <path d="M42 63 Q52 71 62 63" className="stroke-brand-sky" strokeWidth="3" strokeLinecap="round" fill="none" />
          {/* body hint */}
          <rect x="34" y="82" width="36" height="12" rx="6" className="fill-brand-bg-2 stroke-brand-sky" strokeWidth="2" />
        </svg>
      </div>
      <div className="text-[13px] font-semibold text-brand-sky animate-pulse">{label}</div>
    </div>
  )
}
```

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/components/cockpit/__tests__/ThinkingCharacter.test.jsx`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/ThinkingCharacter.jsx src/components/cockpit/__tests__/ThinkingCharacter.test.jsx
git commit -m "feat(cockpit): ThinkingCharacter loading cartoon"
```

---

## Task 10: `BatchPanel`

**Files:**
- Create: `src/components/cockpit/batch/BatchPanel.jsx`
- Test: `src/components/cockpit/__tests__/BatchPanel.test.jsx`

**Interfaces:**
- Consumes: `useRunJob` (Task 5), `ThinkingCharacter` (Task 9).
- Produces: `<BatchPanel selectedIds={Set|Array} by={string} />`. Launch disabled unless ≥1 selected; on launch calls `run.start([...selectedIds], wipe)`. While running, shows the `ThinkingCharacter` cartoon.

- [ ] **Step 1: Write the failing test**

```jsx
// src/components/cockpit/__tests__/BatchPanel.test.jsx
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'

const runJob = { start: vi.fn(), reset: vi.fn(), jobId: null, status: 'idle', logLines: [], results: [], job: null, agentsByAid: {} }
vi.mock('../../../hooks/useRunJob.js', () => ({ useRunJob: () => runJob }))

import BatchPanel from '../batch/BatchPanel.jsx'

describe('BatchPanel', () => {
  beforeEach(() => { runJob.start.mockReset() })

  it('disables launch with no selection', () => {
    renderWithProviders(<BatchPanel selectedIds={new Set()} by="me@x.com" />)
    expect(screen.getByRole('button', { name: /launch batch/i })).toBeDisabled()
  })

  it('launches with the selected ids and wipe flag', () => {
    renderWithProviders(<BatchPanel selectedIds={new Set([1, 2])} by="me@x.com" />)
    fireEvent.click(screen.getByLabelText(/wipe/i))
    fireEvent.click(screen.getByRole('button', { name: /launch batch/i }))
    expect(runJob.start).toHaveBeenCalledWith([1, 2], true)
  })
})
```

- [ ] **Step 2: Run — expect failure**

Run: `npx vitest run src/components/cockpit/__tests__/BatchPanel.test.jsx`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement**

```jsx
// src/components/cockpit/batch/BatchPanel.jsx
import { useState } from 'react'
import { useRunJob } from '../../../hooks/useRunJob.js'
import ThinkingCharacter from '../ThinkingCharacter.jsx'

export default function BatchPanel({ selectedIds, by }) {
  const ids = [...(selectedIds || [])]
  const [wipe, setWipe] = useState(false)
  const run = useRunJob()
  const launched = run.jobId != null
  const summary = run.job?.result

  return (
    <div className="flex flex-col gap-4">
      <div className="rounded-2xl border border-[var(--border)] bg-brand-surface p-4">
        <div className="mb-1 text-[10px] font-bold uppercase tracking-widest text-text-muted">Batch run</div>
        <div className="text-[12px] text-text-muted">Runs straight through (no gates). Select candidates on the left — click to toggle multiple.</div>
        <div className="mt-3 flex items-center gap-4">
          <label className="flex items-center gap-2 text-[12px] text-text-muted">
            <input type="checkbox" checked={wipe} onChange={e => setWipe(e.target.checked)} /> wipe previous outputs first
          </label>
          <div className="flex-1" />
          <button
            onClick={() => run.start(ids, wipe)}
            disabled={ids.length === 0 || run.status === 'running'}
            className="rounded-xl bg-gradient-to-r from-brand-primary to-brand-sky px-4 py-2.5 text-[13px] font-bold text-white disabled:cursor-not-allowed disabled:opacity-50">
            ▶ Launch batch{ids.length ? ` (${ids.length})` : ''}
          </button>
        </div>
        {launched && (
          <div className="mt-3 text-[12px] text-text-muted">
            {run.status === 'running' && `job ${run.jobId} running on ${ids.length || run.results.length} candidate(s)…`}
            {run.status === 'complete' && `batch COMPLETE — ${summary ? `${summary.ok}/${summary.total} ok` : `${run.results.length} done`}`}
            {run.status === 'failed' && 'batch FAILED — check telemetry'}
          </div>
        )}
      </div>
      {run.status === 'running' && <ThinkingCharacter label="Running the batch…" />}
    </div>
  )
}
```

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/components/cockpit/__tests__/BatchPanel.test.jsx`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/batch/BatchPanel.jsx src/components/cockpit/__tests__/BatchPanel.test.jsx
git commit -m "feat(cockpit): BatchPanel"
```

---

## Task 11: `IdLookup`

**Files:**
- Create: `src/components/cockpit/review/IdLookup.jsx`
- Test: `src/components/cockpit/__tests__/IdLookup.test.jsx`

**Interfaces:**
- Consumes: `useLookupId` (Task 2).
- Produces: `<IdLookup onRun={(aid, label) => {}} />`. Resolves an id; renders a placement result (with Run) or a candidate's placement list (each with Run), or a not-found error.

- [ ] **Step 1: Write the failing test**

```jsx
// src/components/cockpit/__tests__/IdLookup.test.jsx
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, fireEvent, waitFor } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'

const mutateAsync = vi.fn()
vi.mock('../../../api/lookup.js', () => ({ useLookupId: () => ({ mutateAsync }) }))

import IdLookup from '../review/IdLookup.jsx'

describe('IdLookup', () => {
  beforeEach(() => { mutateAsync.mockReset() })

  it('resolves a placement and runs it', async () => {
    mutateAsync.mockResolvedValue({ kind: 'placement', placement: { assignment_id: 149142, candidate: 'Jane', school: 'PS 1', is_edu: true } })
    const onRun = vi.fn()
    renderWithProviders(<IdLookup onRun={onRun} />)
    fireEvent.change(screen.getByPlaceholderText(/Candidate ID/i), { target: { value: '149142' } })
    fireEvent.click(screen.getByRole('button', { name: /look up/i }))
    await waitFor(() => screen.getByRole('button', { name: /^▶ Run/i }))
    fireEvent.click(screen.getByRole('button', { name: /^▶ Run/i }))
    expect(onRun).toHaveBeenCalledWith(149142, expect.stringContaining('Jane'))
  })

  it('lists a candidate\'s placements', async () => {
    mutateAsync.mockResolvedValue({ kind: 'candidate', candidate: { id: 2670415, name: 'John Roe' },
      placements: [{ assignment_id: 1, school: 'PS 9', is_edu: true }] })
    renderWithProviders(<IdLookup onRun={vi.fn()} />)
    fireEvent.change(screen.getByPlaceholderText(/Candidate ID/i), { target: { value: '2670415' } })
    fireEvent.click(screen.getByRole('button', { name: /look up/i }))
    await waitFor(() => screen.getByText(/John Roe/))
    expect(screen.getByText('PS 9')).toBeInTheDocument()
  })

  it('shows a not-found error', async () => {
    mutateAsync.mockRejectedValue(new Error('404'))
    renderWithProviders(<IdLookup onRun={vi.fn()} />)
    fireEvent.change(screen.getByPlaceholderText(/Candidate ID/i), { target: { value: 'zzz' } })
    fireEvent.click(screen.getByRole('button', { name: /look up/i }))
    await waitFor(() => screen.getByText(/not a Bullhorn/i))
  })
})
```

- [ ] **Step 2: Run — expect failure**

Run: `npx vitest run src/components/cockpit/__tests__/IdLookup.test.jsx`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement**

```jsx
// src/components/cockpit/review/IdLookup.jsx
import { useState } from 'react'
import { useLookupId } from '../../../api/lookup.js'

function eduBadge(p) {
  return p.is_edu
    ? <span className="rounded-full border border-tier-green bg-tier-green/10 px-2 py-0.5 text-[10px] font-bold text-tier-green">EDU</span>
    : <span className="rounded-full border border-tier-yellow bg-tier-yellow/10 px-2 py-0.5 text-[10px] font-bold text-tier-yellow">⚠ {p.branch || 'non-EDU'}</span>
}

export default function IdLookup({ onRun }) {
  const [id, setId] = useState('')
  const [res, setRes] = useState(null)
  const [err, setErr] = useState('')
  const lookup = useLookupId()

  async function go() {
    setErr(''); setRes(null)
    if (!id.trim()) return
    try { setRes(await lookup.mutateAsync(id)) }
    catch { setErr(`${id} is not a Bullhorn candidate id or assignment id`) }
  }

  return (
    <div className="mb-2.5">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-[12px] text-text-muted">Run by <b className="text-text">Candidate ID</b> or <b className="text-text">Assignment ID</b>:</span>
        <input value={id} onChange={e => setId(e.target.value)} onKeyDown={e => e.key === 'Enter' && go()}
          placeholder="Candidate ID (e.g. 2670415) or Assignment ID (e.g. 149142)"
          className="min-w-[320px] rounded-lg border border-[var(--border)] bg-brand-surface px-3 py-2 text-[12px] text-text outline-none" />
        <button onClick={go} className="rounded-lg border border-[var(--border)] px-3 py-2 text-[12px] text-text-muted hover:text-brand-sky">Look up</button>
      </div>

      {err && <div className="mt-2 rounded-xl border border-tier-red bg-tier-red/10 px-4 py-2.5 text-[13px] font-bold text-tier-red">✗ {err}</div>}

      {res?.kind === 'placement' && (() => {
        const p = res.placement, label = `${p.candidate || '—'} · ${p.school || '—'}`
        return (
          <div className="mt-2">
            <div className="rounded-xl border border-tier-green bg-tier-green/10 px-4 py-2.5 text-[13px] font-bold text-tier-green">
              ✓ #{p.assignment_id} — {label}
              <div className="text-[11px] font-normal opacity-90">{p.job_title || ''}{p.status ? ` · ${p.status}` : ''}</div>
            </div>
            <button onClick={() => onRun(p.assignment_id, label)} className="mt-2 rounded-xl bg-gradient-to-r from-brand-primary to-brand-sky px-4 py-2 text-[13px] font-bold text-white">▶ Run</button>
          </div>
        )
      })()}

      {res?.kind === 'candidate' && (
        <div className="mt-2 rounded-xl border border-[var(--border)] bg-brand-bg-2 px-4 py-3">
          <div className="text-[13px] font-bold text-text-strong">👤 {res.candidate?.name || 'candidate'} — candidate #{res.candidate?.id} · {(res.placements || []).length} assignment(s)</div>
          {(res.placements || []).length === 0 && <div className="mt-1 text-[12px] text-text-muted">no assignments on file — nothing to run.</div>}
          {(res.placements || []).map((p) => {
            const label = `${res.candidate?.name || ''} · ${p.school || '—'}`
            return (
              <div key={p.assignment_id} className="mt-2 flex items-center gap-2 border-t border-[var(--border)] pt-2 text-[12px]">
                {eduBadge(p)}
                <span className="text-brand-sky">#{p.assignment_id} · <b>{p.school || '—'}</b></span>
                <span className="italic text-text-muted">{p.status || ''}{p.ended ? ' · ended' : ''}</span>
                <button onClick={() => onRun(p.assignment_id, label)} className="ml-auto rounded-lg bg-gradient-to-r from-brand-primary to-brand-sky px-3 py-1 text-[12px] font-bold text-white">▶ Run</button>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
```

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/components/cockpit/__tests__/IdLookup.test.jsx`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/review/IdLookup.jsx src/components/cockpit/__tests__/IdLookup.test.jsx
git commit -m "feat(cockpit): IdLookup (run by candidate/assignment id)"
```

---

## Task 12: `FullReview`

**Files:**
- Create: `src/components/cockpit/review/FullReview.jsx`
- Test: `src/components/cockpit/__tests__/FullReview.test.jsx`

**Interfaces:**
- Consumes: `useReview` (`api/review.js`), `useRequirements` (Task 2), `useSetOverride` (`api/overrides.js`), `useAgentOutput` (`api/agents.js`), `useCredentialers` (`api/credentialers.js`), and components `CostTierSummary`, `RequirementsTable`, `ChecklistReview`, `AgentOutputView`, `VerifierView`, `PendingEmailPreview`.
- Produces: `<FullReview aid={id} by={email} onApplyRerun={() => {}} onOpenDoc={(file)=>{}} />`. Aggregates queued corrections `rfixes[agentId][field]=value`; "Apply Corrections & Re-run" saves each via `useSetOverride(aid).mutateAsync({ agent, field, value, by, reason })` then calls `onApplyRerun()`.

> Note: `useAgentOutput(aid, n)` must be called for a fixed set of agents. Call it unconditionally per agent id at the top level (hooks rule) — one call each for '1','2','3','4','5','5_5','6'.

- [ ] **Step 1: Write the failing test**

```jsx
// src/components/cockpit/__tests__/FullReview.test.jsx
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, fireEvent, waitFor } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'

const setOverride = vi.fn().mockResolvedValue({})
vi.mock('../../../api/review.js', () => ({ useReview: () => ({ data: { candidate: 'Jane', district: 'PS 1', hitl_tier: 'GREEN', checklist: [], cost: { total_usd: 0.01 } } }) }))
vi.mock('../../../api/requirements.js', () => ({ useRequirements: () => ({ data: { requirements: [] } }) }))
vi.mock('../../../api/overrides.js', () => ({ useOverrides: () => ({ data: {} }), useSetOverride: () => ({ mutateAsync: setOverride }) }))
vi.mock('../../../api/agents.js', () => ({ useAgentOutput: () => ({ data: { audit: { output: {} }, verifier: null } }) }))
vi.mock('../../../api/credentialers.js', () => ({ useCredentialers: () => ({ data: { credentialers: [] } }) }))
vi.mock('../../../api/email.js', () => ({ usePendingEmail: () => ({ data: { found: false } }) }))

import FullReview from '../review/FullReview.jsx'

describe('FullReview', () => {
  beforeEach(() => { setOverride.mockClear() })

  it('renders the summary and per-agent cards', () => {
    renderWithProviders(<FullReview aid={1} by="me@x.com" onApplyRerun={vi.fn()} />)
    expect(screen.getByText(/TIER GREEN/)).toBeInTheDocument()
    expect(screen.getByText(/Agent 4/i)).toBeInTheDocument()
  })

  it('applying with no corrections does not save or rerun', () => {
    const onApplyRerun = vi.fn()
    renderWithProviders(<FullReview aid={1} by="me@x.com" onApplyRerun={onApplyRerun} />)
    fireEvent.click(screen.getByRole('button', { name: /apply corrections/i }))
    expect(setOverride).not.toHaveBeenCalled()
    expect(onApplyRerun).not.toHaveBeenCalled()
  })
})
```

- [ ] **Step 2: Run — expect failure**

Run: `npx vitest run src/components/cockpit/__tests__/FullReview.test.jsx`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement**

```jsx
// src/components/cockpit/review/FullReview.jsx
import { useState } from 'react'
import { useReview } from '../../../api/review.js'
import { useRequirements } from '../../../api/requirements.js'
import { useSetOverride } from '../../../api/overrides.js'
import { useAgentOutput } from '../../../api/agents.js'
import { useCredentialers } from '../../../api/credentialers.js'
import CostTierSummary from '../CostTierSummary.jsx'
import RequirementsTable from '../RequirementsTable.jsx'
import ChecklistReview from '../ChecklistReview.jsx'
import AgentOutputView from '../AgentOutputView.jsx'
import VerifierView from '../VerifierView.jsx'
import PendingEmailPreview from '../PendingEmailPreview.jsx'

const AGENTS = [['1', 'Trigger'], ['2', 'Intake'], ['3', 'Assign'], ['4', 'Requirements'], ['5', 'Doc Recon'], ['5_5', 'Gate'], ['6', 'Comms']]
const SCALAR = { '5_5': ['hitl_tier', 'route_to'], '6': ['recipient', 'cc_email', 'subject'] }

function Card({ title, verifier, children }) {
  return (
    <div className="my-3 rounded-2xl border border-[var(--border)] bg-brand-surface p-4">
      <div className="mb-2 flex items-center justify-between text-[10px] font-bold uppercase tracking-widest text-text-muted">
        <span>{title}</span>
        {verifier?.verdict && <span className="text-text">{verifier.verdict}</span>}
      </div>
      {children}
    </div>
  )
}

function ScalarEditor({ agent, onQueue }) {
  const fields = SCALAR[agent] || []
  const [field, setField] = useState('')
  const [value, setValue] = useState('')
  if (!fields.length) return null
  return (
    <div className="mt-2 flex flex-wrap items-center gap-2">
      <span className="text-[12px] text-text-muted">Correct field:</span>
      <select value={field} onChange={e => setField(e.target.value)} className="rounded-lg border border-[var(--border)] bg-brand-bg-2 px-2.5 py-1.5 text-[12px] text-text">
        <option value="">— none —</option>
        {fields.map(f => <option key={f} value={f}>{f}</option>)}
      </select>
      <input value={value} onChange={e => setValue(e.target.value)} placeholder="new value" className="rounded-lg border border-[var(--border)] bg-brand-bg-2 px-2.5 py-1.5 text-[12px] text-text" />
      <button onClick={() => { if (field && value) { onQueue(agent, field, value); setField(''); setValue('') } }} className="rounded-lg border border-[var(--border)] px-3 py-1.5 text-[12px] text-text-muted hover:text-brand-sky">+ queue</button>
    </div>
  )
}

export default function FullReview({ aid, by, onApplyRerun, onOpenDoc = () => {} }) {
  const review = useReview(aid).data
  const requirements = useRequirements(aid).data
  const credentialers = useCredentialers().data?.credentialers || []
  const setOverride = useSetOverride(aid)
  const [fixes, setFixes] = useState({}) // { [agent]: { [field]: value } }
  const [saving, setSaving] = useState(false)

  // One hook call per agent id (hooks must be unconditional + stable order).
  const a1 = useAgentOutput(aid, '1').data
  const a2 = useAgentOutput(aid, '2').data
  const a3 = useAgentOutput(aid, '3').data
  const a4 = useAgentOutput(aid, '4').data
  const a5 = useAgentOutput(aid, '5').data
  const a55 = useAgentOutput(aid, '5_5').data
  const a6 = useAgentOutput(aid, '6').data
  const per = { '1': a1, '2': a2, '3': a3, '4': a4, '5': a5, '5_5': a55, '6': a6 }

  const count = Object.values(fixes).reduce((n, o) => n + Object.keys(o).length, 0)
  const queueField = (agent, field, value) => setFixes(p => ({ ...p, [agent]: { ...(p[agent] || {}), [field]: value } }))
  const queueChecklist = (req, value) => setFixes(p => ({ ...p, '5': { ...(p['5'] || {}), [req]: value } }))

  async function apply() {
    if (!count || !by) return
    setSaving(true)
    for (const agent of Object.keys(fixes)) {
      for (const field of Object.keys(fixes[agent])) {
        await setOverride.mutateAsync({ agent, field, value: fixes[agent][field], by, reason: 'review-mode correction' })
      }
    }
    setFixes({}); setSaving(false)
    onApplyRerun?.()
  }

  if (!review) return <div className="text-[13px] text-text-muted">building review…</div>

  return (
    <div>
      <CostTierSummary review={review} />
      {AGENTS.map(([id, label]) => {
        const pa = per[id] || {}
        const out = pa?.audit?.output
        const ver = pa?.verifier
        return (
          <Card key={id} title={`Agent ${id.replace('_', '.')} — ${label}`} verifier={ver}>
            {id === '4' ? (
              <RequirementsTable data={requirements} />
            ) : id === '5' ? (
              <ChecklistReview review={review} mode="correct" onOpenDoc={onOpenDoc} onQueue={queueChecklist} />
            ) : id === '6' ? (
              <PendingEmailPreview aid={aid} />
            ) : (
              <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
                <div><div className="mb-1 text-[10px] font-bold uppercase tracking-widest text-text-muted">Output</div><AgentOutputView output={out} agent={id} /></div>
                <div><div className="mb-1 text-[10px] font-bold uppercase tracking-widest text-text-muted">Verifier</div><VerifierView verifier={ver} /></div>
              </div>
            )}
            {id === '3' && (
              <div className="mt-2 flex flex-wrap items-center gap-2">
                <span className="text-[12px] text-text-muted">Reassign:</span>
                <select onChange={e => { if (e.target.value) { const c = JSON.parse(e.target.value); queueField('3', 'credentialer_name', c.name); queueField('3', 'credentialer_email', c.email) } }}
                  className="rounded-lg border border-[var(--border)] bg-brand-bg-2 px-2.5 py-1.5 text-[12px] text-text">
                  <option value="">— keep AI's choice —</option>
                  {credentialers.map((c, i) => <option key={i} value={JSON.stringify(c)}>{c.name} — {c.email} (workload {c.workload})</option>)}
                </select>
              </div>
            )}
            {(id === '5_5' || id === '6') && <ScalarEditor agent={id} onQueue={queueField} />}
          </Card>
        )
      })}

      <div className="mt-3 rounded-2xl border border-[var(--border)] bg-brand-surface p-4">
        <div className="text-[12px] text-text-muted">
          {count ? `⚡ ${count} correction(s) queued — applied on re-run` : 'No corrections queued — output above is final unless you edit it.'}
        </div>
        <div className="mt-2 flex flex-wrap items-center gap-3">
          <button onClick={apply} disabled={!count || !by || saving}
            className="rounded-xl bg-gradient-to-r from-brand-primary to-brand-sky px-4 py-2.5 text-[13px] font-bold text-white disabled:opacity-50">
            {saving ? 'Applying…' : '✓ Apply corrections & re-run'}
          </button>
          {!by && <span className="text-[12px] text-tier-yellow">enter your email up top first</span>}
        </div>
      </div>
    </div>
  )
}
```

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/components/cockpit/__tests__/FullReview.test.jsx`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/review/FullReview.jsx src/components/cockpit/__tests__/FullReview.test.jsx
git commit -m "feat(cockpit): FullReview per-agent correction view"
```

---

## Task 13: `RunReviewPanel`

**Files:**
- Create: `src/components/cockpit/review/RunReviewPanel.jsx`
- Test: `src/components/cockpit/__tests__/RunReviewPanel.test.jsx`

**Interfaces:**
- Consumes: `useRunJob` (Task 5), `IdLookup` (Task 11), `FullReview` (Task 12), `ThinkingCharacter` (Task 9).
- Produces: `<RunReviewPanel selectedId={id} by={email} onOpenDoc={(aid,file)=>{}} />`. "Run all agents" runs `selectedId` (or a looked-up id) via `run.start([aid], true)`; on completion shows `FullReview`. `FullReview.onApplyRerun` → `run.start([aid], false)`.

- [ ] **Step 1: Write the failing test**

```jsx
// src/components/cockpit/__tests__/RunReviewPanel.test.jsx
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'

const runJob = { start: vi.fn(), reset: vi.fn(), jobId: null, status: 'idle', logLines: [], results: [], job: null, agentsByAid: {} }
vi.mock('../../../hooks/useRunJob.js', () => ({ useRunJob: () => runJob }))
vi.mock('../review/IdLookup.jsx', () => ({ default: () => <div>id-lookup</div> }))
vi.mock('../review/FullReview.jsx', () => ({ default: () => <div>full-review</div> }))

import RunReviewPanel from '../review/RunReviewPanel.jsx'

describe('RunReviewPanel', () => {
  beforeEach(() => { runJob.start.mockReset() })

  it('prompts to select when nothing is chosen', () => {
    renderWithProviders(<RunReviewPanel selectedId={null} by="me@x.com" />)
    expect(screen.getByText(/Select a candidate/i)).toBeInTheDocument()
  })

  it('runs all agents for the selected id (wipe:true)', () => {
    renderWithProviders(<RunReviewPanel selectedId={149142} by="me@x.com" />)
    fireEvent.click(screen.getByRole('button', { name: /run all agents/i }))
    expect(runJob.start).toHaveBeenCalledWith([149142], true)
  })
})
```

- [ ] **Step 2: Run — expect failure**

Run: `npx vitest run src/components/cockpit/__tests__/RunReviewPanel.test.jsx`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement**

```jsx
// src/components/cockpit/review/RunReviewPanel.jsx
import { useState } from 'react'
import { useRunJob } from '../../../hooks/useRunJob.js'
import IdLookup from './IdLookup.jsx'
import FullReview from './FullReview.jsx'
import ThinkingCharacter from '../ThinkingCharacter.jsx'

export default function RunReviewPanel({ selectedId, by, onOpenDoc = () => {} }) {
  const run = useRunJob()
  const [activeAid, setActiveAid] = useState(null)
  const aid = activeAid ?? selectedId

  const runAll = (id) => { setActiveAid(id); run.start([id], true) }

  return (
    <div className="flex flex-col gap-4">
      <div className="rounded-2xl border border-[var(--border)] bg-brand-surface p-4">
        <div className="mb-2 text-[10px] font-bold uppercase tracking-widest text-text-muted">
          Run + Review {aid ? `// ${aid}` : ''}
        </div>
        <IdLookup onRun={(id) => runAll(id)} />
        {run.status === 'idle' && (
          selectedId ? (
            <button onClick={() => runAll(selectedId)} className="mt-2 rounded-xl bg-gradient-to-r from-brand-primary to-brand-sky px-4 py-2.5 text-[13px] font-bold text-white">
              ▶ Run all agents
            </button>
          ) : (
            <div className="mt-2 text-[13px] text-text-muted">Select a candidate on the left, then run all 7 agents. When they finish, review &amp; correct here, then Apply &amp; Re-run.</div>
          )
        )}
        {run.status === 'running' && <div className="mt-3"><ThinkingCharacter label="Running all agents (no gates)…" /></div>}
        {run.status === 'complete' && aid && (
          <div className="mt-3">
            <FullReview aid={aid} by={by} onOpenDoc={onOpenDoc} onApplyRerun={() => run.start([aid], false)} />
          </div>
        )}
        {run.status === 'failed' && <div className="mt-2 text-[13px] font-bold text-tier-red">✖ run failed — please try again</div>}
      </div>
    </div>
  )
}
```

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/components/cockpit/__tests__/RunReviewPanel.test.jsx`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/review/RunReviewPanel.jsx src/components/cockpit/__tests__/RunReviewPanel.test.jsx
git commit -m "feat(cockpit): RunReviewPanel"
```

---

## Task 14: `WatchdogResult` + `WatchdogPanel`

**Files:**
- Create: `src/components/cockpit/watchdog/WatchdogResult.jsx`, `src/components/cockpit/watchdog/WatchdogPanel.jsx`
- Test: `src/components/cockpit/__tests__/WatchdogPanel.test.jsx`

**Interfaces:**
- Consumes: `useWatchdogStatus`, `useWatchdogResults`, `useWatchdogResult`, `useWatchdogScan` (Task 1).
- Produces:
  - `<WatchdogResult aid={id} onOpenFullReview={(aid)=>{}} />`
  - `<WatchdogPanel onOpenReview={(aid)=>{}} />`

- [ ] **Step 1: Write the failing test**

```jsx
// src/components/cockpit/__tests__/WatchdogPanel.test.jsx
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'

const scan = vi.fn().mockResolvedValue({ ok: true, changed: 1 })
let results = { data: { results: [] } }
vi.mock('../../../api/watchdog.js', () => ({
  useWatchdogStatus: () => ({ data: { scanner_thread_alive: true, interval_min: 15, last_scan_at: 'now' } }),
  useWatchdogResults: () => results,
  useWatchdogResult: () => ({ data: { found: true, changed_docs: ['a.pdf'], deltas: [] } }),
  useWatchdogScan: () => ({ mutateAsync: scan, isPending: false }),
}))

import WatchdogPanel from '../watchdog/WatchdogPanel.jsx'

describe('WatchdogPanel', () => {
  beforeEach(() => { scan.mockClear(); results = { data: { results: [] } } })

  it('shows the empty state and scanner status', () => {
    renderWithProviders(<WatchdogPanel onOpenReview={vi.fn()} />)
    expect(screen.getByText(/no document updates/i)).toBeInTheDocument()
    expect(screen.getByText(/running/i)).toBeInTheDocument()
  })

  it('triggers a scan', () => {
    renderWithProviders(<WatchdogPanel onOpenReview={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: /scan now/i }))
    expect(scan).toHaveBeenCalled()
  })

  it('lists results', () => {
    results = { data: { results: [{ assignment_id: 5, candidate: 'Jane', files_new: 2, files_changed: 1, deltas: [], ready_before: false, ready_after: true }] } }
    renderWithProviders(<WatchdogPanel onOpenReview={vi.fn()} />)
    expect(screen.getByText(/#5 · Jane/)).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run — expect failure**

Run: `npx vitest run src/components/cockpit/__tests__/WatchdogPanel.test.jsx`
Expected: FAIL — modules missing.

- [ ] **Step 3: Implement `WatchdogResult.jsx`**

```jsx
// src/components/cockpit/watchdog/WatchdogResult.jsx
import { useWatchdogResult } from '../../../api/watchdog.js'

export default function WatchdogResult({ aid, onOpenFullReview = () => {} }) {
  const { data: m } = useWatchdogResult(aid)
  if (!m) return <div className="mt-2 text-[12px] text-text-muted">loading…</div>
  if (!m.found) return <div className="mt-2 text-[12px] text-text-muted">not found</div>
  const docs = m.changed_docs || []
  const deltas = m.deltas || []
  const stale = (m.stale_overrides || []).length
  return (
    <div className="mt-3 rounded-2xl border border-[var(--border)] bg-brand-surface p-4">
      <div className="text-[12px] text-text-muted">New / updated documents:</div>
      <ul className="mb-2 ml-5 list-disc text-[12.5px] text-text">
        {docs.length ? docs.map((n, i) => <li key={i}>{n}</li>) : <li>(names unavailable)</li>}
      </ul>
      <div className="text-[12px] text-text-muted">Requirement status changes:</div>
      <table className="my-1.5 w-full border-collapse text-[12.5px]">
        <tbody>
          {deltas.length ? deltas.map((x, i) => (
            <tr key={i}><td className="p-1 text-text">{x.requirement}</td><td className="p-1 text-text-muted">{String(x.from)}</td><td className="p-1">→</td><td className="p-1"><b className="text-brand-sky">{String(x.to)}</b></td></tr>
          )) : <tr><td className="p-1 text-text-muted" colSpan={4}>documents changed; no requirement status flipped</td></tr>}
        </tbody>
      </table>
      {stale > 0 && <div className="text-[12px] text-tier-yellow">⚠ {stale} prior correction(s) may be stale after these docs</div>}
      <button onClick={() => onOpenFullReview(aid)} className="mt-2 rounded-xl border border-[var(--border)] px-3 py-2 text-[12px] text-text-muted hover:text-brand-sky">↗ Open full credentialing view (review &amp; edit)</button>
    </div>
  )
}
```

- [ ] **Step 4: Implement `WatchdogPanel.jsx`**

```jsx
// src/components/cockpit/watchdog/WatchdogPanel.jsx
import { useState } from 'react'
import { useWatchdogStatus, useWatchdogResults, useWatchdogScan } from '../../../api/watchdog.js'
import WatchdogResult from './WatchdogResult.jsx'

export default function WatchdogPanel({ onOpenReview = () => {} }) {
  const { data: status } = useWatchdogStatus()
  const { data, isLoading } = useWatchdogResults()
  const scan = useWatchdogScan()
  const [sel, setSel] = useState(null)
  const rows = data?.results || []

  return (
    <div className="rounded-2xl border border-[var(--border)] bg-brand-surface p-4">
      <div className="mb-2 flex items-center justify-between">
        <div className="text-[10px] font-bold uppercase tracking-widest text-text-muted">🐕 Watchdog — new/updated documents re-reconciled</div>
        <button onClick={() => scan.mutateAsync()} disabled={scan.isPending} className="rounded-lg border border-[var(--border)] px-3 py-1.5 text-[12px] text-text-muted hover:text-brand-sky disabled:opacity-50">⟳ Scan now</button>
      </div>
      {status && (
        <div className="mb-2 text-[12px] text-text-muted">
          scanner: <b className={status.scanner_thread_alive ? 'text-tier-green' : 'text-text'}>{status.scanner_thread_alive ? 'running' : 'idle'}</b>
          {' '}· every {status.interval_min} min · last scan: {status.last_scan_at || '—'}
        </div>
      )}
      {isLoading && <div className="text-[12px] text-text-muted">loading watchdog results…</div>}
      {!isLoading && rows.length === 0 && <div className="text-[12px] text-text-muted">no document updates detected yet. Click "Scan now" to check Bullhorn.</div>}
      <div className="flex max-h-[340px] flex-col gap-2 overflow-y-auto">
        {rows.map((m) => (
          <div key={m.assignment_id} onClick={() => setSel(m.assignment_id)}
            className={`cursor-pointer rounded-xl border px-3 py-2.5 ${sel === m.assignment_id ? 'border-brand-sky bg-brand-sky/5' : 'border-[var(--border)] bg-brand-bg-2'}`}>
            <div className="text-[13px] font-bold text-text-strong">#{m.assignment_id} · {m.candidate || ''}
              <span className="float-right text-[11px] text-text-muted">{m.email_sent ? '✉ notified' : '—'}</span>
            </div>
            <div className="text-[11px] text-text-muted">{m.files_new || 0} new + {m.files_changed || 0} changed doc(s) · {(m.deltas || []).length} status change(s)</div>
            <div className="text-[11px] text-text-muted">ready {String(m.ready_before)} → <b className="text-text">{String(m.ready_after)}</b> · {m.scanned_at || ''}</div>
          </div>
        ))}
      </div>
      {sel && <WatchdogResult aid={sel} onOpenFullReview={onOpenReview} />}
    </div>
  )
}
```

- [ ] **Step 5: Run — expect pass**

Run: `npx vitest run src/components/cockpit/__tests__/WatchdogPanel.test.jsx`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add src/components/cockpit/watchdog/WatchdogResult.jsx src/components/cockpit/watchdog/WatchdogPanel.jsx src/components/cockpit/__tests__/WatchdogPanel.test.jsx
git commit -m "feat(cockpit): WatchdogPanel + WatchdogResult"
```

---

## Task 15: `BullhornNotesPanel` (MAIL drift repair, part 1)

**Files:**
- Create: `src/components/cockpit/mail/BullhornNotesPanel.jsx`
- Test: `src/components/cockpit/__tests__/BullhornNotesPanel.test.jsx`

**Interfaces:**
- Consumes: `usePendingBullhorn`, `usePendingBullhornNote`, `useApproveBullhorn`, `useRejectBullhorn` (Task 3).
- Produces: `<BullhornNotesPanel />` — list + preview + approve/reject.

- [ ] **Step 1: Write the failing test**

```jsx
// src/components/cockpit/__tests__/BullhornNotesPanel.test.jsx
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'

const approve = vi.fn().mockResolvedValue({ ok: true })
const reject = vi.fn().mockResolvedValue({ ok: true })
let list = { data: { pending: [] } }
vi.mock('../../../api/bullhornNotes.js', () => ({
  usePendingBullhorn: () => list,
  usePendingBullhornNote: () => ({ data: { found: true, candidate_name: 'Jane', candidate_id: 9, hospital: 'PS 1', comments: 'note text' } }),
  useApproveBullhorn: () => ({ mutateAsync: approve, isPending: false }),
  useRejectBullhorn: () => ({ mutateAsync: reject, isPending: false }),
}))

import BullhornNotesPanel from '../mail/BullhornNotesPanel.jsx'

describe('BullhornNotesPanel', () => {
  beforeEach(() => { approve.mockClear(); reject.mockClear(); list = { data: { pending: [] } } })

  it('shows empty state', () => {
    renderWithProviders(<BullhornNotesPanel />)
    expect(screen.getByText(/no held Bullhorn notes/i)).toBeInTheDocument()
  })

  it('previews a note and approves it', () => {
    list = { data: { pending: [{ assignment_id: 3, candidate: 'Jane', action: 'Required Forms', hospital: 'PS 1' }] } }
    renderWithProviders(<BullhornNotesPanel />)
    fireEvent.click(screen.getByText(/#3 · Jane/))
    expect(screen.getByText('note text')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: /approve/i }))
    expect(approve).toHaveBeenCalled()
  })
})
```

- [ ] **Step 2: Run — expect failure**

Run: `npx vitest run src/components/cockpit/__tests__/BullhornNotesPanel.test.jsx`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement**

```jsx
// src/components/cockpit/mail/BullhornNotesPanel.jsx
import { useState } from 'react'
import { usePendingBullhorn, usePendingBullhornNote, useApproveBullhorn, useRejectBullhorn } from '../../../api/bullhornNotes.js'

function NotePreview({ aid }) {
  const { data: m } = usePendingBullhornNote(aid)
  const approve = useApproveBullhorn(aid)
  const reject = useRejectBullhorn(aid)
  const [msg, setMsg] = useState('')
  if (!m) return <div className="mt-2 text-[12px] text-text-muted">loading preview…</div>
  if (!m.found) return <div className="mt-2 text-[12px] text-text-muted">not found</div>
  return (
    <div className="mt-3 rounded-2xl border border-[var(--border)] bg-brand-surface p-4">
      <div className="text-[12px] text-text-muted">Candidate: <b className="text-text">{m.candidate_name || ''}</b> (id {m.candidate_id || '—'}) · {m.hospital || ''}</div>
      <pre className="my-2.5 max-h-[280px] overflow-y-auto whitespace-pre-wrap rounded-lg bg-brand-bg-2 p-2.5 text-[12px] text-text">{m.comments || ''}</pre>
      <div className="flex flex-wrap items-center gap-2">
        <button onClick={async () => { setMsg('writing to Bullhorn…'); try { const r = await approve.mutateAsync(); setMsg(r.ok ? '✓ written' : `✗ ${r.error || 'write failed'}`) } catch (e) { setMsg(`✗ ${e.message || 'write failed'}`) } }}
          className="rounded-lg bg-tier-green/90 px-3 py-2 text-[12px] font-bold text-white">✓ Approve &amp; write to Bullhorn</button>
        <button onClick={async () => { await reject.mutateAsync('rejected via cockpit'); setMsg('rejected') }}
          className="rounded-lg border border-tier-red px-3 py-2 text-[12px] font-bold text-tier-red">✗ Reject</button>
        {msg && <span className="text-[12px] text-text-muted">{msg}</span>}
      </div>
    </div>
  )
}

export default function BullhornNotesPanel() {
  const { data, isLoading } = usePendingBullhorn()
  const [sel, setSel] = useState(null)
  const rows = data?.pending || []
  return (
    <div className="mt-4 rounded-2xl border border-[var(--border)] bg-brand-surface p-4">
      <div className="mb-2 text-[10px] font-bold uppercase tracking-widest text-text-muted">Held Bullhorn notes — required forms, waiting for approval</div>
      {isLoading && <div className="text-[12px] text-text-muted">loading held notes…</div>}
      {!isLoading && rows.length === 0 && <div className="text-[12px] text-text-muted">no held Bullhorn notes yet — run a candidate first.</div>}
      <div className="flex max-h-[300px] flex-col gap-2 overflow-y-auto">
        {rows.map((m) => (
          <div key={m.assignment_id} onClick={() => setSel(m.assignment_id)}
            className={`cursor-pointer rounded-xl border px-3 py-2.5 ${sel === m.assignment_id ? 'border-brand-sky bg-brand-sky/5' : 'border-[var(--border)] bg-brand-bg-2'}`}>
            <div className="text-[13px] font-bold text-text-strong">#{m.assignment_id} · {m.candidate || ''}
              <span className="float-right text-[11px] text-text-muted">cand {m.candidate_id || '—'}</span>
            </div>
            <div className="text-[11px] text-text-muted">{m.action || 'Required Forms'} · {m.hospital || ''}</div>
            <div className="text-[11px] text-text-muted">{m.built_at || ''}</div>
          </div>
        ))}
      </div>
      {sel && <NotePreview aid={sel} />}
    </div>
  )
}
```

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/components/cockpit/__tests__/BullhornNotesPanel.test.jsx`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/mail/BullhornNotesPanel.jsx src/components/cockpit/__tests__/BullhornNotesPanel.test.jsx
git commit -m "feat(cockpit): held Bullhorn notes panel"
```

---

## Task 16: AssignmentRail multi-select mode

**Files:**
- Modify: `src/components/cockpit/AssignmentRail.jsx`
- Modify: `src/components/cockpit/__tests__/AssignmentRail.test.jsx` (add cases)

**Interfaces:**
- Produces (new optional props): `multi` (bool), `selectedIds` (Set|Array), `onToggle(id)`. Default behavior (no `multi`) is unchanged single-select.

- [ ] **Step 1: Add failing tests** (append inside the existing `describe`)

```jsx
  it('multi mode toggles ids and hides Review button', () => {
    const onToggle = vi.fn()
    renderWithProviders(<AssignmentRail assignments={ROWS} multi selectedIds={new Set([2])} onToggle={onToggle} />)
    fireEvent.click(screen.getByText('Jane Doe'))
    expect(onToggle).toHaveBeenCalledWith(1)
    expect(screen.queryByRole('button', { name: /review/i })).not.toBeInTheDocument()
  })
```

- [ ] **Step 2: Run — expect failure**

Run: `npx vitest run src/components/cockpit/__tests__/AssignmentRail.test.jsx`
Expected: FAIL — `onToggle` not called (multi not implemented) and/or Review button still present.

- [ ] **Step 3: Implement — edit the signature and row logic**

Change the function signature (lines 9-12) to add the new props:

```jsx
export default function AssignmentRail({
  assignments = [], loading = false,
  selectedId = null, onPick = () => {}, onOpenReview = () => {},
  multi = false, selectedIds = null, onToggle = () => {},
}) {
```

Add a membership helper right after `const t = useTokens()` (line 13):

```jsx
  const idSet = selectedIds instanceof Set ? selectedIds : new Set(selectedIds || [])
```

Replace the `const sel = selectedId === a.assignment_id` line (line 38) with:

```jsx
          const sel = multi ? idSet.has(a.assignment_id) : selectedId === a.assignment_id
```

Replace the row `onClick` (line 40) with:

```jsx
            <div key={a.assignment_id} onClick={() => (multi ? onToggle(a.assignment_id) : onPick(a.assignment_id))}
```

Guard the Review button so it only shows in single-select mode. Change the condition (line 65) from `{st !== 'new' && (` to:

```jsx
                  {!multi && st !== 'new' && (
```

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/components/cockpit/__tests__/AssignmentRail.test.jsx`
Expected: PASS (all cases — existing single-select tests still green).

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/AssignmentRail.jsx src/components/cockpit/__tests__/AssignmentRail.test.jsx
git commit -m "feat(cockpit): AssignmentRail optional multi-select mode"
```

---

## Task 17: CockpitTabs — add the three tabs

**Files:**
- Modify: `src/components/cockpit/CockpitTabs.jsx:3`
- Test: `src/components/cockpit/__tests__/CockpitTabs.test.jsx`

**Interfaces:**
- Produces: `TABS` now includes `review`, `batch`, `watch` in addition to `step`, `mail`.

- [ ] **Step 1: Write the failing test**

```jsx
// src/components/cockpit/__tests__/CockpitTabs.test.jsx
import { describe, it, expect, vi } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'
import CockpitTabs from '../CockpitTabs.jsx'

describe('CockpitTabs', () => {
  it('renders all five tabs and fires onChange', () => {
    const onChange = vi.fn()
    renderWithProviders(<CockpitTabs active="step" onChange={onChange} />)
    ;['Step Run', 'Run + Review', 'Batch', 'Watchdog', 'Mail'].forEach(l =>
      expect(screen.getByText(new RegExp(l, 'i'))).toBeInTheDocument())
    fireEvent.click(screen.getByText(/Watchdog/i))
    expect(onChange).toHaveBeenCalledWith('watch')
  })
})
```

- [ ] **Step 2: Run — expect failure**

Run: `npx vitest run src/components/cockpit/__tests__/CockpitTabs.test.jsx`
Expected: FAIL — Run + Review / Batch / Watchdog not found.

- [ ] **Step 3: Implement — replace line 3**

```jsx
const TABS = [
  ['step', '⚡ Step Run'],
  ['review', '🔁 Run + Review'],
  ['batch', '▦ Batch'],
  ['watch', '🐕 Watchdog'],
  ['mail', '📧 Mail'],
]
```

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/components/cockpit/__tests__/CockpitTabs.test.jsx`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/CockpitTabs.jsx src/components/cockpit/__tests__/CockpitTabs.test.jsx
git commit -m "feat(cockpit): add Run+Review, Batch, Watchdog tabs"
```

---

## Task 18: CockpitView wiring

**Files:**
- Modify: `src/components/cockpit/CockpitView.jsx`
- Test: `src/components/cockpit/__tests__/CockpitView.test.jsx` (extend if present; otherwise add smoke test)

**Interfaces:**
- Consumes: `RunReviewPanel`, `BatchPanel`, `WatchdogPanel` panels; passes multi-select props to `AssignmentRail` when `tab === 'batch'`.

- [ ] **Step 1: Write/extend the failing test**

```jsx
// add to src/components/cockpit/__tests__/CockpitView.test.jsx (create if missing, mirroring existing mocks)
import { describe, it, expect, vi } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'

vi.mock('../../../api/bullhorn.js', () => ({ useBullhornAssignments: () => ({ data: { assignments: [] }, isLoading: false }) }))
vi.mock('../../../auth/AuthProvider.jsx', () => ({ useAuth: () => ({ user: { email: 'me@x.com' } }) }))
vi.mock('react-router-dom', () => ({ useNavigate: () => vi.fn() }))
vi.mock('../batch/BatchPanel.jsx', () => ({ default: () => <div>batch-panel</div> }))
vi.mock('../review/RunReviewPanel.jsx', () => ({ default: () => <div>run-review-panel</div> }))
vi.mock('../watchdog/WatchdogPanel.jsx', () => ({ default: () => <div>watchdog-panel</div> }))

import CockpitView from '../CockpitView.jsx'

describe('CockpitView tabs', () => {
  it('switches to the Batch panel', () => {
    renderWithProviders(<CockpitView />)
    fireEvent.click(screen.getByText(/Batch/i))
    expect(screen.getByText('batch-panel')).toBeInTheDocument()
  })
  it('switches to the Watchdog panel', () => {
    renderWithProviders(<CockpitView />)
    fireEvent.click(screen.getByText(/Watchdog/i))
    expect(screen.getByText('watchdog-panel')).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run — expect failure**

Run: `npx vitest run src/components/cockpit/__tests__/CockpitView.test.jsx`
Expected: FAIL — panels not rendered.

- [ ] **Step 3: Implement — edit `CockpitView.jsx`**

Add imports near the existing panel imports (after line 11):

```jsx
import RunReviewPanel from './review/RunReviewPanel.jsx'
import BatchPanel from './batch/BatchPanel.jsx'
import WatchdogPanel from './watchdog/WatchdogPanel.jsx'
```

Add batch-selection session state after the `doc` state (line 23):

```jsx
  const [batchIds, setBatchIds] = useSessionState('cockpit.batchIds', [])
  const toggleBatch = (id) => setBatchIds(prev => prev.includes(id) ? prev.filter(x => x !== id) : [...prev, id])
  const openReview = (id) => { setSelectedId(id); setDoc(null); setTab('review') }
```

Replace the `AssignmentRail` usage (lines 52-54) so batch mode passes multi props:

```jsx
        <AssignmentRail assignments={assignments} loading={isLoading}
          selectedId={selectedId} onPick={pick}
          onOpenReview={(id) => navigate(`/review/${id}`)}
          multi={tab === 'batch'} selectedIds={batchIds} onToggle={toggleBatch} />
```

Replace the panel render block (lines 65-66) with all five:

```jsx
        {tab === 'step'   && <StepRunPanel selectedId={selectedId} by={by} onOpenDoc={openDoc} />}
        {tab === 'review' && <RunReviewPanel selectedId={selectedId} by={by} onOpenDoc={openDoc} />}
        {tab === 'batch'  && <BatchPanel selectedIds={batchIds} by={by} />}
        {tab === 'watch'  && <WatchdogPanel onOpenReview={openReview} />}
        {tab === 'mail'   && <MailPanel />}
```

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/components/cockpit/__tests__/CockpitView.test.jsx`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/CockpitView.jsx src/components/cockpit/__tests__/CockpitView.test.jsx
git commit -m "feat(cockpit): wire Run+Review, Batch, Watchdog into CockpitView"
```

---

## Task 19: MailPanel — mount Bullhorn notes (MAIL drift repair, part 2)

**Files:**
- Modify: `src/components/cockpit/MailPanel.jsx`
- Test: `src/components/cockpit/__tests__/MailPanel.test.jsx` (extend)

**Interfaces:**
- Consumes: `BullhornNotesPanel` (Task 15).

- [ ] **Step 1: Add a failing test**

Add mock + assertion to the existing MailPanel test (mock the panel so it renders a sentinel):

```jsx
vi.mock('../mail/BullhornNotesPanel.jsx', () => ({ default: () => <div>bullhorn-notes</div> }))
// ...inside describe:
it('renders the held Bullhorn notes section', () => {
  renderWithProviders(<MailPanel />)
  expect(screen.getByText('bullhorn-notes')).toBeInTheDocument()
})
```

- [ ] **Step 2: Run — expect failure**

Run: `npx vitest run src/components/cockpit/__tests__/MailPanel.test.jsx`
Expected: FAIL — sentinel not present.

- [ ] **Step 3: Implement** — in `MailPanel.jsx` add the import and render it after the held-emails block (after line 36, before the closing `</div>`):

```jsx
import BullhornNotesPanel from './mail/BullhornNotesPanel.jsx'
// ...
      {sel && <PendingEmailPreview aid={sel} />}
      <BullhornNotesPanel />
```

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/components/cockpit/__tests__/MailPanel.test.jsx`
Expected: PASS (existing + new).

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/MailPanel.jsx src/components/cockpit/__tests__/MailPanel.test.jsx
git commit -m "feat(cockpit): mount held Bullhorn notes in Mail tab"
```

---

## Task 20: PendingEmailPreview — forms manifest (STEP drift repair, part 1)

**Files:**
- Modify: `src/components/cockpit/PendingEmailPreview.jsx`
- Test: `src/components/cockpit/__tests__/PendingEmailPreview.test.jsx` (extend)

**Interfaces:**
- Renders `m.forms_manifest` (array of `{ file, attached, reason }`) below the attachments when present. Additive; existing rendering unchanged. Follows the file's existing `useTokens` convention.

- [ ] **Step 1: Add a failing test**

```jsx
it('renders the forms manifest when present', () => {
  // configure the usePendingEmail mock to return forms_manifest — see existing test's mock setup
  // { found:true, to:'a@b.c', subject:'x', html_body:'<p>y</p>',
  //   forms_manifest:[{ file:'w9.pdf', attached:true }, { file:'skip.pdf', attached:false, reason:'not a form' }] }
  renderWithProviders(<PendingEmailPreview aid={1} />)
  expect(screen.getByText(/w9.pdf/)).toBeInTheDocument()
  expect(screen.getByText(/skipped/i)).toBeInTheDocument()
})
```

> If the existing test file mocks `usePendingEmail` inline, extend that mock's return value with `forms_manifest`. Otherwise add a `vi.mock('../../../api/email.js', ...)` returning the object above.

- [ ] **Step 2: Run — expect failure**

Run: `npx vitest run src/components/cockpit/__tests__/PendingEmailPreview.test.jsx`
Expected: FAIL — manifest text absent.

- [ ] **Step 3: Implement** — in `PendingEmailPreview.jsx`, insert after the header grid `</div>` and before the `<iframe>` (line 32→33):

```jsx
      {(m.forms_manifest || []).length > 0 && (
        <div className="px-4 py-2" style={{ borderTop: `1px solid ${t.cardBorder}` }}>
          <div className="text-[11px] mb-1" style={{ color: t.muted }}>📁 District forms folder — attached vs skipped:</div>
          {m.forms_manifest.map((f, i) => (
            <div key={i} className="text-[11.5px] py-0.5" style={{ color: t.text }}>
              {f.attached ? '✅' : '🚫'} {typeof f.file === 'string' ? f.file : (f.file?.name || '')}
              <span className="ml-1" style={{ color: t.muted }}>{f.attached ? 'attached (form)' : `skipped — ${f.reason || ''}`}</span>
            </div>
          ))}
        </div>
      )}
```

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/components/cockpit/__tests__/PendingEmailPreview.test.jsx`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/PendingEmailPreview.jsx src/components/cockpit/__tests__/PendingEmailPreview.test.jsx
git commit -m "feat(cockpit): render district forms manifest in held email"
```

---

## Task 21: GatePanel — Agent-4 table + Agent-5 richness (STEP drift repair, part 2)

**Files:**
- Modify: `src/components/cockpit/GatePanel.jsx`
- Test: `src/components/cockpit/__tests__/GatePanel.test.jsx` (extend)

**Interfaces:**
- Consumes: `RequirementsTable` (Task 7), `ChecklistReview` (Task 8).
- Behavior: `awaiting.agent === '4'` renders `RequirementsTable` (from `awaiting.output`) beside the verifier; the Agent-5 gate uses `ChecklistReview mode="correct"` feeding the same `onApprove(overrides)` contract.

> Read `GatePanel.jsx` first. Preserve the existing `overrides` state + `onApprove(overrides)` / `onAbort()` buttons and the agent-3 reassign / agent-6 email preview branches. Only the agent-4 and agent-5 branches change. The agent-5 correction callback must write into the same `overrides` object keyed by requirement (matching the existing approve payload the step-run backend expects).

- [ ] **Step 1: Add failing tests**

```jsx
// extend src/components/cockpit/__tests__/GatePanel.test.jsx
it('agent 4 gate shows the district requirements table', () => {
  renderWithProviders(<GatePanel aid={1} by="me@x.com" onApprove={() => {}} onAbort={() => {}}
    awaiting={{ agent: '4', name: 'Requirements', output: { matched_client_name: 'Springfield USD', requirements: [{ title: 'TB Test' }] }, verifier: null }} />)
  expect(screen.getByText('Springfield USD')).toBeInTheDocument()
  expect(screen.getByText('TB Test')).toBeInTheDocument()
})
```

- [ ] **Step 2: Run — expect failure**

Run: `npx vitest run src/components/cockpit/__tests__/GatePanel.test.jsx`
Expected: FAIL — requirements table not rendered at agent-4.

- [ ] **Step 3: Implement**

Add imports at the top of `GatePanel.jsx`:

```jsx
import RequirementsTable from './RequirementsTable.jsx'
import ChecklistReview from './ChecklistReview.jsx'
```

In the agent-branch switch, add an agent-4 branch BEFORE the generic two-column fallback (mirror how agent 5/3/6 are special-cased around GatePanel.jsx:38-48):

```jsx
  if (awaiting.agent === '4') {
    return (
      <GateShell aid={aid} awaiting={awaiting} by={by} overrides={overrides}
        onApprove={onApprove} onAbort={onAbort}>
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div><Label t={t}>District requirements — from DB</Label><RequirementsTable data={awaiting.output} /></div>
          <div><Label t={t}>Independent verifier</Label><VerifierView verifier={awaiting.verifier} /></div>
        </div>
      </GateShell>
    )
  }
```

> `GateShell` here denotes the existing wrapper (badge header + Approve/Abort buttons). If the current file inlines that markup rather than using a helper, replicate the same wrapper markup used by the other branches instead of inventing a new component — do NOT change the approve/abort wiring.

For agent 5, replace the body of the existing `Agent5Gate` with `ChecklistReview`, wiring its `onQueue(requirement, value)` into the same `setOverrides(prev => ({ ...prev, [requirement]: value }))` the current correction form uses:

```jsx
  // inside the agent-5 branch, replacing the checklist markup:
  <ChecklistReview
    review={reviewData}                 // the useReview(aid).data already loaded in this branch
    mode="correct"
    onOpenDoc={onOpenDoc}
    onQueue={(req, value) => setOverrides(prev => ({ ...prev, [req]: value }))}
  />
```

> Keep whatever `useReview(aid)` / OIG loading the existing `Agent5Gate` already does; `ChecklistReview` renders the OIG banner + unmatched panel itself, so remove the now-duplicated inline OIG/checklist markup to avoid double rendering.

- [ ] **Step 4: Run — expect pass (and full gate test file green)**

Run: `npx vitest run src/components/cockpit/__tests__/GatePanel.test.jsx`
Expected: PASS — new agent-4 test passes; existing approve/abort + agent-3/5/6 tests still green.

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/GatePanel.jsx src/components/cockpit/__tests__/GatePanel.test.jsx
git commit -m "feat(cockpit): agent-4 requirements table + agent-5 evidence at gates"
```

---

## Task 22: StepRunPanel — completion review (STEP drift repair, part 3)

**Files:**
- Modify: `src/components/cockpit/StepRunPanel.jsx`
- Test: `src/components/cockpit/__tests__/StepRunPanel.test.jsx` (extend)

**Interfaces:**
- Consumes: `CostTierSummary`, `RequirementsTable`, `ChecklistReview`, `PendingEmailPreview`, `useReview`, `useRequirements`.
- Behavior: when `s.status === 'complete'`, render a completion review (summary + requirements + checklist(view) + held email) instead of the bare `StatusCard('complete')`. `aborted`/`failed` cards unchanged.

- [ ] **Step 1: Add a failing test**

```jsx
// extend StepRunPanel.test.jsx — set the mocked run.status to complete and mock useReview/useRequirements
// Add near the top:
vi.mock('../../../api/review.js', () => ({ useReview: () => ({ data: { candidate: 'Jane', district: 'PS 1', hitl_tier: 'GREEN', checklist: [], cost: { total_usd: 0.02 } } }) }))
vi.mock('../../../api/requirements.js', () => ({ useRequirements: () => ({ data: { requirements: [] } }) }))
// In a new test, set fakeRun.jobId='j1', fakeRun.aid=1, fakeRun.status={ status:'complete', assignment_id:1, steps:[] }:
it('shows the completion review when the run completes', () => {
  fakeRun.jobId = 'j1'; fakeRun.aid = 1
  fakeRun.status = { status: 'complete', assignment_id: 1, steps: [] }
  renderWithProviders(<StepRunPanel selectedId={1} by="me@x.com" onOpenDoc={() => {}} />)
  expect(screen.getByText(/TIER GREEN/)).toBeInTheDocument()
})
```

- [ ] **Step 2: Run — expect failure**

Run: `npx vitest run src/components/cockpit/__tests__/StepRunPanel.test.jsx`
Expected: FAIL — completion review not rendered.

- [ ] **Step 3: Implement**

Add imports:

```jsx
import CostTierSummary from './CostTierSummary.jsx'
import RequirementsTable from './RequirementsTable.jsx'
import ChecklistReview from './ChecklistReview.jsx'
import PendingEmailPreview from './PendingEmailPreview.jsx'
import { useReview } from '../../api/review.js'
import { useRequirements } from '../../api/requirements.js'
```

Add a small `CompletionReview` component in the file (pure Tailwind is fine here; it's new markup):

```jsx
function CompletionReview({ aid, onOpenDoc }) {
  const review = useReview(aid).data
  const requirements = useRequirements(aid).data
  if (!review) return null
  return (
    <div className="rounded-2xl border border-[var(--border)] bg-brand-surface p-4">
      <CostTierSummary review={review} />
      <div className="mb-2 text-[10px] font-bold uppercase tracking-widest text-text-muted">District requirements</div>
      <RequirementsTable data={requirements} />
      <div className="mt-4"><ChecklistReview review={review} mode="view" onOpenDoc={onOpenDoc} /></div>
      <div className="mt-4"><PendingEmailPreview aid={aid} /></div>
    </div>
  )
}
```

Replace the completion arm of the render. Currently the paused/else block is:

```jsx
          {paused
            ? <GatePanel ... />
            : <StatusCard t={t} status={s?.status} />}
```

Change it to render the rich review on complete:

```jsx
          {paused ? (
            <GatePanel key={gateKey(s)} aid={aid} awaiting={s.awaiting} by={by}
              onApprove={(ov) => run.approve(by || 'cockpit_ui', ov)}
              onAbort={() => run.abort(by)} onOpenDoc={(file) => onOpenDoc(aid, file)} />
          ) : s?.status === 'complete' ? (
            <CompletionReview aid={aid} onOpenDoc={(file) => onOpenDoc(aid, file)} />
          ) : (
            <StatusCard t={t} status={s?.status} />
          )}
```

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/components/cockpit/__tests__/StepRunPanel.test.jsx`
Expected: PASS (existing + new).

- [ ] **Step 5: Commit**

```bash
git add src/components/cockpit/StepRunPanel.jsx src/components/cockpit/__tests__/StepRunPanel.test.jsx
git commit -m "feat(cockpit): rich step-run completion review"
```

---

## Task 23: Lost-session re-run affordance (STEP drift repair, part 4)

**Files:**
- Modify: `src/hooks/useStepRun.js` (expose a `lostAid`), `src/components/cockpit/StepRunPanel.jsx` (render a re-run button)
- Test: `src/components/cockpit/__tests__/StepRunPanel.test.jsx` (extend)

**Interfaces:**
- `useStepRun()` additionally returns `lostAid` — the assignment id of a job that vanished server-side (set in the `status.isError` branch before state is cleared), else `null`.

- [ ] **Step 1: Add a failing test**

```jsx
it('offers a re-run button when the prior job was lost', () => {
  fakeRun.jobId = null; fakeRun.status = null; fakeRun.lostAid = 149142
  renderWithProviders(<StepRunPanel selectedId={null} by="me@x.com" onOpenDoc={() => {}} />)
  const btn = screen.getByRole('button', { name: /re-run #149142/i })
  fireEvent.click(btn)
  expect(fakeRun.start).toHaveBeenCalledWith(149142)
})
```

> Add `lostAid: null` to the `fakeRun` object at the top of the test file so other tests keep passing.

- [ ] **Step 2: Run — expect failure**

Run: `npx vitest run src/components/cockpit/__tests__/StepRunPanel.test.jsx`
Expected: FAIL — no re-run button.

- [ ] **Step 3: Implement**

In `useStepRun.js`: add `const [lostAid, setLostAid] = useState(null)` near the other state (line 43). In the terminal effect's `status.isError` branch (lines 122-130), capture the aid before clearing:

```jsx
    } else if (status.isError) {
      setLostAid(aid)
      clearStepJob()
      setSavedJob(null)
      setJobId(null)
      setAid(null)
      closeStream()
    }
```

Clear it at the start of `start` (line 84, first line of the callback body): `setLostAid(null)`. Add `lostAid` to the returned object (line 143 area):

```jsx
    savedJob, lostAid,
```

In `StepRunPanel.jsx`, in the `!run.jobId` branch, show the re-run affordance when `run.lostAid` is set. Replace the `selectedId ? (...) : (...)` prompt with a version that prefers the lost-job re-run:

```jsx
        run.lostAid ? (
          <div className="rounded-2xl border p-4" style={{ borderColor: `${t.accent}55`, background: t.cardBg }}>
            <div className="text-[13px] font-bold" style={{ color: t.textStrong }}>
              ⚠ The previous run for #{run.lostAid} ended (the server may have restarted).
            </div>
            <div className="text-[11px] mt-1" style={{ color: t.muted }}>No data was lost — approvals &amp; corrections are saved.</div>
            <button onClick={() => run.start(run.lostAid)}
              className="mt-3 px-4 py-2 rounded-xl font-bold text-sm"
              style={{ background: 'linear-gradient(135deg,#005280,#1DAEEF)', color: '#fff', border: 'none', cursor: 'pointer' }}>
              ▶ re-run #{run.lostAid}
            </button>
          </div>
        ) : selectedId ? (
          // ...existing Initiate step run button unchanged...
```

> Keep the existing "Initiate step run" button and "Select a candidate" prompt exactly as they are for the non-lost cases.

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/components/cockpit/__tests__/StepRunPanel.test.jsx`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/hooks/useStepRun.js src/components/cockpit/StepRunPanel.jsx src/components/cockpit/__tests__/StepRunPanel.test.jsx
git commit -m "feat(cockpit): offer re-run when a step job is lost server-side"
```

---

## Task 24: Full-suite verification

**Files:** none (verification only)

- [ ] **Step 1: Run the whole suite**

Run: `npm test`
Expected: all tests pass (existing + new). If any pre-existing test broke, fix the regression in the file that caused it before proceeding.

- [ ] **Step 2: Build sanity check**

Run: `npm run build`
Expected: Vite build succeeds with no unresolved imports.

- [ ] **Step 3: Commit any fixups**

```bash
git add -A
git commit -m "test(cockpit): full suite green for run+review/batch/watchdog"
```

---

## Self-Review — spec coverage

- Spec §4 API hooks → Tasks 1–4. ✓ (watchdog, lookup, requirements, bullhornNotes, useJob)
- Spec §5 `useRunJob` → Task 5. ✓
- Spec §6.1 shared blocks → Tasks 6 (CostTierSummary), 7 (RequirementsTable), 8 (ChecklistReview + UnmatchedDocsPanel). ✓
- Spec §6.2 Run+Review → Tasks 11 (IdLookup), 12 (FullReview), 13 (RunReviewPanel). ✓
- Spec §6.3 Batch → Task 10. ✓
- Spec §6.4 Watchdog → Task 14. ✓
- Spec §6.5 ThinkingCharacter loading cartoon + email manifest → Tasks 9, 20. ✓ (Telemetry log terminal replaced by a cartoon loader per user request 2026-07-31)
- Spec §7.1 Held Bullhorn notes → Tasks 15, 19. ✓
- Spec §7.2 Step completion review → Task 22. ✓
- Spec §7.3 Agent-4 gate table → Task 21. ✓
- Spec §7.4 Agent-5 gate richness → Task 21. ✓
- Spec §7.5 Lost-session re-run → Task 23. ✓
- Spec §8 wiring (tabs, CockpitView, rail multi) → Tasks 16, 17, 18. ✓
- Spec §9 tests → colocated in every task + Task 24 full suite. ✓

**Type consistency check:** `useRunJob` returns `{ start, reset, jobId, status, logLines, agentsByAid, results, job }` — consumed identically in Tasks 10/13. `ChecklistReview` `onQueue(requirement, value)` — consumed in Tasks 12 (`queueChecklist`) and 21 (gate `setOverrides`). `IdLookup onRun(aid, label)` — consumed in Task 13. `WatchdogPanel onOpenReview(aid)` → CockpitView `openReview` (Task 18). No naming drift found.

# Dashboard + Shell Reference Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-skin the app shell (sidebar/topbar) and the Dashboard page to the UI/UX reference by adding the reference's exact class names + color scales as a theme-aware token layer — presentational only, zero functional change.

**Architecture:** A new `src/styles/reference.css` defines `@theme` color scales (backed by `[data-theme]`-flipping CSS variables) and a `@layer components` class layer (`.card`, `.stat-card*`, `.tier-bar`, `.data-table`, `.sidebar-link`, `.page-header`, …). Existing shell + dashboard components swap their inline per-theme JS style objects for these classes. All data hooks, pagination, tier math, snapshots, routes, flags, arrows, and the cartoon are preserved.

**Tech Stack:** React 19, Tailwind CSS v4.3 (`@tailwindcss/vite`, `@theme` + `@layer`), react-router-dom v7, `@tanstack/react-query` v5, Vitest + `@testing-library/react`, `@fontsource/plus-jakarta-sans`.

## Global Constraints

- **Presentational only, except Task 0.** Do NOT edit `src/api/*`, `src/console/*`, `src/auth/*`, `src/run/*`, routing, or any data hook. The ONLY data-logic change is Task 0's `effectiveTier` in `src/lib/dashboardHistory.js` (processed-but-untriaged → RED). Everything else is pure re-skin.
- **Theme-aware.** Every color used by a new class resolves through a CSS variable that has both a `:root` (light) and a `[data-theme="dark"]` value. No hardcoded slate/white hexes inside component classes.
- **Reproduce reference class names exactly:** `.card .card-header .card-title .stat-card .stat-card-primary|info|success|warning|danger .stat-icon .stat-label .stat-sub .stat-value .tier-col .tier-stack .tier-value .tier-bar .tier-label .table-responsive .data-table .badge .badge-danger .badge-live .badge-live-dot .badge-live-text .page-header .page-title .page-subtitle .btn .btn-light .dropdown-menu .dropdown-item .dropdown-caret .sidebar .sidebar-link .nav-icon .section-label .avatar .header .cell-index .cell-title .cell-sub .dot .page-backdrop`.
- **Preserve copy strings the tests assert (case-insensitive):** `Total Docs`, `nothing processed yet`, `Page {n} of {m} · 10 per page`, `{n} candidate(s)`, tier labels `APPROVED`/`VERIFICATION`/`REVIEW`, and per-row `Link` to `/review/{id}`.
- **Keep** the auditor-flag badge, the row → review chevron, the `ThinkingCharacter` cartoon, pulsing LIVE dot, tier-bar grow-in, stat hover-lift, staggered rows.
- **Tailwind only** for new styling; no new inline per-theme JS style objects in restyled files.
- **No live API in tests.** Mock hooks. Verify with `npm test` (= `vitest run`) and `npm run build`.
- **Commit after each task** with the shown message.

---

## Task 0: Reflect processed-but-untriaged assignments as RED

**Files:**
- Modify: `src/lib/dashboardHistory.js`
- Test: `src/lib/__tests__/dashboardHistory.test.js` (extend)

**Interfaces:**
- Produces: `isProcessedReview(review)` → boolean; `effectiveTier(assignment)` → `'RED'|'YELLOW'|'GREEN'|null`. `tierCounts`, `buildCandidateRows`, and `buildSnapshotPayload` use `effectiveTier` so done-but-untriaged assignments count as RED.

**Context:** Live API testing (`:8005`) showed 7/21 done assignments have `hitl_tier: null` but real `counts`/`candidate`; they were dropped by the RYG filter. Rule: a review is *processed* if it has a truthy `candidate` OR a `counts` object containing any of the six known count keys. Processed + no valid tier → treat as `RED`. Empty `{}` reviews stay `null` (excluded), preserving existing tests.

- [ ] **Step 1: Write the failing tests** (append to `src/lib/__tests__/dashboardHistory.test.js`)

```jsx
import { effectiveTier, isProcessedReview } from '../dashboardHistory.js'

describe('effectiveTier (untriaged → RED)', () => {
  it('passes real RYG tiers through', () => {
    expect(effectiveTier({ review: { hitl_tier: 'GREEN', counts: { valid: 5 } } })).toBe('GREEN')
    expect(effectiveTier({ review: { hitl_tier: 'YELLOW', counts: {} } })).toBe('YELLOW')
  })
  it('treats a processed but null-tier assignment as RED', () => {
    expect(effectiveTier({ review: { hitl_tier: null, candidate: 'X',
      counts: { valid: 1, missing: 14, auditor_flags: 1 } } })).toBe('RED')
  })
  it('leaves a genuinely empty review untriaged (null)', () => {
    expect(effectiveTier({ review: {} })).toBe(null)
    expect(isProcessedReview({})).toBe(false)
    expect(isProcessedReview({ counts: { missing: 2 } })).toBe(true)
    expect(isProcessedReview({ candidate: 'Y' })).toBe(true)
  })
})

describe('tierCounts + buildCandidateRows include untriaged-as-RED', () => {
  const set = [
    { assignment_id: 1, review: { hitl_tier: 'GREEN', candidate: 'G', district: 'D',
      counts: { valid: 5, expiring: 0, expired: 0, missing: 0, unreadable: 0, auditor_flags: 0 } } },
    { assignment_id: 2, review: { hitl_tier: null, candidate: 'Untriaged', district: 'D2',
      counts: { valid: 1, expiring: 0, expired: 0, missing: 14, unreadable: 0, auditor_flags: 1 } } },
    { assignment_id: 3, review: {} }, // truly empty → excluded
  ]
  it('counts the untriaged one as red + total', () => {
    expect(tierCounts(set)).toEqual({ total: 2, ready: 0, green: 1, yellow: 0, red: 1 })
  })
  it('lists the untriaged one as a RED row, most-severe first', () => {
    const { rows } = buildCandidateRows(set)
    expect(rows.map((r) => r.assignment_id)).toEqual([2, 1]) // RED(untriaged) before GREEN
    expect(rows[0].tier).toBe('RED')
    expect(rows.some((r) => r.assignment_id === 3)).toBe(false) // empty excluded
  })
})
```

- [ ] **Step 2: Run — expect fail**

Run: `npx vitest run src/lib/__tests__/dashboardHistory.test.js`
Expected: FAIL — `effectiveTier`/`isProcessedReview` not exported.

- [ ] **Step 3: Implement in `src/lib/dashboardHistory.js`.** Add near the top (after `numOr0`):

```js
const COUNT_KEYS = ['valid', 'expiring', 'expired', 'missing', 'unreadable', 'auditor_flags']

/** True when a review reflects a real pipeline run (vs. an empty/pending stub). */
export function isProcessedReview(review) {
  if (!review || typeof review !== 'object') return false
  if (review.candidate) return true
  const c = review.counts
  return !!(c && typeof c === 'object' && COUNT_KEYS.some((k) => k in c))
}

/** Tier the dashboard should use: a real RED/YELLOW/GREEN, else RED for a processed-but-
 *  untriaged assignment (done work the triage gate left tier-less still needs review),
 *  else null for an empty/pending review. */
export function effectiveTier(assignment) {
  const r = assignment?.review || {}
  if (r.hitl_tier === 'RED' || r.hitl_tier === 'YELLOW' || r.hitl_tier === 'GREEN') return r.hitl_tier
  return isProcessedReview(r) ? 'RED' : null
}
```

Then rewire the three consumers to use `effectiveTier`:

- `tierCounts` — replace `const t = a.review?.hitl_tier` with `const t = effectiveTier(a)` (the `ready` tally stays `a.review?.ready`).
- `buildCandidateRows` — change the filter to `.filter((a) => effectiveTier(a) !== null)`, the sort's tier reads to `TIER_RANK[effectiveTier(y)] - TIER_RANK[effectiveTier(x)]`, and each row's `tier:` to `effectiveTier(a)`.
- `buildSnapshotPayload` — replace `const tier = ['RED','YELLOW','GREEN'].includes(r.hitl_tier) ? r.hitl_tier : null` with `const tier = effectiveTier(a)` (so history persists the same view).

- [ ] **Step 4: Run — expect pass (new + existing)**

Run: `npx vitest run src/lib/__tests__/dashboardHistory.test.js`
Expected: PASS — new tests pass AND the existing `tierCounts`/`buildCandidateRows`/`buildSnapshotPayload` tests stay green (their empty `{}` reviews remain excluded).

- [ ] **Step 5: Commit**

```bash
git add src/lib/dashboardHistory.js src/lib/__tests__/dashboardHistory.test.js
git commit -m "fix(dashboard): reflect processed-but-untriaged assignments as RED (effectiveTier)"
```

---

## Task 1: Token + component-class layer & font

**Files:**
- Create: `src/styles/reference.css`
- Modify: `src/styles/globals.css` (add font imports + `@import "./reference.css";`)
- Modify: `package.json` (dependency added by `npm i`)
- Test: `src/styles/__tests__/referenceClasses.test.jsx` (smoke)

**Interfaces:**
- Produces: the global CSS classes and color tokens every later task consumes. No JS exports.

- [ ] **Step 1: Install the font**

Run: `npm i @fontsource-variable/plus-jakarta-sans`
(If the variable package is unavailable, fall back to `npm i @fontsource/plus-jakarta-sans`.)

- [ ] **Step 2: Write the smoke test (expected to fail)**

```jsx
// src/styles/__tests__/referenceClasses.test.jsx
import { describe, it, expect } from 'vitest'
import { renderWithProviders } from '../../test-utils/render.jsx'

// The class layer is global CSS; we can't assert computed color in jsdom, but we
// CAN assert the app stylesheet imports compile and an element keeps its classes.
describe('reference class layer', () => {
  it('renders an element carrying the reference classes without crashing', () => {
    const { container } = renderWithProviders(
      <div className="card">
        <div className="card-header"><span className="card-title">X</span></div>
        <div className="stat-card stat-card-primary">
          <span className="stat-value">6</span>
        </div>
      </div>,
    )
    expect(container.querySelector('.stat-card-primary')).not.toBeNull()
    expect(container.querySelector('.card-title')?.textContent).toBe('X')
  })
})
```

- [ ] **Step 3: Run it — expect fail**

Run: `npx vitest run src/styles/__tests__/referenceClasses.test.jsx`
Expected: FAIL — file/imports not yet wired (or passes trivially; either way proceed to wire CSS).

- [ ] **Step 4: Create `src/styles/reference.css`**

```css
/* src/styles/reference.css — UI/UX reference token + component-class layer.
   Theme-aware: light on :root, dark under [data-theme="dark"]. Hues reuse the
   existing SEM palette so the redesign stays on-brand. */

:root {
  --ref-canvas: #f1f5f9;  --ref-surface: #ffffff;  --ref-surface-2: #f7fafc;
  --ref-border: #e6ebf2;  --ref-divider: #eef1f6;
  --ref-shadow: 0 1px 2px rgba(22,35,58,.05), 0 8px 24px rgba(22,35,58,.05);
  --ref-shadow-hover: 0 10px 24px -14px rgba(22,35,58,.24);
  --ref-heading: #16233a; --ref-text: #3a4a62; --ref-muted: #93a1b5; --ref-label: #9aa7ba;
  --ref-primary-50: #eff5ff; --ref-primary-100: #dbe6ff; --ref-primary-500: #2f6fed;
  --ref-primary-600: #1b74c4; --ref-primary-700: #005280;
  --ref-info: #2f6fed; --ref-info-100: #e6eefe;
  --ref-success: #1f8a5b; --ref-success-100: #e7f4ee; --ref-success-200: #c7e8d5;
  --ref-warning: #e8930c; --ref-warning-100: #fdf3e2; --ref-warning-200: #f8e2bd;
  --ref-danger: #e5484d; --ref-danger-100: #fdeaea; --ref-danger-200: #f8cfd0;
  --ref-ink-600: #5b6b85;
  --ref-row: #fcfafa; --ref-row-hover: #fdf6f6;
  --ref-zero-bg: #f4f6fa; --ref-zero-border: #eceff4; --ref-zero-text: #b4becc;
}

[data-theme="dark"] {
  --ref-canvas: #071525; --ref-surface: rgba(19,26,43,0.7); --ref-surface-2: rgba(10,16,30,0.6);
  --ref-border: rgba(124,164,255,0.12); --ref-divider: rgba(124,164,255,0.08);
  --ref-shadow: 0 1px 2px rgba(0,0,0,.30); --ref-shadow-hover: 0 10px 24px -14px rgba(0,0,0,.55);
  --ref-heading: #EAF1FF; --ref-text: #AEBBD6; --ref-muted: #6B7A98; --ref-label: #90A1C0;
  --ref-primary-50: rgba(43,111,237,0.16); --ref-primary-100: rgba(43,111,237,0.24);
  --ref-primary-500: #5BA8FF; --ref-primary-600: #7cc4ff; --ref-primary-700: #8ec8ff;
  --ref-info: #7cc4ff; --ref-info-100: rgba(47,111,237,0.18);
  --ref-success: #46c08a; --ref-success-100: rgba(31,138,91,0.16); --ref-success-200: rgba(31,138,91,0.34);
  --ref-warning: #f0b03e; --ref-warning-100: rgba(232,147,12,0.16); --ref-warning-200: rgba(232,147,12,0.34);
  --ref-danger: #ef6a6e; --ref-danger-100: rgba(229,72,77,0.16); --ref-danger-200: rgba(229,72,77,0.34);
  --ref-ink-600: #8593a8;
  --ref-row: rgba(124,164,255,0.04); --ref-row-hover: rgba(124,164,255,0.08);
  --ref-zero-bg: rgba(124,164,255,0.05); --ref-zero-border: rgba(124,164,255,0.10); --ref-zero-text: #5E6E8C;
}

@theme {
  --color-primary-50: var(--ref-primary-50);   --color-primary-100: var(--ref-primary-100);
  --color-primary-500: var(--ref-primary-500); --color-primary-600: var(--ref-primary-600);
  --color-primary-700: var(--ref-primary-700);
  --color-info: var(--ref-info);
  --color-success: var(--ref-success);   --color-success-100: var(--ref-success-100);   --color-success-200: var(--ref-success-200);
  --color-warning: var(--ref-warning);   --color-warning-100: var(--ref-warning-100);   --color-warning-200: var(--ref-warning-200);
  --color-danger: var(--ref-danger);     --color-danger-100: var(--ref-danger-100);     --color-danger-200: var(--ref-danger-200);
  --color-ink-600: var(--ref-ink-600);
  --color-heading: var(--ref-heading);   --color-ref-muted: var(--ref-muted);
  --font-jakarta: "Plus Jakarta Sans Variable", "Plus Jakarta Sans", "Geist", sans-serif;
}

@layer components {
  /* ── cards ── */
  .card { background: var(--ref-surface); border: 1px solid var(--ref-border);
    border-radius: 18px; box-shadow: var(--ref-shadow); overflow: hidden;
    display: flex; flex-direction: column; font-family: var(--font-jakarta); }
  .card-header { padding: 14px 22px; border-bottom: 1px solid var(--ref-divider);
    display: flex; align-items: center; justify-content: space-between; }
  .card-title { font-size: 12px; font-weight: 800; letter-spacing: 1px;
    text-transform: uppercase; color: var(--ref-muted); }

  /* ── stat cards ── */
  .stat-card { position: relative; display: flex; align-items: center; gap: 12px;
    padding: 15px 17px 15px 16px; border-radius: 14px; background: var(--ref-surface);
    border: 1px solid var(--ref-border); border-left: 3px solid var(--stat-accent, var(--ref-primary-600));
    box-shadow: var(--ref-shadow); transition: transform .18s ease, box-shadow .18s ease, border-color .18s ease; }
  .stat-card:hover { transform: translateY(-2px); box-shadow: var(--ref-shadow-hover); }
  .stat-card-primary { --stat-accent: var(--ref-primary-600); }
  .stat-card-info    { --stat-accent: var(--ref-info); }
  .stat-card-success { --stat-accent: var(--ref-success); }
  .stat-card-warning { --stat-accent: var(--ref-warning); }
  .stat-card-danger  { --stat-accent: var(--ref-danger); }
  .stat-icon { width: 38px; height: 38px; flex: none; border-radius: 10px; display: flex;
    align-items: center; justify-content: center;
    background: color-mix(in srgb, var(--stat-accent) 12%, transparent); color: var(--stat-accent); }
  .stat-label { font-size: 12.5px; font-weight: 700; color: var(--ref-text); line-height: 1.15; }
  .stat-sub   { font-size: 10.5px; font-weight: 600; color: var(--ref-label); margin-top: 2px; }
  .stat-value { margin-left: auto; font-size: 28px; font-weight: 800; letter-spacing: -1.2px;
    line-height: 1; color: var(--ref-heading); font-variant-numeric: tabular-nums; }

  /* ── tier bars ── */
  .tier-col { flex: 1; max-width: 84px; display: flex; flex-direction: column;
    align-items: center; justify-content: flex-end; gap: 10px; height: 100%; }
  .tier-stack { position: relative; flex: 1; width: 100%; display: flex; align-items: flex-end; }
  .tier-value { position: absolute; left: 0; right: 0; top: -24px; text-align: center;
    font-size: 18px; font-weight: 800; font-variant-numeric: tabular-nums; }
  .tier-bar { width: 100%; border-radius: 10px 10px 0 0; border: 1px solid transparent; }
  .tier-label { font-size: 10px; font-weight: 600; letter-spacing: .4px; color: var(--ref-muted); white-space: nowrap; }

  /* ── data table ── */
  .table-responsive { overflow-x: auto; }
  .data-table { width: 100%; border-collapse: collapse; font-family: var(--font-jakarta); }
  .data-table th { font-size: 9.5px; font-weight: 800; text-transform: uppercase; letter-spacing: .3px;
    color: var(--ref-muted); text-align: center; padding: 10px 8px; border-bottom: 1px solid var(--ref-divider); }
  .data-table th:nth-child(2) { text-align: left; }
  .data-table td { padding: 10px 8px; text-align: center; }

  /* ── badges ── */
  .badge { display: inline-flex; align-items: center; gap: 6px; padding: 5px 11px; border-radius: 999px;
    font-size: 11.5px; font-weight: 700; font-family: var(--font-jakarta); }
  .badge-danger { color: var(--ref-danger); background: var(--ref-danger-100); }
  .badge-live { display: inline-flex; align-items: center; gap: 6px; padding: 4px 10px; border-radius: 999px;
    background: var(--ref-success-100); }
  .badge-live-dot { position: relative; width: 6px; height: 6px; border-radius: 999px; background: var(--ref-success); }
  .badge-live-dot::after { content: ""; position: absolute; inset: 0; border-radius: 999px;
    background: var(--ref-success); animation: pulse 2s ease-in-out infinite; }
  .badge-live-text { font-size: 10px; font-weight: 800; letter-spacing: 1px; color: var(--ref-success); }

  /* ── page head ── */
  .page-header { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between;
    gap: 20px; margin-bottom: 24px; padding-left: 14px; border-left: 3px solid var(--ref-primary-600); }
  .page-title { margin: 0; font-size: 30px; font-weight: 800; letter-spacing: -.9px; line-height: 1;
    color: var(--ref-heading); font-family: var(--font-jakarta); }
  .page-subtitle { margin: 7px 0 0; font-size: 13px; font-weight: 600; letter-spacing: .2px;
    text-transform: uppercase; color: var(--ref-muted); font-family: var(--font-jakarta); }

  /* ── buttons / dropdown ── */
  .btn { display: inline-flex; align-items: center; gap: 9px; height: 40px; padding: 0 14px;
    border-radius: 10px; font-size: 13.5px; font-weight: 700; cursor: pointer; font-family: var(--font-jakarta);
    border: 1px solid var(--ref-border); background: var(--ref-surface); color: var(--ref-text); }
  .btn-light { background: var(--ref-surface); }
  .dropdown-caret { transition: transform .18s ease; }
  .dropdown-menu { position: absolute; top: 46px; right: 0; min-width: 190px; padding: 6px; z-index: 20;
    display: flex; flex-direction: column; gap: 2px; border-radius: 12px;
    background: var(--ref-surface); border: 1px solid var(--ref-border);
    box-shadow: 0 12px 30px -12px rgba(22,35,58,.28); }
  .dropdown-item { display: flex; align-items: center; gap: 10px; text-align: left; padding: 9px 11px;
    border-radius: 8px; font-size: 13px; font-weight: 600; cursor: pointer; color: var(--ref-text);
    background: transparent; border: none; font-family: var(--font-jakarta); }
  .dropdown-item:hover { background: var(--ref-surface-2); }

  /* ── shell ── */
  .sidebar { background: var(--ref-surface); border-right: 1px solid var(--ref-border);
    display: flex; flex-direction: column; height: 100%; overflow: hidden; font-family: var(--font-jakarta); }
  .section-label { font-size: 10.5px; font-weight: 700; letter-spacing: 1.3px; color: var(--ref-label); }
  .sidebar-link { position: relative; display: flex; align-items: center; gap: 12px; padding: 11px 12px;
    border-radius: 11px; text-decoration: none; font-size: 14px; font-weight: 600; color: var(--ref-muted);
    transition: background .18s ease, color .18s ease; }
  .sidebar-link:hover { background: var(--ref-primary-50); color: var(--ref-primary-600); }
  .sidebar-link.is-active { background: var(--ref-primary-50); color: var(--ref-primary-600); font-weight: 700;
    box-shadow: inset 0 0 0 1px var(--ref-primary-100); }
  .sidebar-link.is-active::before { content: ""; position: absolute; left: 0; top: 9px; bottom: 9px; width: 3px;
    border-radius: 0 4px 4px 0; background: var(--ref-primary-600); }
  .nav-icon { width: 20px; height: 20px; flex: none; display: flex; align-items: center; justify-content: center; }
  .avatar { width: 38px; height: 38px; flex: none; border-radius: 50%; display: flex; align-items: center;
    justify-content: center; color: #fff; font-weight: 700; font-size: 13px;
    background: linear-gradient(135deg,#18a9cf,#1b74c4); }
  .header { height: 56px; display: flex; align-items: center; justify-content: space-between; padding: 0 16px;
    background: color-mix(in srgb, var(--ref-surface) 85%, transparent); backdrop-filter: blur(10px);
    border-bottom: 1px solid var(--ref-border); position: sticky; top: 0; z-index: 40; font-family: var(--font-jakarta); }

  /* ── table cells / misc ── */
  .cell-index { font-size: 13px; font-weight: 800; color: var(--ref-label); font-variant-numeric: tabular-nums; }
  .cell-title { font-size: 14px; font-weight: 700; color: var(--ref-heading); }
  .cell-sub   { font-size: 12px; color: var(--ref-label); }
  .dot { width: 7px; height: 7px; border-radius: 999px; flex: none; }
  .page-backdrop { position: absolute; inset: 0; pointer-events: none; z-index: 0; background: var(--ref-canvas); }
}
```

- [ ] **Step 5: Wire into `src/styles/globals.css`**

Add the font imports alongside the other `@fontsource` imports near the top (variable package shown; use the static path if you installed the fallback):

```css
@import "@fontsource-variable/plus-jakarta-sans";
```

Then immediately AFTER the existing `@import "tailwindcss";` line, add:

```css
@import "./reference.css";
```

- [ ] **Step 6: Run the smoke test + build**

Run: `npx vitest run src/styles/__tests__/referenceClasses.test.jsx`
Expected: PASS.
Run: `npm run build`
Expected: build succeeds (Tailwind compiles `@theme` + `@layer components`).

- [ ] **Step 7: Confirm nothing regressed**

Run: `npm test`
Expected: PASS (same as baseline).

- [ ] **Step 8: Commit**

```bash
git add src/styles/reference.css src/styles/globals.css src/styles/__tests__/referenceClasses.test.jsx package.json package-lock.json
git commit -m "feat(dashboard): reference token + component-class layer + Plus Jakarta Sans"
```

---

## Task 2: StatCard → `.stat-card` variants

**Files:**
- Modify: `src/components/dashboard/StatCard.jsx`
- Test: `src/components/dashboard/__tests__/StatCard.test.jsx` (create)

**Interfaces:**
- Consumes: reference classes from Task 1.
- Produces: `<StatCard icon label sub value variant />` where `variant ∈ 'primary'|'info'|'success'|'warning'|'danger'`. Keeps the count-up animation. (New optional prop `variant`; existing `accent` prop is removed — Task 3 updates the caller.)

- [ ] **Step 1: Write the failing test**

```jsx
// src/components/dashboard/__tests__/StatCard.test.jsx
import { describe, it, expect } from 'vitest'
import { renderWithProviders } from '../../../test-utils/render.jsx'
import StatCard from '../StatCard.jsx'

describe('StatCard', () => {
  it('renders label, sub, value and the variant class', () => {
    const { container, getByText } = renderWithProviders(
      <StatCard icon={<svg />} label="Total Candidates" sub="Active in portfolio" value={6} variant="primary" />,
    )
    expect(getByText('Total Candidates')).toBeInTheDocument()
    expect(getByText('Active in portfolio')).toBeInTheDocument()
    expect(container.querySelector('.stat-card.stat-card-primary')).not.toBeNull()
    expect(container.querySelector('.stat-value')).not.toBeNull()
  })
})
```

- [ ] **Step 2: Run — expect fail**

Run: `npx vitest run src/components/dashboard/__tests__/StatCard.test.jsx`
Expected: FAIL — no `.stat-card-primary` (component still inline-styled).

- [ ] **Step 3: Rewrite `StatCard.jsx`** (keep the `useCountUp` helper verbatim; replace the returned JSX)

```jsx
import { useEffect, useRef, useState } from 'react'

function useCountUp(target, duration = 900) {
  const [count, setCount] = useState(0)
  const raf = useRef(0)
  useEffect(() => {
    const to = typeof target === 'number' ? target : 0
    let start = null
    const tick = (ts) => {
      if (start === null) start = ts
      const p = Math.min((ts - start) / duration, 1)
      setCount(Math.round(to * (1 - Math.pow(1 - p, 3))))
      if (p < 1) raf.current = requestAnimationFrame(tick)
    }
    raf.current = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf.current)
  }, [target, duration])
  return count
}

/** One stat card matching the reference: accent left-border, tinted icon chip,
 *  label + sub, big count-up value. `variant` selects the accent color. */
export default function StatCard({ icon, label, sub, value, variant = 'primary', className = '' }) {
  const animated = useCountUp(typeof value === 'number' ? value : 0)
  return (
    <div className={`stat-card stat-card-${variant} stagger-item ${className}`}>
      <div className="stat-icon">{icon}</div>
      <div className="min-w-0 flex-1">
        <div className="stat-label truncate">{label}</div>
        <div className="stat-sub truncate">{sub}</div>
      </div>
      <div className="stat-value tabnum">{animated.toLocaleString()}</div>
    </div>
  )
}
```

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/components/dashboard/__tests__/StatCard.test.jsx`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/dashboard/StatCard.jsx src/components/dashboard/__tests__/StatCard.test.jsx
git commit -m "feat(dashboard): StatCard uses .stat-card reference classes"
```

---

## Task 3: PortfolioSummary → `.card` + stat grid

**Files:**
- Modify: `src/components/dashboard/PortfolioSummary.jsx`
- Test: `src/components/dashboard/__tests__/PortfolioSummary.test.jsx` (create)

**Interfaces:**
- Consumes: `StatCard` with the new `variant` prop (Task 2).
- Produces: `<PortfolioSummary total ready green yellow red className style />` unchanged prop shape.

- [ ] **Step 1: Write the failing test**

```jsx
// src/components/dashboard/__tests__/PortfolioSummary.test.jsx
import { describe, it, expect } from 'vitest'
import { renderWithProviders } from '../../../test-utils/render.jsx'
import PortfolioSummary from '../PortfolioSummary.jsx'

describe('PortfolioSummary', () => {
  it('renders the header, five stat cards and the danger Must Review card', () => {
    const { container, getByText } = renderWithProviders(
      <PortfolioSummary total={6} ready={0} green={0} yellow={0} red={6} />,
    )
    expect(getByText('PORTFOLIO SUMMARY')).toBeInTheDocument()
    expect(getByText('Total Candidates')).toBeInTheDocument()
    expect(getByText('Must Review')).toBeInTheDocument()
    expect(container.querySelectorAll('.stat-card').length).toBe(5)
    expect(container.querySelector('.stat-card-danger')).not.toBeNull()
  })
})
```

- [ ] **Step 2: Run — expect fail**

Run: `npx vitest run src/components/dashboard/__tests__/PortfolioSummary.test.jsx`
Expected: FAIL.

- [ ] **Step 3: Rewrite `PortfolioSummary.jsx`** (keep the five icon components verbatim; replace the wrapper + StatCard calls)

Replace the `useTokens`/`dashboardPalette` import block and the returned JSX with:

```jsx
import StatCard from './StatCard.jsx'
// ...keep PeopleIcon, CheckIcon, ShieldCheckIcon, ShieldIcon, AlertIcon exactly as they are...

export default function PortfolioSummary({ total, ready, green, yellow, red, style, className = '' }) {
  return (
    <section className={`card ${className}`} style={style}>
      <div className="card-header"><span className="card-title">Portfolio Summary</span></div>
      <div className="p-4 flex flex-col gap-3 flex-1">
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <StatCard icon={<PeopleIcon />} label="Total Candidates" sub="Active in portfolio" value={total} variant="primary" />
          <StatCard icon={<CheckIcon />} label="Placement Ready" sub="Fully credentialed" value={ready} variant="info" />
          <StatCard icon={<ShieldCheckIcon />} label="Auto Approved" sub="Cleared automatically" value={green} variant="success" />
          <StatCard icon={<ShieldIcon />} label="Needs Verification" sub="Awaiting verification" value={yellow} variant="warning" />
        </div>
        <StatCard icon={<AlertIcon />} label="Must Review" sub="Manual review required" value={red} variant="danger" />
      </div>
    </section>
  )
}
```

Note: `.card-title` uppercases via CSS, so `Portfolio Summary` renders as `PORTFOLIO SUMMARY` — the test uses that uppercased text.

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/components/dashboard/__tests__/PortfolioSummary.test.jsx`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/dashboard/PortfolioSummary.jsx src/components/dashboard/__tests__/PortfolioSummary.test.jsx
git commit -m "feat(dashboard): PortfolioSummary uses .card + stat-card grid"
```

---

## Task 4: TierDistribution → `.tier-*`

**Files:**
- Modify: `src/components/dashboard/TierDistribution.jsx`
- Test: `src/components/dashboard/__tests__/NeedsReviewTable.test.jsx` (existing TierDistribution block must stay green; add a class assertion)

**Interfaces:**
- Produces: `<TierDistribution green yellow red caption className style />` unchanged.

- [ ] **Step 1: Extend the existing test (add class assertion)**

In `src/components/dashboard/__tests__/NeedsReviewTable.test.jsx`, inside the existing `TierDistribution (render)` test, add after the caption assertion:

```jsx
    const { container } = renderWithProviders(
      <TierDistribution green={1} yellow={2} red={3} caption="x" />,
    )
    expect(container.querySelectorAll('.tier-col').length).toBe(3)
    expect(container.querySelector('.tier-bar')).not.toBeNull()
```

- [ ] **Step 2: Run — expect fail**

Run: `npx vitest run src/components/dashboard/__tests__/NeedsReviewTable.test.jsx`
Expected: FAIL on the new `.tier-col` assertion.

- [ ] **Step 3: Rewrite `TierDistribution.jsx`** (keep the `grown` mount animation + `bars`/`max` logic; swap styling to classes)

```jsx
import { useEffect, useState } from 'react'
import { SEM } from './dashboardTheme.js'

export default function TierDistribution({ green = 0, yellow = 0, red = 0, caption, style, className = '' }) {
  const [grown, setGrown] = useState(false)
  useEffect(() => { const id = requestAnimationFrame(() => setGrown(true)); return () => cancelAnimationFrame(id) }, [])

  const bars = [
    { label: 'APPROVED', value: green, color: SEM.green },
    { label: 'VERIFICATION', value: yellow, color: SEM.yellow },
    { label: 'REVIEW', value: red, color: SEM.red },
  ]
  const max = Math.max(green, yellow, red, 1)

  return (
    <section className={`card ${className}`} style={style}>
      <div className="card-header"><span className="card-title">Tier Distribution</span></div>
      <div className="flex-1 flex items-end justify-center gap-5" style={{ padding: '30px 22px 16px', minHeight: 150 }}>
        {bars.map((b) => {
          const target = 50 + (b.value / max) * 50
          const pct = grown ? target : 0
          return (
            <div key={b.label} className="tier-col">
              <div className="tier-stack">
                <div className="tier-bar" style={{
                  height: `${pct}%`, minHeight: 6,
                  background: `linear-gradient(180deg, ${b.color}, ${b.color}b3)`,
                  borderColor: `${b.color}66`, boxShadow: `0 0 16px ${b.color}3d`,
                  transition: 'height 0.8s cubic-bezier(0.16,1,0.3,1)',
                }}>
                  <div className="tier-value" style={{ color: b.color }}>{b.value}</div>
                </div>
              </div>
              <div className="tier-label">{b.label}</div>
            </div>
          )
        })}
      </div>
      {caption && <div className="px-5 pb-4 pt-1 text-center text-[11.5px] font-medium" style={{ color: 'var(--ref-muted)', fontFamily: 'var(--font-jakarta)' }}>{caption}</div>}
    </section>
  )
}
```

Note: the per-bar hue stays inline because it's data-driven (semantic color per tier) — this is a value, not a theme color, so it's allowed. Layout/surface styling comes from classes.

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/components/dashboard/__tests__/NeedsReviewTable.test.jsx`
Expected: PASS (all blocks).

- [ ] **Step 5: Commit**

```bash
git add src/components/dashboard/TierDistribution.jsx src/components/dashboard/__tests__/NeedsReviewTable.test.jsx
git commit -m "feat(dashboard): TierDistribution uses .tier-* reference classes"
```

---

## Task 5: NeedsReviewTable → `.card` + `.data-table`

**Files:**
- Modify: `src/components/dashboard/NeedsReviewTable.jsx`
- Test: `src/components/dashboard/__tests__/NeedsReviewTable.test.jsx` (existing tests must all stay green)

**Interfaces:**
- Consumes: `buildCandidateRows`, `paginate` (unchanged), reference classes.
- Produces: `<NeedsReviewTable assignments />` — same behavior (list all processed candidates, 10/page, links, flag, chevron, totals row).

**Preserve exactly** (asserted by existing tests): the count badge text `{n} candidate(s)`, header + totals `Total Docs`, empty-state `Nothing processed yet`, `Page {n} of {m} · 10 per page`, page buttons named by number, one `Link` per row to `/review/{id}` (so `getAllByRole('link')` counts match).

- [ ] **Step 1: Confirm the existing tests are the guardrail**

Run: `npx vitest run src/components/dashboard/__tests__/NeedsReviewTable.test.jsx`
Expected: PASS now (baseline before edits).

- [ ] **Step 2: Restyle keeping structure.** Keep `PAGE_SIZE`, `COLS`, `TIER_COLOR`, `FlagIcon`, `pageWindow`, `Pager`, `NumCell`, `buildCandidateRows`, `paginate`, the per-row `<Link to={\`/review/${r.assignment_id}\`}>`, the flag badge, and the chevron. Apply these class swaps (values that are semantic per-column colors stay inline; surfaces move to classes):
  - Outer `<section>` → `className="card"` (drop the inline panel bg/border/shadow).
  - Header row → keep the `.dot` (semantic red), title text `ACT NOW — NEEDS REVIEW`, and the count badge → `className="badge badge-danger"` showing `{rows.length} candidate{…}`.
  - Column-header cells and rows may keep the existing CSS-grid layout (`GRID`) — it is layout, not theme color — but recolor header labels via `text-[color:var(--ref-muted)]` and row surfaces via `bg-[color:var(--ref-row)]` hover `var(--ref-row-hover)`.
  - `NumCell`: replace `P.zeroBg/zeroBorder/zeroText` with `var(--ref-zero-bg)/var(--ref-zero-border)/var(--ref-zero-text)`; keep the semantic `color` tints for non-zero values.
  - `cell-index`, candidate name → `.cell-title`, facility → `.cell-sub`.
  - `Pager`: keep all logic + copy; recolor borders/hover to `var(--ref-border)`/`var(--ref-row-hover)` and the active page to `var(--ref-primary-600)`.
  - Remove the `useTokens`/`dashboardPalette` import; replace `P.*` reads with the `--ref-*` vars above.

  (The grid/rows stay because the existing pagination + link-count tests depend on one `<Link>` per row and the `Total Docs`/`Page x of y` copy — do not convert to a native `<table>` that would change roles.)

- [ ] **Step 3: Run — expect pass (unchanged behavior)**

Run: `npx vitest run src/components/dashboard/__tests__/NeedsReviewTable.test.jsx`
Expected: PASS (all 4 tests: list, empty, paginate, tier block).

- [ ] **Step 4: Full suite guard**

Run: `npm test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/dashboard/NeedsReviewTable.jsx
git commit -m "feat(dashboard): NeedsReviewTable uses .card + reference tokens (behavior unchanged)"
```

---

## Task 6: DateRangeControl → `.btn-light` + `.dropdown-menu`

**Files:**
- Modify: `src/components/dashboard/DateRangeControl.jsx`
- Test: `src/components/dashboard/__tests__/DateRangeControl.test.jsx` (existing must stay green)

**Interfaces:**
- Produces: `<DateRangeControl value onChange />` + `rangeButtonLabel(value)` — unchanged behavior (open/close, presets, custom start/end inputs).

- [ ] **Step 1: Read the existing test to see what it asserts**

Run: `npx vitest run src/components/dashboard/__tests__/DateRangeControl.test.jsx`
Expected: PASS now. Keep the trigger button, option labels (`Today (Live)`, `Last 30 Days`, …), and the `Start`/`End` `aria-label` date inputs intact.

- [ ] **Step 2: Restyle keeping behavior.** Keep `OPTIONS`, `CalendarIcon`, `rangeButtonLabel`, the outside-click effect, `choose`, and the custom-range inputs. Swap styling:
  - Trigger `<button>` → `className="btn btn-light"`; caret svg → add `className="dropdown-caret"` and rotate via `style={{ transform: open ? 'rotate(180deg)' : '' }}`.
  - Menu `<div role="menu">` → `className="dropdown-menu animate-fade-up"`.
  - Each option `<button>` → `className="dropdown-item"`; mark the active one with an extra `is-active`-style via `style={{ background: active ? 'var(--ref-primary-50)' : undefined, color: active ? 'var(--ref-primary-600)' : undefined }}`.
  - Custom inputs: border `var(--ref-border)`, bg `var(--ref-surface-2)`, text `var(--ref-text)`.
  - Remove `useTokens`; delete the `c = isDark ? {...} : {...}` object.

- [ ] **Step 3: Run — expect pass**

Run: `npx vitest run src/components/dashboard/__tests__/DateRangeControl.test.jsx`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/components/dashboard/DateRangeControl.jsx
git commit -m "feat(dashboard): DateRangeControl uses .btn-light + .dropdown-menu"
```

---

## Task 7: DashboardPage → `.page-header`, `.badge-live`, cartoon states

**Files:**
- Modify: `src/pages/DashboardPage.jsx`
- Test: `src/pages/__tests__/DashboardPage.test.jsx` (create)

**Interfaces:**
- Consumes: restyled panels + `ThinkingCharacter` (`src/components/cockpit/ThinkingCharacter.jsx`, `<ThinkingCharacter label />`).
- Produces: same page; only the head + loading/empty visuals change.

- [ ] **Step 1: Write the failing test** (mock the data hooks so no API runs)

```jsx
// src/pages/__tests__/DashboardPage.test.jsx
import { describe, it, expect, vi } from 'vitest'
import { MemoryRouter } from 'react-router-dom'
import { renderWithProviders } from '../../test-utils/render.jsx'

vi.mock('../../api/assignments.js', () => ({ useAssignments: () => ({ data: { assignment_ids: [] }, isLoading: false, error: null }) }))
vi.mock('@tanstack/react-query', async (imp) => ({ ...(await imp()), useQueries: () => [] }))
vi.mock('../../api/dashboardHistory.js', () => ({ useDashboardRange: () => ({ data: null, isLoading: false, error: null }), postSnapshot: vi.fn() }))

import DashboardPage from '../DashboardPage.jsx'

describe('DashboardPage', () => {
  it('renders the reference page header with the title and a live badge', () => {
    const { container, getByText } = renderWithProviders(<MemoryRouter><DashboardPage /></MemoryRouter>)
    expect(getByText('Credentialing Intelligence')).toBeInTheDocument()
    expect(container.querySelector('.page-header')).not.toBeNull()
    expect(container.querySelector('.page-title')).not.toBeNull()
    expect(container.querySelector('.badge-live')).not.toBeNull()
  })
})
```

- [ ] **Step 2: Run — expect fail**

Run: `npx vitest run src/pages/__tests__/DashboardPage.test.jsx`
Expected: FAIL — no `.page-header`.

- [ ] **Step 3: Restyle the page.** Keep ALL query wiring (`useAssignments`, `useQueries` per `/review/{id}`, snapshot effect, live/history switch, `tierCounts`, `rangeButtonLabel`). Change only presentation:
  - Outer wrapper: keep `max-w-[1500px] mx-auto animate-fade-up`; set text color via `style={{ color: 'var(--ref-text)' }}`; remove `dashboardPalette`/`useTokens`.
  - Head block → `<div className="page-header">` with `<h1 className="page-title">Credentialing Intelligence</h1>` and the badge.
  - `HeadBadge` live branch → `<span className="badge-live"><span className="badge-live-dot" /><span className="badge-live-text">{anyLoading ? \`LOADING …\` : 'LIVE'}</span></span>`; history branch → `<span className="badge">{rangeText}</span>`.
  - Subtitle → `<p className="page-subtitle">…</p>` (same conditional text).
  - `DateRangeControl` unchanged.
  - Loading center box → render `<ThinkingCharacter label={\`Connecting to \${apiLabel}…\`} />` instead of the bare spinner.
  - Empty "all clear" (history empty and today-with-zero handled inside `NeedsReviewTable`) — for the today loading and history loading use `ThinkingCharacter`; keep `EmptyState` for error branches.

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/pages/__tests__/DashboardPage.test.jsx`
Expected: PASS.

- [ ] **Step 5: Full suite**

Run: `npm test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/pages/DashboardPage.jsx src/pages/__tests__/DashboardPage.test.jsx
git commit -m "feat(dashboard): page header + live badge + cartoon loading (reference)"
```

---

## Task 8: Sidebar → `.sidebar` + `.sidebar-link`

**Files:**
- Modify: `src/components/shell/Sidebar.jsx`
- Test: `src/components/shell/__tests__/Sidebar.test.jsx` (create)

**Interfaces:**
- Consumes: `useAuth`, `useConsoleMode`, reference classes. Produces the shell sidebar; behavior unchanged (collapse, nav switch, active link, logout, user card).

- [ ] **Step 1: Write the failing test** (mock providers)

```jsx
// src/components/shell/__tests__/Sidebar.test.jsx
import { describe, it, expect, vi } from 'vitest'
import { MemoryRouter } from 'react-router-dom'
import { renderWithProviders } from '../../../test-utils/render.jsx'

vi.mock('../../../console/ConsoleModeProvider.jsx', () => ({ useConsoleMode: () => ({ mode: 'test' }) }))
vi.mock('../../../auth/AuthProvider.jsx', () => ({ useAuth: () => ({ user: { email: 'paige.smith@aequor.com' }, logout: vi.fn() }) }))

import Sidebar from '../Sidebar.jsx'

describe('Sidebar', () => {
  it('renders nav links, the section label, and the user avatar', () => {
    const { container, getByText } = renderWithProviders(<MemoryRouter><Sidebar collapsed={false} /></MemoryRouter>)
    expect(getByText('Dashboard')).toBeInTheDocument()
    expect(getByText('Assignments')).toBeInTheDocument()
    expect(container.querySelector('.sidebar')).not.toBeNull()
    expect(container.querySelectorAll('.sidebar-link').length).toBeGreaterThanOrEqual(4)
    expect(container.querySelector('.avatar')?.textContent).toBe('PS')
  })
})
```

- [ ] **Step 2: Run — expect fail**

Run: `npx vitest run src/components/shell/__tests__/Sidebar.test.jsx`
Expected: FAIL.

- [ ] **Step 3: Restyle.** Keep `NAV_TEST`/`NAV_LIVE`, `personFromEmail`, the icon components, collapse behavior, `NavLink` active state, logout button, user card. Swap the `c = isDark ? {...}` object for classes:
  - `<aside>` → `className="sidebar"` with only `style={{ width: collapsed ? 72 : 256, transition: 'width .24s' }}`.
  - Brand block: keep logo; label text via `text-[color:var(--ref-heading)]`, sub via `.section-label`.
  - `NAVIGATION` label → `<div className="section-label">NAVIGATION</div>`.
  - Each `NavLink` → `className={({isActive}) => \`sidebar-link \${isActive ? 'is-active' : ''}\`}`; keep the active chevron; icon wrapper → `.nav-icon`. (Remove inline hover handlers — `.sidebar-link:hover` handles it.)
  - Footer logout → keep button; user card avatar → `<div className="avatar">{person.initials}</div>`, name via `text-[color:var(--ref-heading)]`, email via `text-[color:var(--ref-muted)]`.

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/components/shell/__tests__/Sidebar.test.jsx`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/shell/Sidebar.jsx src/components/shell/__tests__/Sidebar.test.jsx
git commit -m "feat(shell): Sidebar uses .sidebar + .sidebar-link reference classes"
```

---

## Task 9: TopBar → `.header` (theme toggle preserved)

**Files:**
- Modify: `src/components/shell/TopBar.jsx`
- Test: `src/components/shell/__tests__/TopBar.test.jsx` (create)

**Interfaces:**
- Consumes: `useTheme`, `useRunState`, `ModeSwitch`, reference classes. Produces the topbar; behavior unchanged (breadcrumb, mode switch, running pill, theme toggle, clock).

- [ ] **Step 1: Write the failing test** (mock providers)

```jsx
// src/components/shell/__tests__/TopBar.test.jsx
import { describe, it, expect, vi } from 'vitest'
import { MemoryRouter } from 'react-router-dom'
import { renderWithProviders } from '../../../test-utils/render.jsx'

const toggle = vi.fn()
vi.mock('../../../lib/theme.jsx', async (imp) => ({ ...(await imp()), useTheme: () => ({ isDark: false, toggle }) }))
vi.mock('../../../run/RunProvider.jsx', () => ({ useRunState: () => ({ status: 'idle', results: [], selectedIds: [] }) }))
vi.mock('../ModeSwitch.jsx', () => ({ default: () => null }))

import TopBar from '../TopBar.jsx'

describe('TopBar', () => {
  it('renders the reference header with breadcrumb and a working theme toggle', () => {
    const { container, getByText, getByTitle } = renderWithProviders(
      <MemoryRouter><TopBar onToggleSidebar={() => {}} title="Dashboard" /></MemoryRouter>,
    )
    expect(container.querySelector('.header')).not.toBeNull()
    expect(getByText('ACAP')).toBeInTheDocument()
    expect(getByText('Dashboard')).toBeInTheDocument()
    getByTitle('Dark mode').click()
    expect(toggle).toHaveBeenCalled()
  })
})
```

- [ ] **Step 2: Run — expect fail**

Run: `npx vitest run src/components/shell/__tests__/TopBar.test.jsx`
Expected: FAIL.

- [ ] **Step 3: Restyle.** Keep the `Clock`, hamburger, `ACAP` + breadcrumb chevron + `title`, `ModeSwitch`, running pill, and the two-button theme toggle (keep its `title={\`${opt.title} mode\`}` so `getByTitle('Dark mode')` works). Swap the `c = isDark ? {...}` object:
  - `<header>` → `className="header"` (drop inline bg/border/blur — the class handles it; keep `style` only for anything dynamic like the running-pill accent).
  - Breadcrumb `ACAP` → `text-[color:var(--ref-primary-600)] font-extrabold`; title → `text-[color:var(--ref-muted)]`.
  - Toggle + clock keep their structure; recolor via `--ref-*` vars.

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/components/shell/__tests__/TopBar.test.jsx`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/shell/TopBar.jsx src/components/shell/__tests__/TopBar.test.jsx
git commit -m "feat(shell): TopBar uses .header reference class (theme toggle preserved)"
```

---

## Task 10: AppShell backdrop + final verification

**Files:**
- Modify: `src/components/shell/AppShell.jsx`
- Test: full suite + build

**Interfaces:**
- Consumes: `.page-backdrop`. Produces: unchanged layout/scroll behavior.

- [ ] **Step 1: Restyle the backdrop.** Keep the flex layout, `NavProgress`, `Sidebar`, `TopBar`, `Suspense`/`Outlet`, scroll containers. Replace the two inline `isDark ? … : …` backdrop blocks with a single `<div className="page-backdrop" />` (theme-aware via the class). Remove `useTokens` if it becomes unused, or keep `t.bg` → replace root bg with `style={{ background: 'var(--ref-canvas)' }}`.

- [ ] **Step 2: Run the full suite**

Run: `npm test`
Expected: PASS (all files, including the pre-existing cockpit + dashboard tests).

- [ ] **Step 3: Production build**

Run: `npm run build`
Expected: succeeds; Tailwind compiles the reference layer.

- [ ] **Step 4: Manual visual pass (light + dark)**

Run: `npm run dev`, open `/`, toggle the theme. Confirm: page header + LIVE badge, five stat cards, tier bars grow in, needs-review table paginates and links to `/review/{id}`, flag badge + chevron present, cartoon shows during load, sidebar/topbar match the reference in both themes.

- [ ] **Step 5: Commit**

```bash
git add src/components/shell/AppShell.jsx
git commit -m "feat(shell): AppShell uses .page-backdrop; final reference-redesign pass"
```

---

## Self-Review (author checklist — completed)

- **Spec coverage:** token layer (T1), stat cards (T2/T3), tier bars (T4), needs-review table + pagination/flag/arrow (T5), date range (T6), page header + badge-live + cartoon (T7), sidebar (T8), topbar + theme toggle (T9), backdrop + final build/visual (T10). All spec sections mapped.
- **Placeholders:** none — every step has concrete CSS/JSX/test code or exact class-swap instructions.
- **Type/name consistency:** `StatCard` gains `variant` (T2) and every caller uses `variant` (T3); reference class names identical across tasks and match `reference.css` (T1); preserved copy strings match the existing tests (T5/T6).
- **No-API-in-tests:** T7 mocks `useAssignments`/`useQueries`/`useDashboardRange`; T8/T9 mock `useAuth`/`useConsoleMode`/`useTheme`/`useRunState`.
```
# Tracker Page Reference Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-skin `src/pages/TrackerPage.jsx` to the UI/UX reference (reusing the theme-aware `reference.css` layer + new grid/btn/badge classes), default-sort by latest pipeline run, and add a sync-banner cartoon + micro-interactions — with zero functionality change.

**Architecture:** New classes/tokens go into the shared `src/styles/reference.css`. A new presentational `TrackerSyncCartoon` reuses the ThinkingCharacter robot. `TrackerPage.jsx` is restyled to the reference `.card`/`.grid-table`/`.grid-footer` layout, given an initial `pipeline_ran_at desc` sort, and wired to the cartoon. The data layer (react-table, credTracker hooks, Lenis) is untouched.

**Tech Stack:** React 19, Tailwind v4.3 (`@theme` + `@layer components`), `@tanstack/react-table` v8, framer-motion, lucide-react, Vitest + `@testing-library/react`.

## Global Constraints

- **Presentational only.** Do NOT edit `src/api/credTracker.js`, `src/lib/credTracker.js`, `src/hooks/useLenisScroll.js`, or routing. All react-table sort/filter/paginate, inline edit, Review/Remove, and auto-sync-on-mount behavior is unchanged.
- **Preserve the existing test** `src/pages/__tests__/TrackerPage.test.jsx` (do NOT edit it; it must stay green): text `Onboarding Tracker` findable (kept as `.card-title` "ONBOARDING TRACKER"); action buttons keep `title` = `Edit`/`Save`/`Cancel`/`Review`/`Remove`; editable cells render inputs; sync fires on mount; candidate/recruiter text renders.
- **Theme-aware:** every new class resolves colors through `--ref-*` vars with BOTH `:root` and `[data-theme="dark"]` values. No hardcoded neutrals in component classes.
- **Reproduce reference class names:** `.badge-light .btn-outline-primary .btn-xs .btn-sm .btn-rounded-lg .grid-scroll .grid-table .grid-footer .grid-select .grid-sync-icon .text-heading-soft`, plus `--color-muted` token (so `text-muted` resolves).
- **Default sort:** `initialState.sorting = [{ id: 'pipeline_ran_at', desc: true }]`.
- **Tailwind only** for new styling; no new inline per-theme JS style objects beyond data-driven values.
- **No live API in tests.** Mock hooks. Verify with `npm test` (= `vitest run`) and `npm run build`.
- **Commit after each task** with the shown message.

---

## Task 1: New reference classes + tokens

**Files:**
- Modify: `src/styles/reference.css`
- Test: `src/styles/__tests__/referenceClasses.test.jsx` (extend the existing smoke test)

**Interfaces:**
- Produces the global classes Task 2/3 consume: `.badge-light`, `.btn-outline-primary`, `.btn-xs`, `.btn-sm`, `.btn-rounded-lg`, `.grid-scroll`, `.grid-table`, `.grid-footer`, `.grid-select`, `.grid-sync-icon`, `.text-heading-soft`; token `--color-muted`.

- [ ] **Step 1: Extend the smoke test (add assertions for the new classes)**

Append to `src/styles/__tests__/referenceClasses.test.jsx` a second test:

```jsx
it('renders the tracker grid/badge/btn reference classes without crashing', () => {
  const { container } = renderWithProviders(
    <div className="card">
      <div className="card-header"><span className="badge badge-light">48 tracked</span>
        <button className="btn btn-outline-primary btn-xs btn-rounded-lg">Sync</button></div>
      <div className="grid-scroll"><table className="grid-table"><tbody><tr><td>x</td></tr></tbody></table></div>
      <div className="grid-footer"><select className="grid-select"><option>10</option></select>
        <button className="btn btn-sm btn-rounded-lg">Next</button></div>
      <p className="text-heading-soft">sub</p>
    </div>,
  )
  expect(container.querySelector('.grid-table')).not.toBeNull()
  expect(container.querySelector('.badge-light')).not.toBeNull()
  expect(container.querySelector('.btn-outline-primary')).not.toBeNull()
  expect(container.querySelector('.grid-footer')).not.toBeNull()
})
```

- [ ] **Step 2: Run — expect fail (or trivially pass); then wire CSS**

Run: `npx vitest run src/styles/__tests__/referenceClasses.test.jsx`
(jsdom doesn't apply CSS, so the assertions check the classes are present on the elements — proceed to add the CSS so the classes are real in build.)

- [ ] **Step 3: Add tokens to `reference.css`.** In `:root` add `--ref-heading-soft: #5a6b82;` and in `[data-theme="dark"]` add `--ref-heading-soft: #93a6c4;`. In the `@theme` block add:

```css
  --color-muted: var(--ref-muted);
  --color-heading-soft: var(--ref-heading-soft);
```

Also add grid header/token vars — in `:root`:

```css
  --ref-grid-head-bg: #d4e1f5;
  --ref-grid-head-text: #0e3a6b;
  --ref-grid-head-rule: rgba(30,111,224,0.34);
  --ref-grid-row-hover: rgba(30,111,224,0.05);
```

and in `[data-theme="dark"]`:

```css
  --ref-grid-head-bg: #1a2742;
  --ref-grid-head-text: #d6e6ff;
  --ref-grid-head-rule: rgba(91,168,255,0.45);
  --ref-grid-row-hover: rgba(124,164,255,0.06);
```

- [ ] **Step 4: Add the component classes** inside the existing `@layer components { … }` block:

```css
  /* ── tracker grid + controls ── */
  .badge-light { color: var(--ref-muted); background: var(--ref-surface-2); border: 1px solid var(--ref-border); }
  .btn-xs { height: 30px; padding: 0 10px; font-size: 12px; }
  .btn-sm { height: 34px; padding: 0 12px; font-size: 12.5px; }
  .btn-rounded-lg { border-radius: 10px; }
  .btn-outline-primary { color: var(--ref-primary-600); background: transparent; border: 1px solid var(--ref-primary-600); }
  .btn-outline-primary:hover { background: var(--ref-primary-50); }

  .grid-scroll { flex: 1; min-height: 0; overflow: auto; }
  .grid-table { width: 100%; border-collapse: collapse; font-size: 12.5px; color: var(--ref-text); font-family: var(--font-jakarta); }
  .grid-table thead { position: sticky; top: 0; z-index: 10; }
  .grid-table thead .grid-head-row th {
    background: var(--ref-grid-head-bg); color: var(--ref-grid-head-text);
    text-align: left; padding: 8px 12px; font-size: 10.5px; font-weight: 700;
    letter-spacing: .06em; text-transform: uppercase; white-space: nowrap;
    border-bottom: 2px solid var(--ref-grid-head-rule); border-top: 1px solid var(--ref-grid-head-rule); }
  .grid-table thead .grid-filter-row th { background: var(--ref-grid-head-bg); padding: 0 12px 8px; }
  .grid-table tbody td { padding: 8px 12px; white-space: nowrap; vertical-align: middle; border-bottom: 1px solid var(--ref-divider); }
  .grid-table tbody tr { border-left: 2px solid transparent; transition: background .15s ease; }
  .grid-table tbody tr:hover { background: var(--ref-grid-row-hover); }

  .grid-footer { display: flex; align-items: center; justify-content: space-between; gap: 12px;
    padding: 10px 16px; border-top: 1px solid var(--ref-divider); }
  .grid-select { border-radius: 8px; padding: 4px 8px; font-size: 12px; color: var(--ref-text);
    background: var(--ref-surface); border: 1px solid var(--ref-border); }
  .grid-sync-icon { transition: transform .2s ease; }
  .grid-sync-icon.is-syncing { animation: spin .8s linear infinite; }

  .text-heading-soft { color: var(--ref-heading-soft); }
```

(`spin` keyframes already exist in `globals.css`.)

- [ ] **Step 5: Run the smoke test + build**

Run: `npx vitest run src/styles/__tests__/referenceClasses.test.jsx` → PASS.
Run: `npm run build` → succeeds (Tailwind compiles the new classes/tokens).
Run: `npm test` → still green.

- [ ] **Step 6: Commit**

```bash
git add src/styles/reference.css src/styles/__tests__/referenceClasses.test.jsx
git commit -m "feat(tracker): add grid/badge/btn reference classes + tokens"
```

---

## Task 2: `TrackerSyncCartoon` component

**Files:**
- Create: `src/components/tracker/TrackerSyncCartoon.jsx`
- Test: `src/components/tracker/__tests__/TrackerSyncCartoon.test.jsx`

**Interfaces:**
- Produces: `<TrackerSyncCartoon state="syncing|loading|empty" />` — a friendly robot cartoon + caption; `role="status"`. Reuses the visual language of `src/components/cockpit/ThinkingCharacter.jsx`.

- [ ] **Step 1: Write the failing test**

```jsx
// src/components/tracker/__tests__/TrackerSyncCartoon.test.jsx
import { describe, it, expect } from 'vitest'
import { screen } from '@testing-library/react'
import { renderWithProviders } from '../../../test-utils/render.jsx'
import TrackerSyncCartoon from '../TrackerSyncCartoon.jsx'

describe('TrackerSyncCartoon', () => {
  it('shows the syncing caption', () => {
    renderWithProviders(<TrackerSyncCartoon state="syncing" />)
    expect(screen.getByText(/syncing from bullhorn/i)).toBeInTheDocument()
    expect(screen.getByRole('status')).toBeInTheDocument()
  })
  it('shows an empty-state caption', () => {
    renderWithProviders(<TrackerSyncCartoon state="empty" />)
    expect(screen.getByText(/no tracked assignments|run a sync/i)).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run — expect fail**

Run: `npx vitest run src/components/tracker/__tests__/TrackerSyncCartoon.test.jsx`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement** (pure Tailwind + reference classes; inline SVG robot; no external assets)

```jsx
// src/components/tracker/TrackerSyncCartoon.jsx
const CAPTIONS = {
  syncing: 'Syncing from Bullhorn…',
  loading: 'Loading the tracker…',
  empty:   'No tracked assignments yet — run a sync.',
}

function Robot({ spin }) {
  return (
    <svg width="72" height="72" viewBox="0 0 104 104" fill="none" role="img" aria-label="tracker robot"
      className={spin ? 'animate-bounce [animation-duration:1.4s]' : 'animate-bounce [animation-duration:2.4s]'}>
      <line x1="52" y1="16" x2="52" y2="28" className="stroke-brand-sky" strokeWidth="3" strokeLinecap="round" />
      <circle cx="52" cy="12" r="5" className="fill-brand-sky animate-ping" />
      <circle cx="52" cy="12" r="4" className="fill-brand-sky" />
      <rect x="21" y="28" width="62" height="50" rx="16" className="fill-brand-bg-2 stroke-brand-sky" strokeWidth="2.5" />
      <circle cx="40" cy="50" r="6" className="fill-brand-sky animate-pulse" />
      <circle cx="64" cy="50" r="6" className="fill-brand-sky animate-pulse [animation-delay:250ms]" />
      <path d="M42 63 Q52 71 62 63" className="stroke-brand-sky" strokeWidth="3" strokeLinecap="round" fill="none" />
      <rect x="34" y="82" width="36" height="12" rx="6" className="fill-brand-bg-2 stroke-brand-sky" strokeWidth="2" />
    </svg>
  )
}

/** Friendly cartoon for the tracker's sync banner and loading/empty states. */
export default function TrackerSyncCartoon({ state = 'loading' }) {
  const compact = state === 'syncing'
  return (
    <div role="status" aria-live="polite"
      className={compact
        ? 'flex items-center gap-3 rounded-xl border border-[var(--border)] bg-brand-surface px-3 py-2'
        : 'flex flex-col items-center justify-center gap-3 rounded-2xl border border-[var(--border)] bg-brand-surface py-8'}>
      <Robot spin={compact} />
      <div className={compact ? 'text-[13px] font-bold text-brand-sky' : 'text-[14px] font-bold text-brand-sky animate-pulse tracking-wide'}>
        {CAPTIONS[state] ?? CAPTIONS.loading}
      </div>
    </div>
  )
}
```

- [ ] **Step 4: Run — expect pass**

Run: `npx vitest run src/components/tracker/__tests__/TrackerSyncCartoon.test.jsx`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/components/tracker/TrackerSyncCartoon.jsx src/components/tracker/__tests__/TrackerSyncCartoon.test.jsx
git commit -m "feat(tracker): TrackerSyncCartoon sync/loading/empty cartoon"
```

---

## Task 3: TrackerPage restyle + default sort + cartoon wiring

**Files:**
- Modify: `src/pages/TrackerPage.jsx`
- Test: `src/pages/__tests__/TrackerPage.sort.test.jsx` (create). Do NOT edit `TrackerPage.test.jsx`.

**Interfaces:**
- Consumes: reference classes (Task 1), `TrackerSyncCartoon` (Task 2), existing `useCredTracker`/`useSyncCredTracker`/`useUpdateCredRow`/`useDeleteCredRow`, `useLenisScroll`, `CRED_COLUMNS`/`EDITABLE_FIELDS`/`DATE_FIELDS`/`buildCredRow`.

**Preserve exactly** (existing test): `.card-title` renders `ONBOARDING TRACKER`; action buttons keep `title` `Edit`/`Save`/`Cancel`/`Review`/`Remove`; editable cells render inputs; sync fires on mount; candidate/recruiter text renders; Review → `navigate('/review/{id}')`; Remove → confirm→`remove.mutate(id)`; Save → `update.mutate({ id, fields, updated_by })` with only editable fields.

- [ ] **Step 1: Baseline — confirm the existing test is green**

Run: `npx vitest run src/pages/__tests__/TrackerPage.test.jsx`
Expected: PASS (5 tests) before edits.

- [ ] **Step 2: Restyle `TrackerPage.jsx`.** Keep the entire data/logic core — `useCredTracker`, the mount auto-sync effect, `rows`/`buildCredRow`, edit state (`editingId`/`draft`/`startEdit`/`cancelEdit`/`saveEdit`/`onRemove`), the `columns` memo (data cols + actions col, with the inline-edit inputs and the Review/Edit/Remove + Save/Cancel buttons and their `title`s), and the `useReactTable` call. Apply these presentation changes:

  - Add the default sort: initialize `const [sorting, setSorting] = useState([{ id: 'pipeline_ran_at', desc: true }])` (was `useState([])`). Leave `onSortingChange`/state wiring intact.
  - Root: replace the current wrapper with the reference `<main>` structure — a flex column with `px-4 py-5 sm:px-6`:
    - `<div className="page-header !mb-5">` → `<h1 className="page-title">Tracker</h1>` + `<span className="badge-live"><span className="badge-live-dot" /><span className="badge-live-text">LIVE</span></span>`, and a subtitle `<p className="text-heading-soft mt-2 text-sm font-medium">Onboarding progress across every tracked assignment — sort, filter and drill into each candidate. Synced from Bullhorn.</p>`.
    - `<section className="card flex min-h-0 flex-1 flex-col">`:
      - `.card-header` (flex, space-between): left = `<h2 className="card-title">ONBOARDING TRACKER</h2>` + `<span className="badge badge-light">{rows.length} tracked</span>`; right = Sync button `className="btn btn-outline-primary btn-xs btn-rounded-lg"`, `onClick={() => sync.mutate()}`, `disabled={sync.isPending}`, containing `<RefreshCw className={\`grid-sync-icon size-3 \${sync.isPending ? 'is-syncing' : ''}\`} />` and the label `{sync.isPending ? 'Syncing…' : 'Sync'}`.
      - Sync banner: when `sync.isPending`, render `<div className="px-4 pt-3"><TrackerSyncCartoon state="syncing" /></div>` above the grid.
      - `<div ref={scrollRef} className="grid-scroll" data-lenis-prevent>` wrapping `<table className="grid-table">`.
      - Header: render TWO `<tr>` in `<thead>` — a `className="grid-head-row"` row with the column label + sort icon (keep the `ArrowUp`/`ArrowDown`/`ArrowUpDown` logic and `getToggleSortingHandler`), and a `className="grid-filter-row"` row whose cells contain the existing filter `<input>` for filterable columns (empty `<th>` otherwise). Keep `flexRender` for headers.
      - Body: keep the framer-motion `AnimatePresence` rows, the skeleton loading rows, and the inline-edit rendering exactly; drop the per-row inline hover style handlers (the `.grid-table tbody tr:hover` CSS handles hover) but keep the editing left-bar accent (data-driven, inline `borderLeft` when editing is fine).
      - Empty state (`!isLoading && rows.length === 0`): a full-width `<td colSpan>` containing `<TrackerSyncCartoon state="empty" />`.
      - Loading with no rows: keep skeleton rows (they already exist) — optionally show `<TrackerSyncCartoon state="loading" />` above/inside; skeletons are sufficient, so keep them.
    - `.grid-footer` replaces the old pagination bar: left = `<span className="text-muted text-sm tabular-nums">{filtered} rows{…}</span>` + `<select className="grid-select">` with options `[10,25,50,100]`; right = Prev `btn btn-sm btn-rounded-lg`, page-info `1 / N`, Next `btn btn-sm btn-rounded-lg` (keep `table.previousPage()/nextPage()/getCanPreviousPage()/getCanNextPage()/setPageSize`).
  - Update `useReactTable` `initialState` to `{ sorting: [{ id: 'pipeline_ran_at', desc: true }], pagination: { pageSize: 25 } }` (the `sorting` state already carries the default; `initialState.sorting` is redundant if state is initialized — set the state default and leave pagination in initialState).
  - Remove `useTokens`/`headTokens` usage that the classes replace; keep `useTokens` only if still needed for edit-input/action-button data-driven colors (or tokenize them via `--ref-*`). Keep `PageBtn` only if reused; otherwise inline the footer buttons with `.btn` classes and delete `PageBtn`.
  - Keep the `isError` branch (restyle its text to `text-muted`).

- [ ] **Step 3: Verify the existing test still passes (unedited)**

Run: `npx vitest run src/pages/__tests__/TrackerPage.test.jsx`
Expected: PASS (5 tests) — `Onboarding Tracker` matches the card title, all `title`s and edit inputs intact.

- [ ] **Step 4: Write the default-sort test**

```jsx
// src/pages/__tests__/TrackerPage.sort.test.jsx
import { describe, it, expect, vi } from 'vitest'
import { screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { renderWithProviders } from '../../test-utils/render.jsx'

vi.mock('react-router-dom', async (o) => ({ ...(await o()), useNavigate: () => vi.fn() }))
vi.mock('../../hooks/useLenisScroll.js', () => ({ useLenisScroll: () => {} }))
vi.mock('../../api/credTracker.js', () => ({
  useCredTracker: () => ({ data: { rows: [
    { assignment_id: 1, candidate_name: 'Older Run', pipeline_ran_at: '2026-08-01 09:00' },
    { assignment_id: 2, candidate_name: 'Newest Run', pipeline_ran_at: '2026-08-04 09:00' },
  ] }, isLoading: false, isError: false }),
  useSyncCredTracker: () => ({ mutate: vi.fn(), isPending: false }),
  useUpdateCredRow: () => ({ mutate: vi.fn() }),
  useDeleteCredRow: () => ({ mutate: vi.fn() }),
}))

import TrackerPage from '../TrackerPage.jsx'

describe('TrackerPage default sort', () => {
  it('defaults to latest pipeline_ran_at first and renders reference markup', () => {
    const { container } = renderWithProviders(<MemoryRouter><TrackerPage /></MemoryRouter>)
    expect(container.querySelector('.card')).not.toBeNull()
    expect(container.querySelector('.grid-table')).not.toBeNull()
    expect(screen.getByRole('heading', { name: 'Tracker' })).toBeInTheDocument()
    const names = [...container.querySelectorAll('.grid-table tbody tr')]
      .map((tr) => tr.textContent)
    // Newest Run (2026-08-04) must appear before Older Run (2026-08-01)
    const newestIdx = names.findIndex((t) => t.includes('Newest Run'))
    const olderIdx = names.findIndex((t) => t.includes('Older Run'))
    expect(newestIdx).toBeGreaterThanOrEqual(0)
    expect(newestIdx).toBeLessThan(olderIdx)
  })
})
```

- [ ] **Step 5: Run — expect pass**

Run: `npx vitest run src/pages/__tests__/TrackerPage.sort.test.jsx`
Expected: PASS. (If the skeleton/loading branch hides rows, ensure `isLoading:false` path renders the two rows.)

- [ ] **Step 6: Full suite + build**

Run: `npm test` → all green (incl. the untouched `TrackerPage.test.jsx`).
Run: `npm run build` → succeeds.

- [ ] **Step 7: Commit**

```bash
git add src/pages/TrackerPage.jsx src/pages/__tests__/TrackerPage.sort.test.jsx
git commit -m "feat(tracker): reference redesign — grid card, default latest-run sort, sync cartoon"
```

---

## Self-Review (author checklist — completed)

- **Spec coverage:** new classes/tokens (T1), cartoon component (T2), page restyle + default sort + cartoon wiring + micro-interactions (T3). All spec sections mapped.
- **Placeholders:** none — concrete CSS, component code, and test code provided; T3 gives exact class-by-class restyle instructions against the known current file.
- **Type/name consistency:** `TrackerSyncCartoon` `state` prop values (`syncing`/`loading`/`empty`) consistent across T2/T3; class names identical to reference.css additions in T1; preserved `title`s + `.card-title` text match the existing test contract.
- **No-API-in-tests:** T2 renders the pure component; T3's sort test mocks all credTracker hooks + Lenis + navigate.
