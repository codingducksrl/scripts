#!/bin/sh

printf "Project name: "
read -r projectName

# Install and configure Nx
yarn global add nx
npx create-nx-workspace "$projectName" \
  --interactive=false \
  --workspaceType=integrated \
  --preset=empty \
  --skipGit=true \
  --pm=yarn \
  --nxCloud=false

cd "$projectName" || exit 1

# Install React
yarn add -D @nx/react
npx nx g @nx/react:app frontend \
  --unitTestRunner jest \
  --strict true \
  --e2eTestRunner none \
  --bundler vite \
  --globalCss true \
  --routing true \
  --style css

npx nx g @nx/react:lib ui \
  --unitTestRunner=jest \
  --bundler=vite \
  --globalCss=true \
  --style=css \
  --strict true

# Configure Tailwind
npx nx g @nx/react:setup-tailwind --project=frontend
npx nx g @nx/react:setup-tailwind --project=ui

# Install Storybook
npx nx g @nx/react:storybook-configuration ui \
  --generateStories=true \
  --generateCypressSpecs=false \
  --interactionTests=false \
  --configureStaticServe=false

cat << EOF > libs/ui/.storybook/tailwind-imports.css
@tailwind base;
@tailwind components;
@tailwind utilities;
EOF

echo "import './tailwind-imports.css';" >> libs/ui/.storybook/preview.ts

# Install NestJS
yarn add -D @nx/nest
npx nx g @nx/nest:app backend \
  --frontendProject frontend \
  --unitTestRunner jest \
  --strict true \
  --e2eTestRunner none



yarn add -D @nx-tools/nx-prisma

npx nx g @nx/nest:lib db --unitTestRunner=none
npx nx g @nx-tools/nx-prisma:init db

cat << EOF > docker-compose.yaml
version: '3'
services:
  mariadb:
    image: 'mariadb:10'
    ports:
      - '${FORWARD_DB_PORT:-3306}:3306'
    environment:
      MYSQL_ROOT_PASSWORD: '\${DB_PASSWORD}'
      MYSQL_ROOT_HOST: '%'
      MYSQL_DATABASE: '\${DB_DATABASE}'
      MYSQL_USER: '\${DB_USERNAME}'
      MYSQL_PASSWORD: '\${DB_PASSWORD}'
      MYSQL_ALLOW_EMPTY_PASSWORD: 'yes'
    volumes:
      - 'nest-mariadb:/var/lib/mysql'
      - './docker/create-testing-database.sh:/docker-entrypoint-initdb.d/10-create-testing-database.sh'
    networks:
      - nest
    healthcheck:
      test:
        - CMD
        - mysqladmin
        - ping
        - '-p${DB_PASSWORD}'
      retries: 3
      timeout: 5s
  redis:
    image: 'redis:alpine'
    ports:
      - '\${FORWARD_REDIS_PORT:-6379}:6379'
    volumes:
      - 'nest-redis:/data'
    networks:
      - nest
    healthcheck:
      test:
        - CMD
        - redis-cli
        - ping
      retries: 3
      timeout: 5s
  mailpit:
    image: 'axllent/mailpit:latest'
    ports:
      - '\${FORWARD_MAILPIT_PORT:-1025}:1025'
      - '\${FORWARD_MAILPIT_DASHBOARD_PORT:-8025}:8025'
    networks:
      - nest

networks:
  nest:
    driver: bridge
volumes:
  nest-mariadb:
    driver: local
  nest-redis:
    driver: local

EOF

mkdir -p docker

cat << EOF > docker/create-testing-database.sh
#!/usr/bin/env bash

mysql --user=root --password="$MYSQL_ROOT_PASSWORD" <<-EOSQL
    CREATE DATABASE IF NOT EXISTS testing;
    GRANT ALL PRIVILEGES ON \`testing%\`.* TO '$MYSQL_USER'@'%';
EOSQL
EOF

cat << EOF > .env
DB_USERNAME=nestjs
DB_PASSWORD=nestjs
DB_DATABASE=nestjs
DB_HOST=localhost
EOF

echo ".env" >> .gitignore

cp .env .env.example

mkdir -p libs/ui/src/atoms
mkdir -p libs/ui/src/molecules
mkdir -p libs/ui/src/organisms
mkdir -p libs/ui/src/templates

touch libs/ui/src/atoms/.gitkeep
touch libs/ui/src/molecules/.gitkeep
touch libs/ui/src/organisms/.gitkeep
touch libs/ui/src/templates/.gitkeep

mkdir -p .github/workflows

cat << EOF > .github/workflows/check.yml
name: 'Check project'

on:
  pull_request:
    branches:
      - staging
      - main

permissions:
  contents: read
  pull-requests: read

concurrency:
  group: '\${{ github.workflow }} @ \${{ github.event.pull_request.head.label || github.head_ref || github.ref }}'
  cancel-in-progress: true

jobs:
  check-build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: 18
          cache: 'yarn'
      - name: Install dependencies 📦
        run: yarn install
      - name: Link check 🗒️
        run: npx nx run-many -t lint
      - name: Running tests 🧪
        run: npx nx run-many -t test
      - name: Testing production build 🏗️
        run: npx nx run-many -t build
EOF

cat << EOF > README.md
## Prerequisites
Install the yarn dependencies
\`\`\`
yarn install
\`\`\`

## Development

### Directory structure
\`\`\`
├── apps
│   ├── backend
│   └── frontend
├── libs
│   ├── ui
│   │   ├── src
│   │   │   ├── atoms
│   │   │   ├── molecules
│   │   │   ├── organisms
│   │   │   ├── templates
│   │   │   ├── index.ts
│   ├── db
├──.env
├──.env.example
├──docker-compose.yml
├──dist
\`\`\`
The apps directory contains the frontend and the backend applications.

The libs directory contains the modules used by the frontend and/or the backend.

By default, there are two modules: **ui** and **db**.
* **ui**: contains the components used by the frontend. It is a library of reusable components.
  It must follow the atomic design principles.
* **db**: contains the prisma schema and the generated prisma client used by the backend.

> **Important**
> In a library, a component, to be used outside the library, must be exported in the index.ts file.

### Start the development servers
In order to start both the backend and the frontend, run the following command:
\`\`\`
nx run-many -t serve
\`\`\`
If you want to start the backend and the frontend separately, you can run the following commands:
\`\`\`
nx serve backend
nx serve frontend
\`\`\`
The frontend will be available at http://localhost:4200/ and the backend at http://localhost:3000/api,
however, the frontend will proxy all requests to the backend, so you can use http://localhost:4200/api to access the backend.

In order to start the database servers, run the following command:
\`\`\`
docker compose up
\`\`\`
It will start the following servers:
* mariadb
  * Host: localhost
  * Port: 3306
  * User: {FROM .env}
  * Password: {FROM .env}
  * Database: {FROM .env}
* redis
  * Host: localhost
  * Port: 6379
* mailpit
  * Host: localhost
  * Port: 1025

### Start storybook
\`\`\`
nx serve ui:storybook
\`\`\`

### Linting
\`\`\`
nx run-many -t lint
\`\`\`

### Testing
\`\`\`
nx run-many -t test
\`\`\`

## Production
To build the project run:
\`\`\`
nx run-many -t build
\`\`\`
The build artifacts will be stored in the \`dist/\` directory, ready to be deployed.
 \\

 \\
<a alt="Nx logo" href="https://nx.dev" target="_blank" rel="noreferrer"><img src="https://raw.githubusercontent.com/nrwl/nx/master/images/nx-logo.png" width="45"></a>

✨ **This workspace has been generated by [Nx, a Smart, fast and extensible build system.](https://nx.dev)** ✨


## Generate code

If you happen to use Nx plugins, you can leverage code generators that might come with it.

Run \`nx list\` to get a list of available plugins and whether they have generators. Then run \`nx list <plugin-name>\` to see what generators are available.

Learn more about [Nx generators on the docs](https://nx.dev/plugin-features/use-code-generators).

## Running tasks

To execute tasks with Nx use the following syntax:

\`\`\`
nx <target> <project> <...options>
\`\`\`

You can also run multiple targets:

\`\`\`
nx run-many -t <target1> <target2>
\`\`\`

..or add \`-p\` to filter specific projects

\`\`\`
nx run-many -t <target1> <target2> -p <proj1> <proj2>
\`\`\`

Targets can be defined in the \`package.json\` or \`projects.json\`. Learn more [in the docs](https://nx.dev/core-features/run-tasks).
EOF