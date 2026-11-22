#!/usr/bin/env bash
# Prepares the Mac: Homebrew, podman and its machine, docker-compose, start at login, dnsmasq, ports 80/443.

podman_machine_size(){
  local host_mib="$1" host_cpus="$2" mem cpus
  mem=$(( host_mib * 55 / 100 )); [ "$mem" -le 12288 ] || mem=12288
  mem=$(( (mem / 1024) * 1024 ))
  [ "$mem" -ge 10240 ] || [ "$host_mib" -lt 16384 ] || mem=10240
  cpus=$(( host_cpus - 2 )); [ "$cpus" -le 8 ] || cpus=8; [ "$cpus" -ge 2 ] || cpus=2
  MACHINE_MIB="$mem"
  MACHINE_CPUS="$cpus"
}

autorestart_state(){ # -> on | off | unsupported
  case "$(pmset -g 2>/dev/null | awk '$1=="autorestart"{print $2}')" in 1) echo on ;; 0) echo off ;; *) echo unsupported ;; esac
}

root_steps_pending(){ # : the host steps that need sudo, comma-separated; nothing when none
  local out='' d
  command -v brew >/dev/null 2>&1 || out="Homebrew install"
  [ "$(autorestart_state)" != off ] || out="${out:+${out}, }pmset autorestart"
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
    info "would install Homebrew + podman/docker-compose/jq/gettext via brew, create/start a podman machine sized from host RAM, persist DOCKER_HOST in ~/.zprofile, and install the LaunchAgent that starts it at login, and set power-on after a power failure"
    return 0
  fi

  if ! command -v brew >/dev/null 2>&1; then
    info "installing Homebrew (non-interactive)"
    run env NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
  fi

  require_cmd brew
  for pkg in podman docker-compose jq gettext; do   # gettext: envsubst, for the connector generators
    if brew list --formula "$pkg" >/dev/null 2>&1; then skip "$pkg installed"; else run brew install "$pkg"; fi
  done

  if ! podman machine list --format '{{.Name}}' 2>/dev/null | grep -q .; then
    host_mib="${HOST_MIB:-$(( $(sysctl -n hw.memsize) / 1048576 ))}"
    host_cpus="${HOST_CPUS:-$(sysctl -n hw.ncpu)}"
    podman_machine_size "$host_mib" "$host_cpus"
    if [ "$MACHINE_MIB" -lt 10240 ]; then
      fail "this Mac has ${host_mib} MiB RAM; a clinic's podman machine needs 10 GiB (10240 MiB), which this installer gives a Mac of 16 GiB (16384 MiB) or more"
    fi

    info "creating the podman machine (${MACHINE_CPUS} CPU, ${MACHINE_MIB} MiB, 120 GiB, rootless; 55% of ${host_mib} MiB host RAM, capped at 12288)"
    run podman machine init --cpus "${MACHINE_CPUS}" --memory "${MACHINE_MIB}" --disk-size 120
  else
    skip "podman machine exists"

    existing_mib="$(podman machine inspect --format '{{.Resources.Memory}}' 2>/dev/null || true)"
    if [ -n "${existing_mib:-}" ] && [ "$existing_mib" -lt 10240 ]; then
      warn "the existing podman machine has ${existing_mib} MiB, below the 10 GiB a clinic needs: podman machine set --memory 10240 (or more), then restart the machine"
    fi
  fi

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

  plist="${HOME}/Library/LaunchAgents/com.bahmni.clinic.start-at-login.plist"
  if [ -f "$plist" ] && [ "$(plutil -extract AbandonProcessGroup raw "$plist" 2>/dev/null || true)" != true ]; then
    run plutil -insert AbandonProcessGroup -bool true "$plist"
    run launchctl unload "$plist"
    run launchctl load "$plist"
    ok "LaunchAgent keeps the podman machine it starts: ${plist}"
  elif [ ! -f "$plist" ]; then
    mkdir -p "${HOME}/Library/LaunchAgents"
    run sh -c "cat > '${plist}' <<EOF
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\"><dict>
  <key>Label</key><string>com.bahmni.clinic.start-at-login</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>${CLINIC_DIR}/podman/start-at-login.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>AbandonProcessGroup</key><true/>
  <key>StandardOutPath</key><string>${HOME}/Library/Logs/bahmni-clinic-start.log</string>
  <key>StandardErrorPath</key><string>${HOME}/Library/Logs/bahmni-clinic-start.log</string>
</dict></plist>
EOF"
    run launchctl load "$plist"
    ok "LaunchAgent installed: ${plist}"
  else skip "LaunchAgent present"; fi
  # A portable has no autorestart setting; the install goes on without it.
  case "$(autorestart_state)" in
    on)  skip "powers on after a power failure" ;;
    off) sudo -n pmset -a autorestart 1 2>/dev/null && ok "powers on after a power failure" || warn "pmset autorestart needs sudo: the installer asks for it when it starts; run it from a terminal" ;;
    *)   warn "this Mac does not offer power-on after a power failure (pmset autorestart)" ;;
  esac
  [ -n "$(defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true)" ] && ok "automatic login is on" \
    || warn "automatic login is off: after a power cut nothing starts until someone logs in. Turn it on in System Settings > Users & Groups"
  case "$(fdesetup status 2>/dev/null || true)" in *"FileVault is Off"*) true ;; *) false ;; esac && ok "FileVault is off" \
    || warn "FileVault is on: the Mac waits at the unlock screen after a power cut, and automatic login cannot be turned on"
  # The proxy publishes 80 and 443. Rootless podman runs containers as a user
  # inside the podman machine, where Linux refuses ports below
  # ip_unprivileged_port_start (1024 by default); lower it to 80 there, and
  # persist it. A rootful machine is not the fix: its storage is separate,
  # and this node's databases live on the rootless one's volumes.
  # sysctl --system applies /etc/sysctl.conf last, so a value set there is rewritten too.
  run podman machine ssh "printf 'net.ipv4.ip_unprivileged_port_start=80\n' | sudo tee /etc/sysctl.d/90-clinic-low-ports.conf >/dev/null && sudo sed -i 's/^net.ipv4.ip_unprivileged_port_start=.*/net.ipv4.ip_unprivileged_port_start=80/' /etc/sysctl.conf && sudo sysctl -q --system"
  # The machine has no swap by default: when the stack's peak (a restore, a
  # first boot) outgrows the machine, the kernel kills a database instead of
  # slowing down. A 4 GiB swapfile, persisted in fstab.
  run podman machine ssh "sudo sh -c '[ -f /var/swapfile ] || { fallocate -l 4G /var/swapfile && chmod 600 /var/swapfile && mkswap /var/swapfile >/dev/null; }; swapon --show=NAME --noheadings | grep -qx /var/swapfile || swapon /var/swapfile; grep -qs /var/swapfile /etc/fstab || echo \"/var/swapfile none swap defaults 0 0\" >> /etc/fstab'"
  if [ "${DRY}" != 1 ]; then
    sw="$(podman machine ssh "swapon --show=NAME --noheadings" 2>/dev/null | tr -d '\r' | grep -x /var/swapfile || true)"
    [ -n "$sw" ] && ok "podman machine has 4 GiB of swap (/var/swapfile)" || fail "podman machine has no swap: podman machine ssh swapon --show"
  fi
  if [ "${DRY}" != 1 ]; then
    lp="$(podman machine ssh sysctl -n net.ipv4.ip_unprivileged_port_start 2>/dev/null | tr -d '\r')"
    [ "${lp:-1024}" -le 80 ] && ok "podman machine allows ports from ${lp}" || fail "podman machine still refuses ports below ${lp:-unknown}: podman machine ssh sysctl net.ipv4.ip_unprivileged_port_start"
  fi
  # the clinic LAN name (dns.sh)
  . "${INSTALL_DIR}/dns.sh"
  dns_install_macos "${LAN_NAME}"
  dns_check "${LAN_NAME}"
}
