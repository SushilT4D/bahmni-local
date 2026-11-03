#!/usr/bin/env bash
# RESTART_POLICY=always, LaunchAgent, and (FileVault) system LaunchDaemon.
# Folds former podman/initialize.sh + podman/install-boot-daemon.sh.
set -euo pipefail
INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${INIT_DIR}/lib.sh"
parse_task_args "$@"
begin_task "11 · Restart policy + Podman autostart"

ensure_path_has_brew
require_cmd podman

start_script="${PROJECT_DIR}/podman/start-at-login.sh"
[[ -f "${start_script}" ]] || fail "Missing ${start_script}"
chmod +x "${start_script}"

# --- .env RESTART_POLICY ---
if [[ -f "${ENV_FILE}" ]]; then
  if grep -qE '^RESTART_POLICY=always' "${ENV_FILE}" && [[ "${FORCE}" != true ]]; then
    ok "RESTART_POLICY=always already set"
  elif grep -qE '^RESTART_POLICY=always' "${ENV_FILE}"; then
    ok "RESTART_POLICY=always already set"
  elif grep -qE '^RESTART_POLICY=' "${ENV_FILE}"; then
    info "Updating RESTART_POLICY to always…"
    sed -i.bak 's/^RESTART_POLICY=.*/RESTART_POLICY=always/' "${ENV_FILE}"
    ok "RESTART_POLICY set to always (backup: ${ENV_FILE}.bak)"
  else
    info "Appending RESTART_POLICY=always…"
    printf '\nRESTART_POLICY=always\n' >> "${ENV_FILE}"
    ok "RESTART_POLICY=always appended"
  fi
else
  warn ".env missing — set RESTART_POLICY=always before compose"
fi

# --- LaunchAgent (gui login) ---
podman_bin="$(command -v podman)"
[[ -x "${podman_bin}" ]] || fail "podman binary not found"
launch_agents="${HOME}/Library/LaunchAgents"
agent_plist="${launch_agents}/com.podman.machine.plist"
agent_label="com.podman.machine"
uid="$(id -u)"

agent_ok=false
if [[ -f "${agent_plist}" ]] && grep -Fq "${start_script}" "${agent_plist}"; then
  agent_ok=true
fi

if [[ "${agent_ok}" == true && "${FORCE}" != true ]]; then
  skip "LaunchAgent ${agent_label} already points at start-at-login.sh"
else
  info "Installing LaunchAgent ${agent_label}…"
  mkdir -p "${launch_agents}"
  cat > "${agent_plist}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key><string>${agent_label}</string>
    <key>ProgramArguments</key>
    <array>
      <string>/bin/bash</string>
      <string>${start_script}</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
    <key>StandardOutPath</key><string>/tmp/podman-machine.out</string>
    <key>StandardErrorPath</key><string>/tmp/podman-machine.err</string>
  </dict>
</plist>
PLIST
  launchctl bootout "gui/${uid}/${agent_label}" 2>/dev/null || true
  if ! launchctl bootstrap "gui/${uid}" "${agent_plist}" 2>/dev/null; then
    launchctl unload "${agent_plist}" 2>/dev/null || true
    launchctl load "${agent_plist}" 2>/dev/null || true
  fi
  launchctl enable "gui/${uid}/${agent_label}" 2>/dev/null || true
  launchctl kickstart -k "gui/${uid}/${agent_label}" 2>/dev/null || true
  ok "LaunchAgent ${agent_label} → ${start_script}"
  dim "Logs: /tmp/podman-machine.out · /tmp/podman-machine.err"
fi

# --- LaunchDaemon (boot / FileVault — no Automatic Login) ---
daemon_label="com.bahmni.podman"
daemon_plist="/Library/LaunchDaemons/${daemon_label}.plist"
run_user="$(id -un)"
run_group="$(id -gn)"
log_dir="${HOME}/Library/Logs"
out_log="${log_dir}/bahmni-podman.out"
err_log="${log_dir}/bahmni-podman.err"
mkdir -p "${log_dir}"

daemon_ok=false
if [[ -f "${daemon_plist}" ]] && sudo grep -Fq "${start_script}" "${daemon_plist}" 2>/dev/null; then
  daemon_ok=true
fi

if [[ "${daemon_ok}" == true && "${FORCE}" != true ]]; then
  skip "LaunchDaemon ${daemon_label} already installed"
else
  info "Installing system LaunchDaemon ${daemon_label} (sudo; for FileVault / no auto-login)…"
  tmp="$(mktemp)"
  cat > "${tmp}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key><string>${daemon_label}</string>
    <key>UserName</key><string>${run_user}</string>
    <key>GroupName</key><string>${run_group}</string>
    <key>ProgramArguments</key>
    <array>
      <string>/bin/bash</string>
      <string>${start_script}</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
    <key>StandardOutPath</key><string>${out_log}</string>
    <key>StandardErrorPath</key><string>${err_log}</string>
    <key>EnvironmentVariables</key>
    <dict>
      <key>HOME</key><string>${HOME}</string>
      <key>USER</key><string>${run_user}</string>
      <key>LOGNAME</key><string>${run_user}</string>
      <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
  </dict>
</plist>
PLIST
  sudo cp "${tmp}" "${daemon_plist}"
  sudo chown root:wheel "${daemon_plist}"
  sudo chmod 644 "${daemon_plist}"
  rm -f "${tmp}"
  sudo launchctl bootout "system/${daemon_label}" 2>/dev/null || true
  sudo launchctl bootstrap system "${daemon_plist}"
  sudo launchctl enable "system/${daemon_label}" 2>/dev/null || true
  ok "LaunchDaemon ${daemon_label} installed"
  dim "Logs: ${out_log}"
fi

# Start machine + containers once now (safe if already up)
info "Starting Podman machine + restart-policy containers now…"
/bin/bash "${start_script}" || "${podman_bin}" machine start || true
ok "autostart configured"
dim "FileVault: unlock disk at power-on; LaunchDaemon starts Podman without GUI login"
