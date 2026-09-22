#!/usr/bin/env bash
# macOS host layer: Homebrew, podman, the podman machine, DOCKER_HOST for
# docker-compose, and a LaunchAgent that starts the machine at login. What
# initialize/01,02,03,11 on main do, minus dnsmasq and the privileged
# ports this stack does not need (8081/9443/9444). Rootless, as Ghated runs.

# podman_machine_size HOST_MIB HOST_CPUS : sets MACHINE_MIB / MACHINE_CPUS for
# a NEW machine (never called to resize an existing one -- see host_macos
# below). memory = min(12288, 55% of host RAM), rounded DOWN to a multiple of
# 1024 -- Ghated's own machine (8 CPU/12288 MiB on a 24 GB host) is exactly
# this rule's ceiling. 55% is the rule Rawach's 18 GB needs: a 15 GB (83%) VM
# on an 18 GB Mac made macOS swap fill the disk, and the Virtualization
# framework killed the VM four times in one day. cpus = host cpus minus 2,
# capped at 8, floored at 2.
podman_machine_size(){
  local host_mib="$1" host_cpus="$2" mem cpus
  mem=$(( host_mib * 55 / 100 )); [ "$mem" -le 12288 ] || mem=12288
  mem=$(( (mem / 1024) * 1024 ))
  cpus=$(( host_cpus - 2 )); [ "$cpus" -le 8 ] || cpus=8; [ "$cpus" -ge 2 ] || cpus=2
  MACHINE_MIB="$mem"; MACHINE_CPUS="$cpus"
}

host_macos(){
  # Under DRY=1 nothing may reach the network, yet the Homebrew
  # `curl | bash` line evaluates its command substitution to build the
  # would-print string BEFORE run() ever gets called, so run()'s own DRY
  # check never got a chance) and still wrote to disk (`mkdir -p` for the
  # LaunchAgent ran unconditionally, outside run() entirely). Both bugs share
  # one root cause: run() only ever guards the exact command handed to it, so
  # anything upstream of that call -- a command substitution in its
  # arguments, or a plain statement never passed to run() at all -- still
  # executes for real. Fixed here by never reaching any of that code under
  # DRY: one guard at the top, nothing below it (brew, podman, mkdir,
  # launchctl) runs at all.
  if [ "${DRY}" = 1 ]; then
    info "would install Homebrew + podman/docker-compose/jq via brew, create/start a podman machine sized from host RAM, persist DOCKER_HOST in ~/.zprofile, and install the LaunchAgent that starts it at login"
    return 0
  fi
  if ! command -v brew >/dev/null 2>&1; then
    info "installing Homebrew (non-interactive)"
    run env NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  require_cmd brew
  for pkg in podman docker-compose jq; do
    if brew list --formula "$pkg" >/dev/null 2>&1; then skip "$pkg installed"; else run brew install "$pkg"; fi
  done
  if ! podman machine list --format '{{.Name}}' 2>/dev/null | grep -q .; then
    host_mib="${HOST_MIB:-$(( $(sysctl -n hw.memsize) / 1048576 ))}"
    host_cpus="${HOST_CPUS:-$(sysctl -n hw.ncpu)}"
    podman_machine_size "$host_mib" "$host_cpus"
    if [ "$MACHINE_MIB" -lt 10240 ]; then
      # the exact threshold, not a rounded guess: the smallest host RAM whose
      # 55% still rounds (down, to a multiple of 1024) to >= 10240 MiB.
      needed_mib=$(( (10240 * 100 + 54) / 55 ))
      fail "this Mac has ${host_mib} MiB RAM; 55% of it rounds down to ${MACHINE_MIB} MiB, below the 10 GiB (10240 MiB) a clinic's podman machine needs. This host needs at least ${needed_mib} MiB (~$(( (needed_mib + 1023) / 1024 )) GiB) of RAM for the installer to size a machine here"
    fi
    info "creating the podman machine (${MACHINE_CPUS} CPU, ${MACHINE_MIB} MiB, 120 GiB, rootless; 55% of ${host_mib} MiB host RAM, capped at 12288)"
    run podman machine init --cpus "${MACHINE_CPUS}" --memory "${MACHINE_MIB}" --disk-size 120
  else
    skip "podman machine exists"
    # never resized automatically -- a warning here, since preflight's own
    # macos-facts block already FAILs on this every run after the first.
    existing_mib="$(podman machine inspect --format '{{.Resources.Memory}}' 2>/dev/null || true)"
    if [ -n "${existing_mib:-}" ] && [ "$existing_mib" -lt 10240 ]; then
      warn "the existing podman machine has ${existing_mib} MiB, below the 10 GiB a clinic needs: podman machine set --memory 10240 (or more), then restart the machine"
    fi
  fi
  # podman_socket calls `podman machine inspect`, which does not exist to call
  # yet on a fresh host: DRY, or podman genuinely absent from PATH (brew
  # install above only ran for real outside DRY), both skip it rather than
  # crash with rc=127 on a Mac with no podman installed.
  if [ "${DRY}" = 1 ] || ! command -v podman >/dev/null 2>&1; then
    info "would start the podman machine and persist DOCKER_HOST in ~/.zprofile"
  else
    if podman machine list --format '{{.Running}}' 2>/dev/null | grep -q true; then skip "podman machine running"; else run podman machine start; fi
    sock="$(podman_socket)"
    if ! grep -q 'DOCKER_HOST=' "${HOME}/.zprofile" 2>/dev/null; then
      run sh -c "printf 'export DOCKER_HOST=%s\n' '${sock}' >> '${HOME}/.zprofile'"
      ok "DOCKER_HOST persisted in ~/.zprofile"
    else skip "DOCKER_HOST already in ~/.zprofile"; fi
    export DOCKER_HOST="${sock}"
  fi
  # LaunchAgent: start the machine at login, then the containers that carry a
  # restart policy (podman does not reattach them by itself on macOS).
  plist="${HOME}/Library/LaunchAgents/com.bahmni.clinic.start-at-login.plist"
  if [ ! -f "$plist" ]; then
    mkdir -p "${HOME}/Library/LaunchAgents"
    run sh -c "cat > '${plist}' <<EOF
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\"><dict>
  <key>Label</key><string>com.bahmni.clinic.start-at-login</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>${CLINIC_DIR}/podman/start-at-login.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>${HOME}/Library/Logs/bahmni-clinic-start.log</string>
  <key>StandardErrorPath</key><string>${HOME}/Library/Logs/bahmni-clinic-start.log</string>
</dict></plist>
EOF"
    run launchctl load "$plist"
    ok "LaunchAgent installed: ${plist}"
  else skip "LaunchAgent present"; fi
}
