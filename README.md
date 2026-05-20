# foodcoops-infra

Infrastructure setup for the Food-Coop application.

This repository contains the Docker Compose setup and shared configuration needed to run the Food-Coop application locally. It connects the backend, frontend, Keycloak and MariaDB so developers do not have to start and configure each service manually.

## Services

The local setup includes:

- Food-Coop Backend
- Food-Coop Frontend
- Keycloak for authentication
- MariaDB as database

## Repository structure

Recommended local folder structure:

```text
Food-Coop/
  foodcoops-infra/
  foodcoops-backend/
  foodcoops-frontend/
```

The Docker Compose file assumes that the backend and frontend repositories are checked out next to this repository. If your folder structure is different, adjust the paths in `compose.yaml`.

## Configuration

Environment-specific values should be placed in a local `.env` file.

```bash
cp .env.example .env
```

The `.env` file must not be committed to Git. Copy `.env.example` and fill out all required configuration values.

## Getting started

Start the full local environment:

```bash
docker compose up --build
```

Stop the environment:

```bash
docker compose down
```

Stop the environment and remove local volumes:

```bash
docker compose down -v
```
