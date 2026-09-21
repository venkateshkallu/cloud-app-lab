I’m giving you only the exact build and run commands that were used for the dummy app, in a clean step-by-step format.

## Step 1: Build the four images

```bash
docker build -t cockpit:dev -f ./Credentialing/cred_deploy/Dockerfile ./Credentialing/cred_deploy
docker build -t pipeline:dev -f ./Credentialing/cred_deploy/Dockerfile.pipeline ./Credentialing/cred_deploy
docker build -t excel-api:dev -f ./Credentialing/cred_fronted/excel-api/Dockerfile ./Credentialing/cred_fronted/excel-api
docker build -t frontend:dev -f ./Credentialing/cred_fronted/Dockerfile ./Credentialing/cred_fronted
```

## Step 2: Run the four containers

```bash
docker run -d --name cockpit -p 8004:8004 cockpit:dev
docker run -d --name pipeline -p 5001:5001 pipeline:dev
docker run -d --name excel-api -p 8002:8002 excel-api:dev
docker run -d --name frontend -p 80:80 frontend:dev
```

## Optional health checks

```bash
curl http://localhost:8004/health
curl http://localhost:5001/health
curl http://localhost:8002/health
curl http://localhost:80/health
```

Expected response for each:

```json
{"ok":true}
```

> These are the exact commands for the local dummy application build/run flow only, without extra explanation.