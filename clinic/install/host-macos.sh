#!/usr/bin/env bash
# Prepares the Mac: Homebrew, podman and its machine, podman-compose, the boot-time LaunchDaemon, dnsmasq, ports 80/443.

# Boot-time LaunchDaemon running podman/start-at-login.sh, which stays up and stops the stack on SIGTERM.
# AbandonProcessGroup false + ExitTimeOut 300: launchd waits for that shutdown.
DAEMON_LABEL=com.bahmni.podman
DAEMON_PLIST="${DAEMON_PLIST:-/Library/LaunchDaemons/${DAEMON_LABEL}.plist}"
OLD_AGENT_PLIST="${HOME}/Library/LaunchAgents/com.bahmni.clinic.start-at-login.plist"   # older installs

daemon_plist(){ # : in plutil's layout, so an installed copy compares equal
  local u g; u="$(id -un)"; g="$(id -gn)"
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AbandonProcessGroup</key>
	<false/>
	<key>EnvironmentVariables</key>
	<dict>
		<key>HOME</key>
		<string>${HOME}</string>
		<key>LOGNAME</key>
		<string>${u}</string>
		<key>PATH</key>
		<string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
		<key>USER</key>
		<string>${u}</string>
	</dict>
	<key>ExitTimeOut</key>
	<integer>300</integer>
	<key>GroupName</key>
	<string>${g}</string>
	<key>KeepAlive</key>
	<false/>
	<key>Label</key>
	<string>${DAEMON_LABEL}</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>${CLINIC_DIR}/podman/start-at-login.sh</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>StandardErrorPath</key>
	<string>${HOME}/Library/Logs/bahmni-podman.err</string>
	<key>StandardOutPath</key>
	<string>${HOME}/Library/Logs/bahmni-podman.out</string>
	<key>UserName</key>
	<string>${u}</string>
</dict>
</plist>
EOF
}

daemon_pending(){ # : why the plist needs a root write; nothing when current
  [ -f "${DAEMON_PLIST}" ] || { printf 'LaunchDaemon %s install' "${DAEMON_LABEL}"; return 0; }
  [ "$(daemon_plist)" = "$(cat "${DAEMON_PLIST}" 2>/dev/null)" ] || printf 'LaunchDaemon %s update' "${DAEMON_LABEL}"
}

daemon_loaded(){ launchctl print "system/${DAEMON_LABEL}" >/dev/null 2>&1; }

daemon_install(){
  local why tmp
  if [ -f "${OLD_AGENT_PLIST}" ]; then
    launchctl unload "${OLD_AGENT_PLIST}" 2>/dev/null || true   # its job has exited; the machine stays up
    rm -f "${OLD_AGENT_PLIST}"
    ok "old LaunchAgent removed (${OLD_AGENT_PLIST}): the LaunchDaemon replaces it"
  fi
  why="$(daemon_pending)"
  if [ -z "$why" ]; then skip "LaunchDaemon ${DAEMON_PLIST} current"
  else
    tmp="$(mktemp)"; daemon_plist > "$tmp"
    plutil -lint "$tmp" >/dev/null || { rm -f "$tmp"; fail "the rendered LaunchDaemon plist does not lint: plutil -lint"; }
    { [ ! -f "${DAEMON_PLIST}" ] || sudo -n cp -p "${DAEMON_PLIST}" "${DAEMON_PLIST}.bak"; } \
      && sudo -n install -m 644 -o root -g wheel "$tmp" "${DAEMON_PLIST}" \
      || { rm -f "$tmp"; fail "writing ${DAEMON_PLIST} needs sudo: the installer asks for it when it starts; run it from a terminal"; }
    rm -f "$tmp"
    ok "${why}: ${DAEMON_PLIST} (a previous one is kept as ${DAEMON_PLIST}.bak)"
  fi
  # Never boot out a loaded supervisor: SIGTERM stops the whole stack. A new plist applies at next boot.
  if daemon_loaded; then
    [ -z "$why" ] && skip "LaunchDaemon ${DAEMON_LABEL} loaded" || info "LaunchDaemon ${DAEMON_LABEL} is already loaded; the new plist takes effect at the next boot"
  else
    sudo -n launchctl bootstrap system "${DAEMON_PLIST}" || fail "sudo launchctl bootstrap system ${DAEMON_PLIST} failed"
    ok "LaunchDaemon ${DAEMON_LABEL} loaded: it starts the podman machine and the containers at boot, and stops them at shutdown"
  fi
}

autorestart_state(){ # -> on | off | unsupported
  case "$(pmset -g 2>/dev/null | awk '$1=="autorestart"{print $2}')" in 1) echo on ;; 0) echo off ;; *) echo unsupported ;; esac
}

root_steps_pending(){ # : the host steps that need sudo, comma-separated; nothing when none
  local out='' d
  command -v brew >/dev/null 2>&1 || out="Homebrew install"
  [ "$(autorestart_state)" != off ] || out="${out:+${out}, }pmset autorestart"
  d="$(daemon_pending)"; [ -z "$d" ] || out="${out:+${out}, }${d}"
  if [ -z "$d" ] && ! daemon_loaded; then out="${out:+${out}, }LaunchDaemon ${DAEMON_LABEL} load"; fi
  . "${INSTALL_DIR}/dns.sh"
  d="$(dns_root_pending "${LAN_NAME}")"; [ -z "$d" ] || out="${out:+${out}, }${d}"
  printf '%s' "$out"
}

sudo_upfront(){ # : asks for the sudo password once, before any task runs, when a host step needs root; keeps it valid for the run
  local why
  [ "${DRY}" != 1 ] || return 0
  why="$(root_steps_pending)"
  [ -n "$why" ] || { skip "no host step needs sudo"; return 0; }
  if ! sudo -n true 2>/dev/null; then
    [ -t 0 ] || fail "these steps need sudo: ${why}. Run the installer from a terminal, which asks for the password once at the start"
    info "these steps need sudo: ${why}; asking for the password now, so the rest runs unattended"
    sudo -v || fail "sudo refused"
  fi
  ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) >/dev/null 2>&1 &
  ok "sudo ready for: ${why}"
}

host_macos(){
  if [ "${DRY}" = 1 ]; then
    info "would install Homebrew + podman/podman-compose/jq/gettext via brew, create/start a rootful podman machine (${MACHINE_CPUS} CPU, ${MACHINE_MIB} MiB, ${MACHINE_DISK_GB} GiB), install the LaunchDaemon ${DAEMON_PLIST} that starts it and the containers at boot and stops them at shutdown (retiring any old LaunchAgent), and set power-on after a power failure"
    return 0
  fi

  if ! command -v brew >/dev/null 2>&1; then
    info "installing Homebrew (non-interactive)"
    run env NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
  fi

  require_cmd brew
  for pkg in podman podman-compose jq gettext; do   # gettext: envsubst, for the connector generators
    if brew list --formula "$pkg" >/dev/null 2>&1; then skip "$pkg installed"; else run brew install "$pkg"; fi
  done

  if ! podman machine list --format '{{.Name}}' 2>/dev/null | grep -q .; then
    info "creating the podman machine (${MACHINE_CPUS} CPU, ${MACHINE_MIB} MiB, ${MACHINE_DISK_GB} GiB, rootful)"
    run podman machine init --rootful --cpus "${MACHINE_CPUS}" --memory "${MACHINE_MIB}" --disk-size "${MACHINE_DISK_GB}"
  else
    skip "podman machine exists (preflight checked its size)"
  fi

  if [ "${DRY}" = 1 ] || ! command -v podman >/dev/null 2>&1; then
    info "would start the podman machine"
  else
    if podman machine list --format '{{.Running}}' 2>/dev/null | grep -q true; then skip "podman machine running"; else run podman machine start; fi
    # Rootful on every clinic: ports 80/443 work as is, and the data stays in one storage.
    [ "$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null)" = false ] && ok "podman runs rootful" \
      || fail "podman runs rootless: podman machine stop; podman machine set --rootful; podman machine start (rootless volumes are not seen by rootful)"
  fi

  daemon_install
  # A portable has no autorestart setting; the install goes on without it.
  case "$(autorestart_state)" in
    on)  skip "powers on after a power failure" ;;
    off) sudo -n pmset -a autorestart 1 2>/dev/null && ok "powers on after a power failure" || warn "pmset autorestart needs sudo: the installer asks for it when it starts; run it from a terminal" ;;
    *)   warn "this Mac does not offer power-on after a power failure (pmset autorestart)" ;;
  esac
  # Swap in the VM, so a peak (a restore, a first boot) slows down instead of killing a database.
  # A swapfile of another size is made again at MACHINE_SWAP_GB.
  run podman machine ssh "sudo sh -c 'f=/var/swapfile; want=\$((${MACHINE_SWAP_GB} * 1073741824)); if [ -f \$f ] && [ \$(stat -c %s \$f) != \$want ]; then swapoff \$f 2>/dev/null; rm -f \$f; fi; [ -f \$f ] || { fallocate -l ${MACHINE_SWAP_GB}G \$f && chmod 600 \$f && mkswap \$f >/dev/null; }; swapon --show=NAME --noheadings | grep -qx \$f || swapon \$f; grep -qs \$f /etc/fstab || echo \"\$f none swap defaults 0 0\" >> /etc/fstab'"
  if [ "${DRY}" != 1 ]; then
    sw="$(podman machine ssh "swapon --show=NAME --noheadings | grep -qx /var/swapfile && stat -c %s /var/swapfile" 2>/dev/null | tr -d '\r')"
    [ "${sw:-0}" = "$((MACHINE_SWAP_GB * 1073741824))" ] && ok "podman machine has ${MACHINE_SWAP_GB} GiB of swap (/var/swapfile)" \
      || fail "podman machine swap is '${sw:-none}' bytes, want ${MACHINE_SWAP_GB} GiB: podman machine ssh swapon --show"
  fi
  # the clinic LAN name (dns.sh)
  . "${INSTALL_DIR}/dns.sh"
  dns_install_macos "${LAN_NAME}"
  dns_check "${LAN_NAME}"
}
