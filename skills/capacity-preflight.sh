#!/usr/bin/env bash
#
# capacity-preflight.sh — measure and judge headroom BEFORE you add anything
#                          to a sync-core lab node. (follow-up F-022)
#
# WHY THIS EXISTS — the incident it prevents
# ------------------------------------------
# 2026-09-02, cloud node (samyogas-mac-mini, Colima/docker): the container VM ran
# out of disk and Kafka died. ~2.9GB of Odoo images were pulled onto a Colima VM
# that had ~5GB free, on top of ~4.6GB of Kafka segments a sync loop had already
# written. The VM's 34.2GB disk hit 100% with 0 bytes available. In order:
#
#   1. a Postgres GRANT failed with "could not extend file ... No space left on device"
#   2. Kafka exited(1) and could NOT restart -- it could not write its own log
#   3. openelisdb went unhealthy
#
# Separately and at the same time, cloud-openmrs-1 had been OOM-killed (exit 137):
# Colima is allocated 12GiB of a 16GB host, leaving macOS about 121MB free.
#
# NOTHING WARNED AT ANY POINT. The first signal anyone got was a database write
# error. This script is the warning that did not exist.
#
# The trap the incident turned on: HOST disk free is NOT container-VM disk free.
# The mac mini had gigabytes free on / while the VM inside it was at 100%. Every
# `df -h` anyone ran looked fine. Section 3 below is the number that actually
# mattered, and it is different on all three runtimes we operate.
#
# WHAT IT DOES
# ------------
# For a node, reports and judges six things:
#   1. host memory: available, and how much is compressed / swapped (the OOM precursor)
#   2. host disk free
#   3. container-VM disk free   <-- the one that actually filled
#   4. VM memory allocation vs host RAM (the cloud's actual root cause)
#   5. per-container memory and the total
#   6. runtime reclaimable space
# Then it subtracts what you are ABOUT to add and fails if the projection breaks
# a floor.
#
# WHICH MEMORY NUMBER THE FLOOR USES -- and why it is not `top`'s "unused"
# -----------------------------------------------------------------------
# The obvious metric is the "unused" field of `top -l 1 -n 0 | grep PhysMem`.
# Measured on all three nodes while every one of them was healthy:
#   rawach 113-142M    ghated 217-245M    cloud 77-80M
# macOS deliberately keeps the free list near zero, so a 500MB floor on that
# field FAILS everywhere, always. A gate that is always red is a gate nobody
# reads, which is how the incident happened in the first place.
#
# So the floor is judged on what the kernel can actually hand out without
# swapping -- free + inactive + speculative + purgeable, from `vm_stat`:
#   rawach 3.16GiB     ghated 10.58GiB    cloud 4.19GiB
# That number discriminates between the three nodes; "unused" does not.
# `top`'s unused, compressor and swap are still printed and still raise
# WARNs, because heavy compression next to a tiny free list is the OOM
# precursor the incident showed. Pass --mem-metric unused to gate on the
# raw `top` field instead.
#
# The single most predictive number for the exit-137 half of the incident is
# neither: it is section 5's container total against section 4's VM RAM.
# cloud-openmrs-1 was killed when the containers collectively approached the
# 12GiB the VM had been given. That ratio is checked too.
#
# STRICTLY READ-ONLY. It measures and judges. It never prunes, deletes, stops,
# restarts or reconfigures anything. Safe to run at any time, including mid-sync.
# The one caveat is Docker Desktop, whose VM filesystem can only be reached from
# inside a container: that probe uses the `busybox` image and REFUSES to pull it
# if absent (pass --allow-pull to accept the ~4MB write) so a disk-pressure check
# can never itself consume disk.
#
# THE THREE NODES use THREE different runtimes, and each needs a different probe:
#   rawach  local          Docker Desktop   VM disk via a busybox container mount
#   ghated  ssh ghated     podman rootless  VM disk via `podman info` Store.GraphRoot*
#   cloud   ssh mac mini   Colima/docker    VM disk via `colima ssh -- df`
#
# USAGE
#   ./capacity-preflight.sh --node cloud  --need-disk 3G
#   ./capacity-preflight.sh --all         --need-disk 500M --need-mem 1G
#   ./capacity-preflight.sh --node ghated --need-disk 2G --floor-disk 8G
#
#   --need-disk SIZE   REQUIRED. How much VM disk you are about to add
#                      (image pull, restore, seed dump). e.g. 3G, 500M, 0
#   --need-mem SIZE    How much host memory you are about to commit  [0]
#   --node NAME        rawach | ghated | cloud
#   --all              all three nodes; the worst verdict wins
#   --floor-disk SIZE  VM disk that must remain free afterwards      [5G]
#   --floor-mem SIZE   host memory that must remain available afterwards[500M]
#   --mem-metric M     available (vm_stat, default) | unused (top PhysMem)
#   --warn-vm-ram-pct N  warn when the VM is allocated >N% of host RAM  [70]
#   --warn-disk-pct N  warn when VM disk is already >N% full          [85]
#   --warn-ctr-ram-pct N warn when containers total >N% of VM RAM      [85]
#   --allow-pull       permit the busybox pull on Docker Desktop
#   --quiet            verdict lines only
#
# EXIT CODES
#   0  PASS  -- every floor still met after the addition (WARNs may be printed)
#   1  FAIL  -- a floor would be breached, or already is
#   2  ERROR -- a node was unreachable or a probe could not be made at all
#              (an unmeasurable floor is never reported as a pass)
#
# NOTE — `podman info` and `podman system df` walk the whole image store, so a
# --node ghated run takes a couple of minutes. That is podman, not this script.
#
# NOTE — two traps this script deliberately avoids:
#
#   1. Under `set -o pipefail` a pipeline like `cmd | grep -v X` returns
#      non-zero on empty input and kills the script with no message. Every such
#      pipeline below is guarded with `|| true` and its emptiness checked
#      explicitly instead.
#
#   2. Over the ssh hop the script IS the remote bash's stdin (`bash -s < $0`),
#      and bash reads a piped script incrementally as it runs. Any probe that
#      consumes stdin therefore eats the rest of the script: `colima ssh` runs
#      a real ssh client, so the cloud node silently stopped at section 3, ran
#      off the end of the file and exited 0 while printing FAIL. measure() is
#      called with </dev/null so no probe can ever reach that stdin again.
#
set -euo pipefail

# --- node wiring (overridable by env) --------------------------------------
GHATED_SSH="${GHATED_SSH:-ssh -o BatchMode=yes -o ConnectTimeout=20 ghated}"
CLOUD_SSH="${CLOUD_SSH:-ssh -o BatchMode=yes -o ConnectTimeout=20 samyoga@samyogas-mac-mini.tailca2651.ts.net}"
# ghated is rootless podman: docker-compose reaches it only through DOCKER_HOST,
# and homebrew's bin is not on a non-login ssh PATH on either remote.
GHATED_DOCKER_HOST="${GHATED_DOCKER_HOST:-unix:///var/folders/81/w9gnyn_14w17wh_7120pfs5r0000gn/T/podman/podman-machine-default-api.sock}"
REMOTE_PATH="${REMOTE_PATH:-/opt/homebrew/bin:\$PATH}"
COLIMA_PROFILE="${COLIMA_PROFILE:-default}"

# --- defaults ---------------------------------------------------------------
NEED_DISK_RAW=""; NEED_MEM_RAW="0"
FLOOR_DISK_RAW="5G"; FLOOR_MEM_RAW="500M"
WARN_VM_RAM_PCT=70; WARN_DISK_PCT=85; WARN_CTR_RAM_PCT=85; MEM_METRIC=available
NODES=""; LOCAL_ONLY=0; QUIET=0; ALLOW_PULL=0

usage() { sed -n '2,116p' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --need-disk)       NEED_DISK_RAW="${2:-}"; shift 2 ;;
    --need-mem)        NEED_MEM_RAW="${2:-}"; shift 2 ;;
    --floor-disk)      FLOOR_DISK_RAW="${2:-}"; shift 2 ;;
    --floor-mem)       FLOOR_MEM_RAW="${2:-}"; shift 2 ;;
    --warn-vm-ram-pct) WARN_VM_RAM_PCT="${2:-}"; shift 2 ;;
    --warn-disk-pct)   WARN_DISK_PCT="${2:-}"; shift 2 ;;
    --warn-ctr-ram-pct) WARN_CTR_RAM_PCT="${2:-}"; shift 2 ;;
    --mem-metric)      MEM_METRIC="${2:-}"; shift 2 ;;
    --node)            NODES="$NODES ${2:-}"; shift 2 ;;
    --all)             NODES="rawach ghated cloud"; shift ;;
    --local)           LOCAL_ONLY=1; shift ;;     # internal: set by the ssh hop
    --allow-pull)      ALLOW_PULL=1; shift ;;
    --quiet)           QUIET=1; shift ;;
    -h|--help)         usage; exit 0 ;;
    *) echo "unknown option: $1  (see --help)" >&2; exit 2 ;;
  esac
done

[ -n "$NEED_DISK_RAW" ] || { echo "ERROR: --need-disk is required. Say how much you are about to add (e.g. --need-disk 3G, or 0)." >&2; exit 2; }
case "$MEM_METRIC" in available|unused) ;; *) echo "ERROR: --mem-metric must be 'available' or 'unused'" >&2; exit 2 ;; esac
NODES="$(echo "$NODES" | xargs || true)"
[ -n "$NODES" ] || NODES="rawach"

say()  { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
loud() { printf '%s\n' "$*"; }

# --- units ------------------------------------------------------------------
# Bare K/M/G and the KiB/MiB/GiB forms are 1024-based (df -h, macOS `top`,
# `sysctl vm.swapusage`, docker stats). The explicit KB/MB/GB forms are
# 1000-based, which is what podman's stats and info actually print.
to_bytes() {
  printf '%s' "${1:-}" | awk '
    { s=$0
      if (!match(s, /^[0-9]+(\.[0-9]+)?/)) { print "ERR"; exit }
      n=substr(s,RSTART,RLENGTH); u=substr(s,RSTART+RLENGTH)
      gsub(/[ \t]/,"",u); u=toupper(u)
      if      (u==""   || u=="B")               m=1
      else if (u=="K"  || u=="KIB")             m=1024
      else if (u=="M"  || u=="MIB")             m=1024^2
      else if (u=="G"  || u=="GIB")             m=1024^3
      else if (u=="T"  || u=="TIB")             m=1024^4
      else if (u=="KB")                         m=1000
      else if (u=="MB")                         m=1000^2
      else if (u=="GB")                         m=1000^3
      else if (u=="TB")                         m=1000^4
      else { print "ERR"; exit }
      printf "%.0f", n*m }'
}
fmt() {  # bytes -> human, 1024-based; handles the negative "you are this far
         # over" case the verdict produces
  awk -v b="${1:-0}" 'BEGIN{
    if (b=="" || b=="n/a") { print "n/a"; exit }
    sign=""; v=b+0; if (v<0) { sign="-"; v=-v }
    s="B"
    if (v>=1024^4) { v=v/1024^4; s="TiB" } else if (v>=1024^3) { v=v/1024^3; s="GiB" }
    else if (v>=1024^2) { v=v/1024^2; s="MiB" } else if (v>=1024) { v=v/1024; s="KiB" }
    printf (s=="B" ? "%s%.0f%s\n" : "%s%.2f%s\n"), sign, v, s }'
}
pct() { awk -v a="${1:-0}" -v b="${2:-0}" 'BEGIN{ if (b+0==0) print "n/a"; else printf "%.1f", 100*a/b }'; }
ge()  { awk -v a="${1:-0}" -v b="${2:-0}" 'BEGIN{ exit !(a+0 >= b+0) }'; }

NEED_DISK=$(to_bytes "$NEED_DISK_RAW");  NEED_MEM=$(to_bytes "$NEED_MEM_RAW")
FLOOR_DISK=$(to_bytes "$FLOOR_DISK_RAW"); FLOOR_MEM=$(to_bytes "$FLOOR_MEM_RAW")
for v in "$NEED_DISK:--need-disk" "$NEED_MEM:--need-mem" "$FLOOR_DISK:--floor-disk" "$FLOOR_MEM:--floor-mem"; do
  case "$v" in ERR:*) echo "ERROR: cannot parse size for ${v#*:}" >&2; exit 2 ;; esac
done

# ============================================================================
#  LOCAL MEASUREMENT  -- everything below runs ON the node being measured
# ============================================================================
# `podman info` walks the whole image store and takes tens of seconds, so it is
# called ONCE and every field the script needs is pulled from that one call.
# detect_runtime sets globals rather than echoing, so the cache survives.
RT=none; PODMAN_INFO=""
detect_runtime() {
  # podman first: on ghated there is no `docker` binary at all, and on a host
  # with podman installed but no machine the info call fails and we fall through.
  if command -v podman >/dev/null 2>&1; then
    PODMAN_INFO=$(podman info --format '{{.Store.GraphRootAllocated}}|{{.Store.GraphRootUsed}}|{{.Store.GraphRoot}}|{{.Host.MemTotal}}' 2>/dev/null || true)
    if [ -n "$PODMAN_INFO" ]; then RT=podman; return; fi
  fi
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    local name; name=$(docker info --format '{{.Name}}' 2>/dev/null || true)
    case "$name" in
      colima*)         RT=colima ;;
      docker-desktop*) RT=docker-desktop ;;
      *)               RT=docker ;;
    esac
    return
  fi
  RT=none
}

measure() {
  local node="$1"
  detect_runtime; local rt="$RT"
  local fail=0 warn=0 unmeasured=0

  say "============================================================"
  say "NODE: $node    runtime: $rt    $(hostname -s 2>/dev/null || echo '?')    $(date '+%Y-%m-%d %H:%M:%S')"
  say "============================================================"

  if [ "$rt" = "none" ]; then
    loud "  ERROR: no reachable container runtime (no working podman or docker)."
    loud "         PATH=$PATH  DOCKER_HOST=${DOCKER_HOST:-unset}"
    return 2
  fi
  local CLI=docker; [ "$rt" = "podman" ] && CLI=podman

  # --- 1. HOST MEMORY -------------------------------------------------------
  # macOS reports this only through `top`; the line looks like
  #   PhysMem: 17G used (2619M wired, 8402M compressor), 152M unused.
  # "unused" is the number the OOM killer is effectively racing. A large
  # compressor plus a small unused is the precursor: the kernel is already
  # squeezing pages to stay alive, and the next container start is the one
  # that gets exit 137. That is exactly how cloud-openmrs-1 died.
  say ""
  say "-- 1. HOST MEMORY --"
  local host_mem_total physmem mem_unused mem_wired mem_compressor
  host_mem_total=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
  physmem=$(top -l 1 -n 0 2>/dev/null | grep PhysMem || true)
  if [ -z "$physmem" ]; then
    loud "  ERROR: could not read PhysMem from top -- host memory floor is UNMEASURED."
    unmeasured=1; mem_unused=""
  else
    mem_unused=$(to_bytes "$(echo "$physmem"     | sed -n 's/.*[,(] *\([0-9.]*[A-Za-z]*\) unused.*/\1/p')")
    mem_wired=$(to_bytes "$(echo "$physmem"      | sed -n 's/.*(\([0-9.]*[A-Za-z]*\) wired.*/\1/p')")
    mem_compressor=$(to_bytes "$(echo "$physmem" | sed -n 's/.*[,(] *\([0-9.]*[A-Za-z]*\) compressor.*/\1/p')")
    case "$mem_unused" in ERR|"") loud "  ERROR: could not parse: $physmem"; unmeasured=1; mem_unused="" ;; esac
  fi
  local swap swap_total swap_used
  swap=$(sysctl vm.swapusage 2>/dev/null || true)
  swap_total=$(to_bytes "$(echo "$swap" | sed -n 's/.*total = \([0-9.]*[A-Za-z]*\).*/\1/p')")
  swap_used=$(to_bytes  "$(echo "$swap" | sed -n 's/.*used = \([0-9.]*[A-Za-z]*\).*/\1/p')")
  case "$swap_total" in ERR|"") swap_total=0 ;; esac
  case "$swap_used"  in ERR|"") swap_used=0 ;;  esac

  say "  host RAM total     : $(fmt "$host_mem_total")"
  if [ -n "$mem_unused" ]; then
    say "  unused             : $(fmt "$mem_unused")  ($(pct "$mem_unused" "$host_mem_total")% of host)"
    say "  wired              : $(fmt "$mem_wired")"
    say "  compressor         : $(fmt "$mem_compressor")  ($(pct "$mem_compressor" "$host_mem_total")% of host -- pages the kernel is squeezing to stay alive)"
  fi
  # What the kernel can still hand out without swapping. `top`'s "unused" is
  # only the free list, which macOS keeps near zero by design (measured
  # 77-245MB on all three nodes while healthy) -- see the header.
  local mem_avail=""
  local vs; vs=$(vm_stat 2>/dev/null || true)
  if [ -n "$vs" ]; then
    mem_avail=$(printf '%s' "$vs" | awk '
      /page size of/ { if (match($0,/[0-9]+/)) ps=substr($0,RSTART,RLENGTH) }
      /^Pages free:/        { f=$3+0 } /^Pages inactive:/    { i=$3+0 }
      /^Pages speculative:/ { sp=$3+0 } /^Pages purgeable:/  { pu=$3+0 }
      END { if (ps=="") ps=4096; printf "%.0f", (f+i+sp+pu)*ps }')
  fi
  if [ -z "$mem_avail" ] || [ "$mem_avail" = "0" ]; then
    loud "  ERROR: vm_stat gave no usable numbers -- available memory is UNMEASURED."
    unmeasured=1; mem_avail=""
  else
    say "  available          : $(fmt "$mem_avail")  ($(pct "$mem_avail" "$host_mem_total")% of host -- free+inactive+speculative+purgeable)"
  fi
  say "  swap used          : $(fmt "$swap_used") of $(fmt "$swap_total")"
  if [ -n "$mem_compressor" ] && ge "$(pct "$mem_compressor" "$host_mem_total")" 25; then
    loud "  ! WARN  compressor is >25% of host RAM -- this is the OOM precursor (exit 137)."; warn=1
  fi
  if [ "$swap_total" -gt 0 ] && ge "$(pct "$swap_used" "$swap_total")" 70; then
    loud "  ! WARN  swap is >70% consumed."; warn=1
  fi
  if [ -n "$mem_unused" ] && [ "$mem_unused" -lt "$FLOOR_MEM" ]; then
    say "  (note: top's raw 'unused' is under the $(fmt "$FLOOR_MEM") floor, but that is normal on"
    say "   macOS and is not what the floor is judged on -- see --mem-metric in --help)"
  fi

  # --- 2. HOST DISK ---------------------------------------------------------
  # Reported for completeness and, more importantly, as the decoy: during the
  # incident this number looked healthy while the VM below was at 100%.
  say ""
  say "-- 2. HOST DISK (/) --"
  local hd hd_size hd_used hd_avail hd_pct
  hd=$(df -Pk / 2>/dev/null | tail -1 || true)
  if [ -z "$hd" ]; then
    loud "  ERROR: df -Pk / produced nothing."; unmeasured=1
  else
    hd_size=$(( $(echo "$hd" | awk '{print $2}') * 1024 ))
    hd_used=$(( $(echo "$hd" | awk '{print $3}') * 1024 ))
    hd_avail=$(( $(echo "$hd" | awk '{print $4}') * 1024 ))
    hd_pct=$(echo "$hd" | awk '{print $5}')
    say "  size / used / free : $(fmt "$hd_size") / $(fmt "$hd_used") / $(fmt "$hd_avail")   ($hd_pct full)"
    say "  NOTE: this is NOT the number that filled on 2026-09-02. See section 3."
  fi

  # --- 3. CONTAINER-VM DISK -- the one that actually filled -----------------
  say ""
  say "-- 3. CONTAINER-VM DISK (the number that filled) --"
  local vm_size=0 vm_used=0 vm_avail="" vm_src="" dfline=""
  case "$rt" in
    podman)
      # Rootless podman on applehv: the storage lives inside the VM and the
      # host cannot see it. `podman info` reports the numbers directly, which
      # needs no container and no `podman machine ssh` round trip.
      if [ -n "$PODMAN_INFO" ]; then
        vm_size=$(echo "$PODMAN_INFO" | cut -d'|' -f1); vm_used=$(echo "$PODMAN_INFO" | cut -d'|' -f2)
        vm_avail=$(( vm_size - vm_used ))
        vm_src="podman info Store.GraphRootAllocated/Used ($(echo "$PODMAN_INFO" | cut -d'|' -f3))"
      fi
      ;;
    colima)
      # Colima gives us a shell in the VM, so no container and no image pull.
      dfline=$(colima ssh --profile "$COLIMA_PROFILE" -- df -Pk /var/lib/docker 2>/dev/null | tail -1 || true)
      if [ -n "$dfline" ]; then vm_src="colima ssh -- df -Pk /var/lib/docker"; fi
      ;;
    docker-desktop|docker)
      # Docker Desktop's VM filesystem is reachable ONLY from inside a
      # container. Refuse to pull for a disk check unless told otherwise.
      if docker image inspect busybox >/dev/null 2>&1 || [ "$ALLOW_PULL" = 1 ]; then
        dfline=$(docker run --rm --privileged -v /var/lib/docker:/d busybox df -Pk /d 2>/dev/null | tail -1 || true)
        if [ -n "$dfline" ]; then vm_src="docker run --rm --privileged -v /var/lib/docker:/d busybox df -Pk /d"; fi
      else
        loud "  ERROR: the busybox image is not present locally and Docker Desktop's VM"
        loud "         filesystem can only be read from inside a container. Refusing to"
        loud "         pull (~4MB) during a disk-pressure check. Re-run with --allow-pull,"
        loud "         or: docker pull busybox"
        unmeasured=1
      fi
      ;;
  esac
  if [ -n "$dfline" ]; then
    vm_size=$(( $(echo "$dfline" | awk '{print $2}') * 1024 ))
    vm_used=$(( $(echo "$dfline" | awk '{print $3}') * 1024 ))
    vm_avail=$(( $(echo "$dfline" | awk '{print $4}') * 1024 ))
  fi
  if [ -z "$vm_avail" ]; then
    if [ "$unmeasured" != 1 ]; then loud "  ERROR: could not probe the container-VM disk on runtime '$rt'."; fi
    unmeasured=1
  else
    local vm_use_pct; vm_use_pct=$(pct "$vm_used" "$vm_size")
    say "  probe              : $vm_src"
    say "  size / used / free : $(fmt "$vm_size") / $(fmt "$vm_used") / $(fmt "$vm_avail")   (${vm_use_pct}% full)"
    if ge "$vm_use_pct" "$WARN_DISK_PCT"; then
      loud "  ! WARN  VM disk is already >${WARN_DISK_PCT}% full. On 2026-09-02 this reached 100%,"
      loud "          Kafka exited(1) and could not restart because it could not write its own log."
      warn=1
    fi
  fi

  # --- 4. VM MEMORY ALLOCATION vs HOST RAM ----------------------------------
  # The cloud's actual root cause: 12GiB handed to Colima out of a 16GB host
  # leaves macOS ~121MB to work with, and the host starts OOM-killing.
  say ""
  say "-- 4. VM MEMORY ALLOCATION vs HOST RAM --"
  local vm_mem=0
  if [ "$rt" = "podman" ]; then
    vm_mem=$(echo "$PODMAN_INFO" | cut -d'|' -f4)
    local pml; pml=$(podman machine list 2>/dev/null | tail -n +2 || true)
    if [ -n "$pml" ]; then say "  podman machine     : $(echo "$pml" | head -1 | awk '{$1=$1;print}')"; fi
  else
    vm_mem=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
    if command -v colima >/dev/null 2>&1; then
      local cl; cl=$(colima list 2>/dev/null | tail -n +2 || true)
      if [ -n "$cl" ]; then say "  colima profile     : $(echo "$cl" | head -1 | awk '{$1=$1;print}')"; fi
    fi
  fi
  if [ "${vm_mem:-0}" -gt 0 ] && [ "${host_mem_total:-0}" -gt 0 ]; then
    local ratio; ratio=$(pct "$vm_mem" "$host_mem_total")
    say "  VM allocated RAM   : $(fmt "$vm_mem")  = ${ratio}% of the $(fmt "$host_mem_total") host"
    say "  left for the host  : $(fmt $(( host_mem_total - vm_mem ))) minus whatever macOS itself is using"
    if ge "$ratio" "$WARN_VM_RAM_PCT"; then
      loud "  ! WARN  the VM holds >${WARN_VM_RAM_PCT}% of host RAM. This is the cloud's root cause:"
      loud "          12GiB of a 16GB host left macOS ~121MB and cloud-openmrs-1 was OOM-killed (exit 137)."
      warn=1
    fi
  else
    say "  VM allocated RAM   : n/a"
  fi

  # --- 5. PER-CONTAINER MEMORY ----------------------------------------------
  say ""
  say "-- 5. PER-CONTAINER MEMORY --"
  local ctr_total=0
  local stats; stats=$($CLI stats --no-stream --format '{{.Name}}|{{.MemUsage}}' 2>/dev/null || true)
  if [ -z "$stats" ]; then
    say "  (no running containers, or $CLI stats returned nothing)"
  else
    local total=0 line name usage bytes n=0
    local tmp; tmp=$(mktemp)
    while IFS='|' read -r name usage; do
      [ -n "$name" ] || continue
      bytes=$(to_bytes "$(echo "$usage" | awk -F'/' '{gsub(/ /,"",$1); print $1}')")
      case "$bytes" in ERR|"") bytes=0 ;; esac
      total=$(( total + bytes )); n=$(( n + 1 ))
      printf '%s %s\n' "$bytes" "$name" >> "$tmp"
    done <<< "$stats"
    # `sort | head` can raise SIGPIPE on sort, which pipefail turns into a
    # silent exit; guard it the way this repo's other scripts guard `| grep`.
    (sort -rn "$tmp" | head -8 || true) | while read -r bytes name; do
      say "  $(printf '%-38s %10s' "$name" "$(fmt "$bytes")")"
    done
    if [ "$n" -gt 8 ]; then say "  ... and $(( n - 8 )) more"; fi
    say "  ------------------------------------------------------"
    say "  $(printf '%-38s %10s' "TOTAL ($n containers)" "$(fmt "$total")") of $(fmt "$vm_mem") VM RAM"
    rm -f "$tmp"
    ctr_total=$total
    # This ratio is the exit-137 precursor. cloud-openmrs-1 was OOM-killed when
    # the containers collectively approached the 12GiB the VM had been given;
    # the host's own free memory was a symptom, not the limit that was hit.
    if [ "${vm_mem:-0}" -gt 0 ]; then
      local cr; cr=$(pct "$ctr_total" "$vm_mem")
      if ge "$cr" "$WARN_CTR_RAM_PCT"; then
        loud "  ! WARN  containers hold ${cr}% of the VM's RAM (>${WARN_CTR_RAM_PCT}%). This is the"
        loud "          exit-137 precursor: the next container to grow gets OOM-killed."
        warn=1
      fi
    fi
  fi

  # --- 6. RECLAIMABLE -------------------------------------------------------
  say ""
  say "-- 6. RECLAIMABLE (informational -- this script never reclaims) --"
  local sdf; sdf=$($CLI system df 2>/dev/null || true)
  if [ -n "$sdf" ]; then
    while IFS= read -r line; do say "  $line"; done <<< "$sdf"
  else
    say "  ($CLI system df unavailable)"
  fi

  # --- VERDICT --------------------------------------------------------------
  say ""
  loud "-- VERDICT for $node (adding $(fmt "$NEED_DISK") disk, $(fmt "$NEED_MEM") memory) --"
  if [ -n "$vm_avail" ]; then
    local after_disk=$(( vm_avail - NEED_DISK ))
    if [ "$after_disk" -lt "$FLOOR_DISK" ]; then
      loud "  FAIL  VM disk: $(fmt "$vm_avail") free - $(fmt "$NEED_DISK") = $(fmt "$after_disk") left, below the $(fmt "$FLOOR_DISK") floor."
      if [ "$vm_avail" -lt "$FLOOR_DISK" ]; then loud "        (it is ALREADY below the floor before you add anything)"; fi
      fail=1
    else
      loud "  ok    VM disk: $(fmt "$vm_avail") free - $(fmt "$NEED_DISK") = $(fmt "$after_disk") left, floor is $(fmt "$FLOOR_DISK")."
    fi
  fi
  local mem_now="" mem_label=""
  if [ "$MEM_METRIC" = unused ]; then mem_now="$mem_unused"; mem_label="unused (top)"
  else                                mem_now="$mem_avail";  mem_label="available (vm_stat)"; fi
  if [ -n "$mem_now" ]; then
    local after_mem=$(( mem_now - NEED_MEM ))
    if [ "$after_mem" -lt "$FLOOR_MEM" ]; then
      loud "  FAIL  host memory: $(fmt "$mem_now") $mem_label - $(fmt "$NEED_MEM") = $(fmt "$after_mem") left, below the $(fmt "$FLOOR_MEM") floor."
      if [ "$mem_now" -lt "$FLOOR_MEM" ]; then loud "        (it is ALREADY below the floor before you add anything)"; fi
      fail=1
    else
      loud "  ok    host memory: $(fmt "$mem_now") $mem_label - $(fmt "$NEED_MEM") = $(fmt "$after_mem") left, floor is $(fmt "$FLOOR_MEM")."
    fi
  fi
  if [ "$unmeasured" = 1 ]; then
    loud "  $node: ERROR -- at least one floor could not be measured. Not reporting a pass."
    return 2
  fi
  if [ "$fail" = 1 ]; then
    loud "  $node: FAIL -- do not add this here until you free space or move the work."
    return 1
  fi
  if [ "$warn" = 1 ]; then
    loud "  $node: PASS WITH WARNINGS -- floors hold, but a precursor above is already lit."
    return 0
  fi
  loud "  $node: PASS -- headroom holds after the addition."
  return 0
}

# ============================================================================
#  DISPATCH -- local, or push this same script over ssh and run it there
# ============================================================================
remote_args() {
  printf -- '--local --node %s --need-disk %s --need-mem %s --floor-disk %s --floor-mem %s --warn-vm-ram-pct %s --warn-disk-pct %s --warn-ctr-ram-pct %s --mem-metric %s' \
    "$1" "$NEED_DISK_RAW" "$NEED_MEM_RAW" "$FLOOR_DISK_RAW" "$FLOOR_MEM_RAW" "$WARN_VM_RAM_PCT" "$WARN_DISK_PCT" "$WARN_CTR_RAM_PCT" "$MEM_METRIC"
  if [ "$QUIET" = 1 ];      then printf ' --quiet'; fi
  if [ "$ALLOW_PULL" = 1 ]; then printf ' --allow-pull'; fi
  return 0
}

run_node() {
  local node="$1"
  if [ "$LOCAL_ONLY" = 1 ]; then
    measure "$node" </dev/null; return $?
  fi
  case "$node" in
    rawach)
      measure "$node" </dev/null; return $? ;;
    ghated)
      # One source of truth: the script is piped to the remote's bash rather
      # than duplicating every probe as a quoted command string.
      $GHATED_SSH "export PATH=$REMOTE_PATH; export DOCKER_HOST=$GHATED_DOCKER_HOST; bash -s -- $(remote_args ghated)" < "$0"
      return $? ;;
    cloud)
      $CLOUD_SSH "export PATH=$REMOTE_PATH; bash -s -- $(remote_args cloud)" < "$0"
      return $? ;;
    *)
      echo "unknown node: $node  (rawach | ghated | cloud)" >&2; return 2 ;;
  esac
}

worst=0
for n in $NODES; do
  rc=0
  run_node "$n" || rc=$?
  # ERROR(2) outranks FAIL(1) outranks PASS(0): never let an unreachable node
  # be washed out by a passing one.
  if [ "$rc" -gt "$worst" ]; then worst=$rc; fi
  say ""
done

if [ "$LOCAL_ONLY" = 0 ] && [ "$(echo "$NODES" | wc -w | tr -d ' ')" -gt 1 ]; then
  case "$worst" in
    0) loud "OVERALL: PASS  -- every node has headroom for this addition." ;;
    1) loud "OVERALL: FAIL  -- at least one node would breach a floor." ;;
    *) loud "OVERALL: ERROR -- at least one node could not be assessed." ;;
  esac
fi
exit "$worst"
