#!/usr/bin/env bash
# shellcheck disable=SC2155

set -Eeuo pipefail

# -------- colors & logging ----------------------------------------------------
COLOR_BLUE=""; COLOR_GREEN=""; COLOR_RED=""; COLOR_YELLOW=""; COLOR_RESET=""
if [[ -t 1 ]]; then
  COLOR_BLUE=$'\e[34m'; COLOR_GREEN=$'\e[32m'; COLOR_RED=$'\e[31m'
  COLOR_YELLOW=$'\e[33m'; COLOR_RESET=$'\e[0m'
fi

log()   { printf "%s\n" "$*"; }
info()  { printf "%b[INFO]%b %s\n"   "$COLOR_BLUE" "$COLOR_RESET" "$*"; }
ok()    { printf "%b[OK]%b %s\n"     "$COLOR_GREEN" "$COLOR_RESET" "$*"; }
warn()  { printf "%b[WARN]%b %s\n"   "$COLOR_YELLOW" "$COLOR_RESET" "$*"; }
error() { printf "%b[ERROR]%b %s\n"  "$COLOR_RED" "$COLOR_RESET" "$*" >&2; }

trap 'error "Unexpected error on line $LINENO"; exit 1' ERR

export TERM=${TERM:-xterm-256color}

# -------- defaults ------------------------------------------------------------
DOWNLOAD_SCRIPTS="${DOWNLOAD_SCRIPTS:-false}"
ARGUMENTS="${ARGUMENTS:-}"
PRODUCTION_INSTALL="${PRODUCTION_INSTALL:-false}"
LOCAL_INSTALL="${LOCAL_INSTALL:-false}"
LOCAL_UPDATE="${LOCAL_UPDATE:-false}"
TEST_REPO_ENABLE="${TEST_REPO_ENABLE:-false}"
VER="${VER:-stable}"

readonly SERVICES_SYSTEMD=(
  "ds-converter.service"
  "ds-docservice.service"
  "ds-metrics.service"
)

# -------- usage ---------------------------------------------------------------
usage() {
  cat <<'USAGE'
Usage: install-and-check.sh [options]

  -d  <true|false>   (alias: --download-scripts) download docs-install.sh
  -a  "<args>"       (alias: --arguments)        arguments to pass into docs-install.sh
  -p  <true|false>   (alias: --production-install)
  -lI <true|false>   (alias: --local-install)
  -lU <true|false>   (alias: --local-update)
  -t  <true|false>   (alias: --test-repo)
  -v  <channel>      (alias: --version)          repo channel/version (e.g. stable, testing, 9.1)

Examples:
  ./install-and-check.sh -d true -a "--apply-transactions true" -t true -v testing
USAGE
}

# -------- args parsing --------------------------------------------------------
# getopts: short flags; long aliases handled manually
while (( $# )); do
  case "${1:-}" in
    --download-scripts) set -- "-d" "${2:-}" "${@:3}";;
    --arguments)        set -- "-a" "${2:-}" "${@:3}";;
    --production-install) set -- "-p" "${2:-}" "${@:3}";;
    --local-install)    set -- "-lI" "${2:-}" "${@:3}";;
    --local-update)     set -- "-lU" "${2:-}" "${@:3}";;
    --test-repo)        set -- "-t" "${2:-}" "${@:3}";;
    --version)          set -- "-v" "${2:-}" "${@:3}";;
    -h|--help) usage; exit 0;;
  esac
  shift || true
done

OPTIND=1
while getopts ":d:a:p:l:I:U:t:v:" opt; do
  case "$opt" in
    d) DOWNLOAD_SCRIPTS="$OPTARG" ;;
    a) ARGUMENTS="$OPTARG" ;;
    p) PRODUCTION_INSTALL="$OPTARG" ;;
    l) LOCAL_INSTALL="$OPTARG" ;;           # kept for compatibility if used as -l <val>
    I) LOCAL_INSTALL="$OPTARG" ;;           # -lI
    U) LOCAL_UPDATE="$OPTARG" ;;
    t) TEST_REPO_ENABLE="$OPTARG" ;;
    v) VER="$OPTARG" ;;
    \?) usage; exit 1 ;;
  esac
done
shift $((OPTIND-1))

# -------- helpers -------------------------------------------------------------
require_cmd() { command -v "$1" >/dev/null 2>&1 || { error "Command '$1' not found"; exit 127; }; }

os_id_like() {
  # prints normalized id/id_like (debian|ubuntu|rhel|centos|amzn)
  local id=""
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
    case "$id" in
      debian|ubuntu) printf "debian\n";;
      rhel|centos|rocky|almalinux) printf "rhel\n";;
      amzn) printf "amzn\n";;
      *) printf "%s\n" "$id";;
    esac
  fi
}

rhel_major() {
  local rel=""
  if [[ -f /etc/redhat-release ]]; then
    rel=$(sed -E 's/[^0-9]*([0-9]+).*/\1/' /etc/redhat-release || true)
  fi
  printf "%s\n" "${rel:-0}"
}

# -------- checks --------------------------------------------------------------
check_hw() {
  require_cmd nproc
  require_cmd free
  local cpu ram
  cpu=$(nproc)
  ram=$(free -h | awk '/^Mem:/ {print $2 " total, " $7 " free"}')
  info "CPU cores: ${cpu}"
  info "Memory: ${ram}"
}

# -------- prepare VM ----------------------------------------------------------
prepare_vm() {
  local os; os="$(os_id_like)"
  info "Detected OS family: ${os}"

  if [[ "$os" == "debian" ]]; then
    require_cmd apt-get
    if [[ "${TEST_REPO_ENABLE}" == "true" ]]; then
      echo "deb [trusted=yes] https://s3.eu-west-1.amazonaws.com/repo-doc-onlyoffice-com/repo/debian stable ${VER}" \
        | sudo tee /etc/apt/sources.list.d/onlyoffice-dev.list >/dev/null
    fi
    if [[ -f /etc/os-release ]]; then
      . /etc/os-release
      if [[ "${ID:-}" == "debian" ]]; then
        sudo apt-get remove -y postfix || true
        ok "PREPARE_VM: Postfix removed"
      fi
    fi
  elif [[ "$os" == "rhel" || "$os" == "amzn" ]]; then
    require_cmd yum-config-manager || true
    local rev; rev="$(rhel_major)"
    if [[ "$rev" != "10" ]]; then
      if [[ "$rev" =~ ^9 ]]; then
        if command -v update-crypto-policies >/dev/null 2>&1; then
          sudo update-crypto-policies --set LEGACY || true
          ok "PREPARE_VM: sha1 gpg key check enabled"
        fi
        sudo tee /etc/yum.repos.d/centos-stream-9.repo >/dev/null <<'EOF'
[centos9s-baseos]
name=CentOS Stream 9 - BaseOS
baseurl=http://mirror.stream.centos.org/9-stream/BaseOS/x86_64/os/
enabled=1
gpgcheck=0

[centos9s-appstream]
name=CentOS Stream 9 - AppStream
baseurl=http://mirror.stream.centos.org/9-stream/AppStream/x86_64/os/
enabled=1
gpgcheck=0
EOF
      else
        if [[ -f /etc/redhat-release ]] && grep -qi 'centos' /etc/redhat-release; then
          sudo sed -i 's|^mirrorlist=|#&|; s|^#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|' /etc/yum.repos.d/CentOS-* || true
        elif [[ "$rev" == "8" ]]; then
          sudo tee /etc/yum.repos.d/CentOS-Vault.repo >/dev/null <<'EOF'
[BaseOS]
name=CentOS-8 - Base
baseurl=http://vault.centos.org/8.5.2111/BaseOS/x86_64/os/
gpgcheck=0
enabled=1
[AppStream]
name=CentOS-8 - AppStream
baseurl=http://vault.centos.org/8.5.2111/AppStream/x86_64/os/
gpgcheck=0
enabled=1
EOF
        fi
      fi
      if [[ "${TEST_REPO_ENABLE}" == "true" ]]; then
        sudo yum-config-manager --add-repo \
          "https://s3.eu-west-1.amazonaws.com/repo-doc-onlyoffice-com/repo/centos/onlyoffice-dev-${VER}.repo" || true
      fi
    fi
  else
    warn "Unknown OS family: ${os}; skipping repo tweaks"
  fi

  # Clean home folder carefully
  if [[ -d /home/vagrant ]]; then
    sudo find /home/vagrant -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  fi
  if [[ -d /tmp/docs ]]; then
    sudo mv /tmp/docs/* /home/vagrant/ 2>/dev/null || true
  fi

  echo '127.0.0.1 host4test' | sudo tee -a /etc/hosts >/dev/null
  ok "PREPARE_VM: Hostname mapping added"
}

# -------- install docs --------------------------------------------------------
install_docs() {
  if ! command -v curl >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -y && sudo apt-get install -y curl
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y curl
    elif command -v yum >/dev/null 2>&1; then
      sudo yum install -y curl
    else
      error "No supported package manager found to install curl"
      exit 1
    fi
  fi

  if [[ "${DOWNLOAD_SCRIPTS}" == "true" ]]; then
    info "Downloading docs-install.sh ..."
    curl -fsSLo docs-install.sh https://download.onlyoffice.com/docs/docs-install.sh
    chmod +x docs-install.sh
  fi

  if [[ ! -x ./docs-install.sh ]]; then
    error "docs-install.sh not found or not executable in current directory"
    exit 1
  fi

  info "Running docs-install.sh ${ARGUMENTS}"
  # auto-answers: N, Y, Y, Y (preserving your original flow)
  printf "N\nY\nY\nY\n" | bash ./docs-install.sh ${ARGUMENTS:-} || {
    error "docs-install.sh exited with non-zero code"
    exit 1
  }
  ok "Installation finished"
}

# -------- healthcheck HTTP with retries ---------------------------------------
healthcheck_http() {
  local url="${1:-http://localhost/healthcheck}"
  local tries="${2:-24}"     # total ~ 2 minutes (24 * 5s)
  local delay="${3:-5}"

  require_cmd curl
  info "Waiting for healthcheck at ${url} ..."
  for ((i=1; i<=tries; i++)); do
    if out="$(curl -kfsS "${url}" 2>/dev/null)" && [[ "${out}" == "true" ]]; then
      ok "Healthcheck passed"
      return 0
    fi
    printf "."
    sleep "$delay"
  done
  printf "\n"
  error "Healthcheck failed after $((tries*delay))s"
  return 1
}

# -------- systemd checks & logs -----------------------------------------------
services_logs() {
  shopt -s nullglob
  local log_root="/var/log/onlyoffice/documentserver"
  local dirs=( "docservice" "converter" "metrics" )

  for service in "${SERVICES_SYSTEMD[@]}"; do
    info "journalctl -u ${service}"
    journalctl -u "${service}" --no-pager -n 200 || true
  done

  for d in "${dirs[@]}"; do
    local path="${log_root}/${d}"
    if [[ -d "$path" ]]; then
      warn "Logs for ${d}"
      for file in "$path"/*; do
        ok "File: ${file##*/}"
        # tail to keep output sane
        tail -n +1 "$file" || true
      done
    else
      warn "No directory: ${path}"
    fi
  done
}

healthcheck_systemd_services() {
  local failed=0
  for service in "${SERVICES_SYSTEMD[@]}"; do
    if systemctl is-active --quiet "${service}"; then
      ok "Service ${service} is running"
    else
      error "Service ${service} is NOT running"
      failed=1
    fi
  done
  return "$failed"
}

# -------- main ----------------------------------------------------------------
main() {
  info "Starting ONLYOFFICE Docs installation & checks"
  check_hw
  prepare_vm
  install_docs
  healthcheck_http "http://localhost/healthcheck" 24 5
  services_logs
  if ! healthcheck_systemd_services; then
    warn "ATTENTION: Some services are not running"
    exit 1
  fi
  ok "All checks passed"
}

main "$@"
