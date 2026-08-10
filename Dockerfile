FROM nvidia/cuda:12.9.0-devel-ubuntu24.04

# Prevent interactive prompts during installation.
ENV DEBIAN_FRONTEND=noninteractive

# Set the timezone to UTC.
ENV TZ=UTC

# Install system dependencies.
RUN apt-get update && \
    apt-get install -y build-essential curl wget rsync ffmpeg && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create buildkite-agent user and group. The UID and GID are pinned because
# /var/lib/buildkite-agent is a bind mount whose contents on the host are owned
# by 995:995. Letting useradd -r pick a UID would silently break writes to the
# Julia depot and build directories if a rebuild ever assigned a different one.
RUN groupadd -r -g 995 buildkite-agent && \
    useradd -r -u 995 -g buildkite-agent -d /var/lib/buildkite-agent -s /bin/bash buildkite-agent && \
    mkdir -p /var/lib/buildkite-agent && \
    chown buildkite-agent:buildkite-agent /var/lib/buildkite-agent

# Install Buildkite agent
RUN curl -fsSL https://keys.openpgp.org/vks/v1/by-fingerprint/32A37959C2FA5C3C99EFBC32A79206696452D198 | gpg --dearmor -o /usr/share/keyrings/buildkite-agent-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/buildkite-agent-archive-keyring.gpg] https://apt.buildkite.com/buildkite-agent stable main" | tee /etc/apt/sources.list.d/buildkite-agent.list && \
    apt-get update && \
    apt-get install -y buildkite-agent && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /var/lib/buildkite-agent

# Install uv
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="/opt/uv" sh
ENV PATH="/opt/uv:$PATH"

# Remove CUDA library paths from LD_LIBRARY_PATH to let Julia's CUDA.jl
# use its own CUDA artifacts instead of system libraries (prevents warnings)
ENV LD_LIBRARY_PATH=""

# Install the agent config outside /var/lib/buildkite-agent: that path is a
# bind mount at runtime, which would mask anything copied into it here.
COPY --chown=buildkite-agent:buildkite-agent --chmod=644 buildkite-agent.cfg /etc/buildkite-agent/

# Switch to buildkite-agent user
USER buildkite-agent

# Install juliaup as buildkite-agent user and set PATH
RUN curl -fsSL https://install.julialang.org | sh -s -- --yes
ENV PATH="/var/lib/buildkite-agent/.juliaup/bin:$PATH"

ENTRYPOINT ["buildkite-agent", "start", "--config", "/etc/buildkite-agent/buildkite-agent.cfg"]
