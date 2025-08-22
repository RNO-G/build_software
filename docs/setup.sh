# /cvmfs/rnog.opensciencegrid.org/software/setup.sh
# Meta-wrapper that detects OS and sources the correct per-OS setup.
# Supported today: EL8, EL9. Easy to extend (Ubuntu/Debian/etc).

# ----- config -----
_RNOG_PREFIX="/cvmfs/rnog.opensciencegrid.org/software"
# Allow override for testing, e.g. RNOG_OS_OVERRIDE=el8 source setup.sh
_OS_OVERRIDE="${RNOG_OS_OVERRIDE:-}"

# detect if this file is being *sourced* or *executed*
__rn_source_mode=true
(return 0 2>/dev/null) || __rn_source_mode=false

__rn_die() {
  local msg="$1"
  if $__rn_source_mode; then
    echo "[setup.sh] ERROR: $msg" 1>&2
    return 1
  else
    echo "[setup.sh] ERROR: $msg" 1>&2
    exit 1
  fi
}

__rn_info() {
  echo "[setup.sh] $*"
}

__rn_detect_platform() {
  # If user provided an override, trust it (e.g. "el8", "el9", "ubuntu22")
  if [[ -n "$_OS_OVERRIDE" ]]; then
    echo "$_OS_OVERRIDE"
    return 0
  fi

  # Prefer /etc/os-release where available
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release

    # Normalize common EL variants (rhel, rocky, alma, centos-stream)
    if [[ "${ID_LIKE:-}" =~ (rhel|fedora|centos) ]] || [[ "${ID:-}" =~ (rhel|rocky|almalinux|centos) ]]; then
      # VERSION_ID can be "8", "8.9", etc. We only need the major.
      major="${VERSION_ID%%.*}"
      if [[ "$major" =~ ^[0-9]+$ ]]; then
        echo "el${major}"
        return 0
      fi
    fi

    # Example future expansion: Ubuntu/Debian mapping
    if [[ "${ID:-}" == "ubuntu" ]]; then
      # e.g. ubuntu22 for 22.04+, or keep more precise if you prefer
      major="${VERSION_ID%%.*}"
      echo "ubuntu${major}"
      return 0
    fi

    if [[ "${ID:-}" == "debian" ]]; then
      major="${VERSION_ID%%.*}"
      echo "debian${major}"
      return 0
    fi
  fi

  # Fallbacks (less precise, but helpful)
  if command -v rpm >/dev/null 2>&1; then
    # On EL systems, this expands to major version (e.g. 8 or 9)
    rhel_major="$(rpm -E %rhel 2>/dev/null || true)"
    if [[ "$rhel_major" =~ ^[0-9]+$ ]]; then
      echo "el${rhel_major}"
      return 0
    fi
  fi

  __rn_die "Unable to detect OS platform from /etc/os-release or rpm macros."
}

__rn_main() {
  local platform
  platform="$(__rn_detect_platform)" || return 1

  case "$platform" in
    el8|el9)
      target="${_RNOG_PREFIX}/setup_${platform}.sh"
      ;;
    # Uncomment/add mappings as you add support:
    # ubuntu22) target="${_RNOG_PREFIX}/setup_ubuntu22.sh" ;;
    # debian12) target="${_RNOG_PREFIX}/setup_debian12.sh" ;;
    *)
      __rn_die "Unsupported platform '${platform}'. Supported today: el8, el9."
      return 1
      ;;
  esac

  if [[ ! -r "$target" ]]; then
    __rn_die "Expected setup file not found: $target"
    return 1
  fi

  # Optional: show which file we’re sourcing (handy for debugging)
  __rn_info "Detected ${platform}; sourcing $(basename "$target")"
  # shellcheck disable=SC1090
  source "$target"
}

__rn_main || { $__rn_source_mode || exit 1; }
unset -f __rn_main __rn_detect_platform __rn_die __rn_info
unset _RNOG_PREFIX _OS_OVERRIDE __rn_source_mode