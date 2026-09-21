# Deployment & CI/CD — Test / Staging / Production
 
A beginner, step-by-step guide to deploying **this repo** (React frontend + `excel-api` Node
backend) to a **Windows EC2** behind `*.acap.aequor.com`, with GitHub Actions running the
pipeline. Do the phases **in order** the first time; after that, deploys are automatic on `git push`.
 
> The Python **cockpit/pipeline API** is a *different* repo (currently `52.9.132.43:8001`). This
> guide does **not** deploy it — the frontend just points at it via env vars.
 
---
 
## 0. The big picture (read once)
 
```
GitHub                                  AWS Windows EC2 (one box, RDP)
────────                                ─────────────────────────────────────────────
push develop ─► CI (lint/test/build) ─► self-hosted runner ─► build + copy + pm2 reload
push staging ─►        on PRs/pushes                          │
push main    ─►                                               ▼
                                        IIS (port 443, your SSL)            pm2 (Windows service)
                                        ├ acap.aequor.com         → /api ─► excel-api  :8002  (prod)
                                        ├ staging.acap.aequor.com → /api ─► excel-api  :8012  (staging)
                                        └ test.acap.aequor.com    → /api ─► excel-api  :8022  (test)
                                          each site root = that env's React build (dist)
```
 
- **Frontend** = static files (the `dist/` build). IIS serves them.
- **Backend** = `excel-api` Node process per env, managed by **pm2**, listening on an internal
  port. IIS reverse-proxies `https://<sub>.acap.aequor.com/api/*` → `http://localhost:<port>/*`.
- **One branch = one environment.** `develop`→test, `staging`→staging, `main`→production.
- **Secrets never live in git.** They live in **GitHub Environments** (used at build/deploy time)
  and in the per-env `.env` file the deploy writes onto the box.
 
> **Branch → URL → backend port**
>
> | Branch | Environment | URL | Node port |
> |---|---|---|---|
> | `develop` | test | test.acap.aequor.com | 8022 |
> | `staging` | staging | staging.acap.aequor.com | 8012 |
> | `main` | production | acap.aequor.com | 8002 |
 
---
 
## Phase 1 — Prepare the EC2 (one time)
 
RDP into the EC2 (you have the login/password). Open **PowerShell as Administrator** and install
the runtimes.
 
1. **Node.js 20 LTS** — download the Windows MSI from nodejs.org and install (or, if you have
   `winget`: `winget install OpenJS.NodeJS.LTS`). Verify:
   ```powershell
   node -v   # should print v20.x
   npm -v
   ```
2. **Git for Windows** — `winget install Git.Git` (the runner needs git).
3. **pm2** (process manager) + run it as a Windows **service** so apps survive reboots:
   ```powershell
   npm install -g pm2
   # Make pm2 a Windows service (resurrects saved apps on boot).
   # Recommended installer: https://github.com/jessety/pm2-installer
   #   git clone https://github.com/jessety/pm2-installer.git
   #   cd pm2-installer ; npm run configure ; npm run setup
   # (Alternative: 'npm i -g pm2-windows-startup' then 'pm2-startup install'.)
   ```
4. **IIS + URL Rewrite + Application Request Routing (ARR)** — IIS serves the static site and
   proxies `/api` to Node:
   - Enable IIS: **Server Manager → Add Roles and Features → Web Server (IIS)** (include *Static
     Content*, *Default Document*, *HTTP Errors*).
   - Install **URL Rewrite 2.1** and **ARR 3.0** (download from Microsoft's IIS site, or via Web
     Platform Installer).
   - Enable proxying once: **IIS Manager → server node → Application Request Routing Cache →
     Server Proxy Settings → tick "Enable proxy" → Apply.**
 
---
 
## Phase 2 — Create the three environments on the box (one time)
 
### 2a. Folders
 
```powershell
# Frontend (IIS site roots) and backend (pm2 app roots)
New-Item -ItemType Directory -Force C:\acap\prod\site,    C:\acap\prod\excel-api
New-Item -ItemType Directory -Force C:\acap\staging\site, C:\acap\staging\excel-api
New-Item -ItemType Directory -Force C:\acap\test\site,    C:\acap\test\excel-api
```
 
### 2b. First-time backend start (pm2)
 
The deploy workflow uses `pm2 reload`, which needs each app to exist first. Do a one-time
`pm2 start` per env (ports must match the table above). Run from each `excel-api` folder *after*
the first file copy — easiest is to do the **first deploy** (Phase 7) which copies the files, then
come back and run:
 
```powershell
cd C:\acap\prod\excel-api    ; $env:PORT=8002 ; pm2 start index.js --name excel-api-prod
cd C:\acap\staging\excel-api ; $env:PORT=8012 ; pm2 start index.js --name excel-api-staging
cd C:\acap\test\excel-api    ; $env:PORT=8022 ; pm2 start index.js --name excel-api-test
pm2 save   # remember these across reboots
```
 
(The real `PORT` comes from each env's `.env` that the deploy writes; pm2 reload picks it up.)
 
### 2c. IIS sites + reverse proxy
 
For **each** environment create an IIS **site** pointing at its `…\site` folder, with an HTTPS
binding for its hostname. In each site root put this **`web.config`** (it does SPA routing **and**
proxies `/api` to that env's Node port — change the port per env):
 
```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <!-- /api/* → the excel-api Node process for THIS environment -->
        <rule name="api-proxy" stopProcessing="true">
          <match url="^api/(.*)" />
          <action type="Rewrite" url="http://localhost:8002/{R:1}" />
        </rule>
        <!-- Everything else → index.html (React Router) -->
        <rule name="spa-fallback" stopProcessing="true">
          <match url=".*" />
          <conditions logicalGrouping="MatchAll">
            <add input="{REQUEST_FILENAME}" matchType="IsFile" negate="true" />
            <add input="{REQUEST_FILENAME}" matchType="IsDirectory" negate="true" />
          </conditions>
          <action type="Rewrite" url="/index.html" />
        </rule>
      </rules>
    </rewrite>
  </system.webServer>
</configuration>
```
 
> Use port **8002** for prod, **8012** staging, **8022** test.
>
> Because the frontend calls the backend through `/api` on the **same** origin, set each env's
> `VITE_EXCEL_API_BASE` to **`/api`** (see the secrets table). That avoids CORS entirely and means
> SSL "just works" for the API too.
 
---
 
## Phase 3 — DNS + SSL (one time)
 
1. **DNS:** in whoever hosts `aequor.com` DNS, add **A records** pointing at the EC2's **Elastic
   IP** (allocate one so it never changes):
   - `acap.aequor.com` → EC2 IP (you said this + SSL already exist ✅)
   - `staging.acap.aequor.com` → EC2 IP
   - `test.acap.aequor.com` → EC2 IP
2. **SSL:** you already have a cert for `acap.aequor.com`. For the two new subdomains either:
   - get a **wildcard** `*.acap.aequor.com` cert (simplest — one cert for all three), **or**
   - issue a cert per subdomain (e.g. **win-acme** / Let's Encrypt on Windows: <https://www.win-acme.com/>).
   Bind each cert to its IIS site (**Site → Bindings → https → choose certificate**).
 
---
 
## Phase 4 — Security group (one time)
 
In the EC2 **Security Group** (AWS console):
- **Allow inbound 443** (HTTPS) and **80** (HTTP→HTTPS redirect) from anywhere.
- **Allow 3389** (RDP) **only from your IP**.
- **Do NOT** open 8002/8012/8022 — the Node ports stay internal; only IIS talks to them.
 
---
 
## Phase 5 — Install the GitHub self-hosted runner (one time)
 
This is what lets GitHub Actions deploy onto the box without SSH.
 
1. GitHub repo → **Settings → Actions → Runners → New self-hosted runner → Windows**.
2. RDP into the EC2 and run the commands GitHub shows (download + `config.cmd`). When it asks for
   **labels**, add: `acap` (so it matches `runs-on: [self-hosted, windows, acap]`).
3. Install it as a **service** so it's always available:
   ```powershell
   # from the actions-runner folder, as Administrator
   .\svc.sh install   # (on Windows: .\svc install) — or use the "Install service" prompt in config
   .\svc start
   ```
   In the repo **Runners** page it should show **Idle / green**.
 
> One runner handles all three environments (jobs run one at a time per branch). That's fine to start.
 
---
 
## Phase 6 — Branches + GitHub Environments + secrets (one time)
 
### 6a. Branches
Create the two deploy branches off `main` (after PR #1 is merged):
```bash
git checkout main && git pull
git checkout -b staging && git push -u origin staging
git checkout -b develop && git push -u origin develop
```
 
### 6b. GitHub Environments
Repo → **Settings → Environments** → create **`test`**, **`staging`**, **`production`**.
- On **production**, turn on **"Required reviewers"** (so prod deploys wait for your approval).
 
### 6c. Per-environment **secrets** (Settings → Environments → <env> → Add secret)
 
| Secret | test | staging | production |
|---|---|---|---|
| `VITE_API_BASE` | cockpit URL for test | cockpit URL | `http://52.9.132.43:8001` (prod cockpit) |
| `VITE_PIPELINE_API_BASE` | pipeline URL (or blank — Live is disabled) | … | … |
| `VITE_EXCEL_API_BASE` | `/api` | `/api` | `/api` |
| `VITE_ALLOWED_EMAILS` | allowed emails | … | … |
| `VITE_CRED_TRACKER_TOKEN` | matches that env's `CRED_TRACKER_TOKEN` | … | … |
| `COCKPIT_API_BASE` | cockpit URL (server-side sync) | … | `http://52.9.132.43:8001` |
| `CRED_TRACKER_TOKEN` | a long random string (per env) | … | … |
| `CRED_TRACKER_ALLOWED_ORIGINS` | `https://test.acap.aequor.com` | `https://staging.acap.aequor.com` | `https://acap.aequor.com` |
| `DB_SERVER` | DB host | … | `192.168.7.26` |
| `DB_DATABASE` | **test DB** | **staging DB** | `AQ_COR_STG` |
| `DB_USER` / `DB_PASSWORD` / `DB_PORT` | DB creds | … | … |
 
### 6d. Per-environment **variables** (Settings → Environments → <env> → Add variable)
 
| Variable | test | staging | production |
|---|---|---|---|
| `SITE_ROOT` | `C:\acap\test\site` | `C:\acap\staging\site` | `C:\acap\prod\site` |
| `APP_ROOT` | `C:\acap\test\excel-api` | `C:\acap\staging\excel-api` | `C:\acap\prod\excel-api` |
| `PM2_APP` | `excel-api-test` | `excel-api-staging` | `excel-api-prod` |
| `EXCEL_API_PORT` | `8022` | `8012` | `8002` |
| `VITE_BASE_PATH` | `/` | `/` | `/` |
| `DB_ENCRYPT` | `true` | `true` | `true` |
| `DB_TRUST_CERT` | `true` | `true` | `true` |
 
> ⚠️ **Use a separate DB (or at least a separate `Cred_Tracker` schema/table) for test/staging.**
> They share the same `stg.Cred_Tracker` table today — test/staging deploys writing to the
> production DB would pollute real data. Point `DB_DATABASE` at non-prod for test/staging.
 
---
 
## Phase 7 — First deploy
 
1. Merge **PR #1** into `main` (this also adds these workflow files to `main`).
2. The first push to `main` triggers **Deploy → production**. Because pm2 has no app yet, that
   first run's `pm2 reload` will fail — so do the one-time `pm2 start` from **Phase 2b** now (the
   files were just copied by the deploy), then re-run the workflow (**Actions → failed run →
   Re-run jobs**). Subsequent deploys use `pm2 reload` and just work.
3. Repeat for `staging` and `develop` by pushing those branches.
4. **Verify:** open `https://acap.aequor.com` (frontend loads), and
   `https://acap.aequor.com/api/health` should return `{"ok":true,"db":"up"}`.
 
---
 
## Phase 8 — Day-to-day (after setup)
 
- **Ship to test:** `git push origin develop` → auto-deploys to test.acap.aequor.com.
- **Promote to staging:** merge `develop` → `staging` (PR) → auto-deploys to staging.
- **Release to production:** merge `staging` → `main` (PR) → waits for your approval → deploys to
  acap.aequor.com.
- **Every PR** runs CI (lint + tests + build) automatically — merge only when green.
- **Rollback:** `git revert` the bad commit and push (re-deploys the previous state), or on the box
  `pm2 list` / `pm2 logs excel-api-prod` to inspect, and restore the previous `dist` from a backup.
 
---
 
## Troubleshooting
 
| Symptom | Check |
|---|---|
| Deploy job stuck "Queued" | The self-hosted runner isn't online (Phase 5) or label mismatch (`acap`). |
| 502 on `/api/...` | The pm2 process is down (`pm2 list`, `pm2 logs <name>`) or the `web.config` port is wrong. |
| Frontend 404 on refresh of a route | `web.config` SPA-fallback rule missing in that site root. |
| `/api/health` shows `db:"down"` | DB secrets wrong, or `DB_TRUST_CERT` not `true` for the self-signed SQL cert. |
| CORS error in console | Set `VITE_EXCEL_API_BASE=/api` (same-origin) and `CRED_TRACKER_ALLOWED_ORIGINS` to that env's URL. |
| Prod deploy didn't wait for approval | Add "Required reviewers" to the `production` Environment (Phase 6b). |
 
---
 
*Files: `.github/workflows/ci.yml` (verify), `.github/workflows/deploy.yml` (deploy). App run/setup: `RUN.md`. Architecture: `architectur.md` §14.*
 
GitHub - jessety/pm2-installer: Install PM2 offline as a service on Windows or Linux. Mostly designed for Windows.
Install PM2 offline as a service on Windows or Linux. Mostly designed for Windows. - jessety/pm2-installer