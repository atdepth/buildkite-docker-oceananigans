# Buildkite Julia GPU Agent

A Docker container that runs [Buildkite](https://buildkite.com) agents with Julia and GPU/CUDA
support. It provides an isolated environment for CI/CD pipelines that need GPU acceleration, and is
used to run the Oceananigans.jl pipeline on a self-hosted GPU machine.

## Prerequisites

- [Docker](https://docs.docker.com/engine/install/debian/), which ships with Docker Compose
- The [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
- A Buildkite agent token, from your organization's **Agents** page

## Setup

### 1. Create `.env`

Every secret lives in `.env`, which is git-ignored and must never be committed. Start from the
template:

```bash
cp .env.stub .env
```

Then fill in:

| Variable | Description |
| --- | --- |
| `BUILDKITE_AGENT_TOKEN` | Agent token from your Buildkite organization's **Agents** page. |
| `DOCUMENTER_KEY` | Base64-encoded SSH private key that [Documenter.jl](https://documenter.juliadocs.org/stable/man/hosting/) uses to push built documentation to the `gh-pages` branch. Only needed if the pipeline deploys docs. |

To generate a `DOCUMENTER_KEY`, run this in Julia:

```julia
using DocumenterTools
DocumenterTools.genkeys(user="<org>", repo="<repo>.jl")
```

Add the printed public key to the repository as a deploy key **with write access**, and paste the
printed base64 private key into `.env`.

### 2. Review the agent configuration

Non-secret agent settings live in `buildkite-agent.cfg`, which is committed and copied into the
image at `/etc/buildkite-agent/buildkite-agent.cfg`:

- `name` — the agent name shown in the Buildkite UI (`%spawn` is replaced by the agent's index)
- `spawn` — how many agents the single container runs in parallel
- `tags` — the queue this agent serves, matched by `agents: queue: ...` in your pipeline steps

The file also lists every other agent option, commented out, as a reference.

### 3. Start the container

```bash
docker compose up --build --detach
```

### 4. Watch the logs

```bash
docker compose logs --follow
```

The agents should show up on your Buildkite **Agents** page within a few seconds.

## Configuration

| What | Where |
| --- | --- |
| GPU selection | `device_ids` under `deploy.resources.reservations.devices` in `docker-compose.yaml` |
| CPU and memory limits | `deploy.resources.limits` in `docker-compose.yaml` |
| Shared memory | `shm_size` in `docker-compose.yaml` |
| Build and scratch storage | the host paths under `volumes` in `docker-compose.yaml` |
| CUDA version | the `nvidia/cuda` base image tag in `Dockerfile` |
| Julia version | juliaup installs the current stable release in `Dockerfile`; pin a version with `juliaup add` and `juliaup default` |
| Agent name, queue, and count | `buildkite-agent.cfg` |

Two host directories are bind-mounted into the container:

- `/var/lib/buildkite-agent` — agent state, checked-out builds, and the Julia depot, so installed
  packages and compilation caches survive restarts
- `/tmp` — scratch space for jobs, kept off the container's writable layer

Because the bind mount masks everything the image ships under `/var/lib/buildkite-agent`, the agent
config is installed at `/etc/buildkite-agent/buildkite-agent.cfg` instead. Copying it into
`/var/lib/buildkite-agent` would leave it hidden at runtime, and the agent would silently read a
stale file from the host directory instead.

The `Dockerfile` clears `LD_LIBRARY_PATH` on purpose, so that CUDA.jl uses its own CUDA artifacts
instead of the system libraries from the base image.

## Common tasks

Rebuild and restart after changing the `Dockerfile` or `buildkite-agent.cfg`:

```bash
docker compose up --build --detach --timeout 3600
```

Recreating the container stops every agent it runs. `buildkite-agent` treats `SIGTERM` as a graceful
disconnect and finishes its current job first, but Docker's default stop timeout is only 10 seconds,
after which the job is killed mid-run. The `--timeout` above gives in-flight jobs an hour to finish;
alternatively, pause the queue in the Buildkite UI and wait for the agents to go idle before
deploying.

Stop the agents:

```bash
docker compose down --timeout 3600
```

Open a shell inside the running container:

```bash
docker compose exec buildkite-oceananigans bash
```

## Secrets

- `.env` holds every secret. It is listed in `.gitignore` and `.dockerignore`, so it is neither
  committed nor sent to the Docker daemon as build context.
- `.env.stub` is the committed template and must only ever contain empty values.
- `buildkite-agent.cfg` **is** committed and is baked into the image, so never put a token in it.
  The agent reads its token from `BUILDKITE_AGENT_TOKEN` instead.

