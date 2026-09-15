#!/usr/bin/env bash
# Linux host layer (Ubuntu 22.04/24.04): packages, then Docker Engine + compose
# v2 (default) or podman + docker-compose (RUNTIME=podman). Sudo is used only
# here; every later task runs as the invoking user.
host_linux(){
  run sudo apt-get update -qq
  run sudo apt-get install -y -qq ca-certificates curl git jq python3 openssl gzip lsof
  if [ "$(detect_runtime)" = docker ]; then
    if command -v docker >/dev/null 2>&1; then skip "docker installed ($(docker --version | cut -d, -f1))"; else
      run sh -c 'curl -fsSL https://get.docker.com | sudo sh'
    fi
    if id -nG "$USER" | grep -qw docker; then skip "$USER in group docker"; else
      run sudo usermod -aG docker "$USER"
      warn "added $USER to group docker -- log out and in (or run: newgrp docker) before continuing"
    fi
    docker compose version >/dev/null 2>&1 || fail "docker compose v2 plugin missing (get.docker.com installs it; check the docker-compose-plugin package)"
  else
    if command -v podman >/dev/null 2>&1; then skip "podman installed"; else run sudo apt-get install -y -qq podman; fi
    command -v docker-compose >/dev/null 2>&1 || run sudo apt-get install -y -qq docker-compose
    run systemctl --user enable --now podman.socket
    export DOCKER_HOST="$(podman_socket)"
    grep -q 'DOCKER_HOST=' "${HOME}/.profile" 2>/dev/null || run sh -c "printf 'export DOCKER_HOST=%s\n' '${DOCKER_HOST}' >> '${HOME}/.profile'"
  fi
}
