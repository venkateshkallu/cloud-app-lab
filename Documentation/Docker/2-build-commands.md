I’m updating the commands to match your current folder layout and the exact paths you’re using in this workspace.

Read [](file:///home/dell/clients/kalpana/credentialing)

## Step 1: Build the four images

```bash
docker build -t cockpit:dev -f ./cred_deploy/Dockerfile ./cred_deploy
docker build -t pipeline:dev -f ./cred_deploy/Dockerfile.pipeline ./cred_deploy
docker build -t excel-api:dev -f ./cred_fronted/excel-api/Dockerfile ./cred_fronted/excel-api
docker build -t frontend:dev -f ./cred_fronted/Dockerfile ./cred_fronted
```

## Step 2: Run the four containers

```bash
docker run -d --name cockpit -p 8004:8004 cockpit:dev
docker run -d --name pipeline -p 5001:5001 pipeline:dev
docker run -d --name excel-api -p 8002:8002 excel-api:dev
docker run -d --name frontend -p 80:80 frontend:dev
```

## Step 3: Health checks

```bash
curl http://localhost:8004/health
curl http://localhost:5001/health
curl http://localhost:8002/health
curl http://localhost:80/health
```

Expected result for each:

```json
{"ok":true}
```

These are the updated commands based on your current folder structure.