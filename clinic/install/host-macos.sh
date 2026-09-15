#!/usr/bin/env bash
# macOS host layer: Homebrew, podman, the podman machine, DOCKER_HOST for
# docker-compose, and a LaunchAgent that starts the machine at login. What
# Sushil's initialize/01,02,03,11 do on main, minus dnsmasq and the privileged
# ports this stack does not need (8081/9443/9444). Rootless, as Ghated runs.
host_macos(){
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
    info "creating the podman machine (8 CPU, 12288 MiB, 120 GiB, rootless)"
    run podman machine init --cpus 8 --memory 12288 --disk-size 120
  else skip "podman machine exists"; fi
  if podman machine list --format '{{.Running}}' 2>/dev/null | grep -q true; then skip "podman machine running"; else run podman machine start; fi
  sock="$(podman_socket)"
  if ! grep -q 'DOCKER_HOST=' "${HOME}/.zprofile" 2>/dev/null; then
    run sh -c "printf 'export DOCKER_HOST=%s\n' '${sock}' >> '${HOME}/.zprofile'"
    ok "DOCKER_HOST persisted in ~/.zprofile"
  else skip "DOCKER_HOST already in ~/.zprofile"; fi
  export DOCKER_HOST="${sock}"
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
