#!/bin/bash
set -euo pipefail

cat<<'EOF'

#######################################
#  INSTALL PREREQUISITES (EL10-ready)
#######################################

EOF

# --- Detect distro/release if not provided ---
REV="${REV:-$(rpm -E %rhel 2>/dev/null || ( . /etc/os-release && echo "${VERSION_ID%%.*}" ))}"
DIST="${DIST:-$(rpm -qa '*-release' --qf '%{NAME}\n' | head -n1 | sed 's/-release.*//')}"

# Clean caches
yum clean all -y

# Base tooling
yum -y install yum-utils dnf-plugins-core curl jq

# Track updates availability (best-effort)
PSQLExitCode=0
exitCode=0
{ yum check-update postgresql       >/dev/null 2>&1; PSQLExitCode=$?; } || true
if [[ -n "${DIST}" ]]; then
  { yum check-update "${DIST}"*-release >/dev/null 2>&1; exitCode=$?; } || true
fi

UPDATE_AVAILABLE_CODE=100
if [[ $exitCode -eq $UPDATE_AVAILABLE_CODE ]]; then
  # Ваши функции/строки вывода, если они определены во внешнем окружении
  type res_unsupported_version >/dev/null 2>&1 && res_unsupported_version || true
  [[ -n "${RES_UNSUPPORTED_VERSION:-}" ]] && echo "$RES_UNSUPPORTED_VERSION"
  [[ -n "${RES_SELECT_INSTALLATION:-}" ]] && echo "$RES_SELECT_INSTALLATION"
  [[ -n "${RES_ERROR_REMINDER:-}"    ]] && echo "$RES_ERROR_REMINDER"
  [[ -n "${RES_QUESTIONS:-}"         ]] && echo "$RES_QUESTIONS"
  type read_unsupported_installation >/dev/null 2>&1 && read_unsupported_installation || true
fi

# EL9 legacy quirk
if [[ "${REV}" == "9" ]]; then
  update-crypto-policies --set DEFAULT:SHA1 || true
  yum -y install xorg-x11-font-utils || true
fi

# --- EPEL ---
yum -y install "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${REV}.noarch.rpm" || true
yum -y install epel-release || true

# --- RabbitMQ repo (packagecloud) ---
# Временно используем dist=9 (официального el10 может не быть)
curl -fsSL https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.rpm.sh \
  | os=el dist=9 bash

# Сравнение ui_from_repo для rabbitmq-server (требует repoquery из dnf-plugins-core)
if rpm -q rabbitmq-server >/dev/null 2>&1; then
  inst_repo="$(repoquery --installed rabbitmq-server --qf '%{ui_from_repo}' 2>/dev/null | sed 's/@//')"
  avail_repo="$(repoquery rabbitmq-server --qf='%{ui_from_repo}' 2>/dev/null || true)"
  if [[ -n "$inst_repo" && -n "$avail_repo" && "$inst_repo" != "$avail_repo" ]]; then
    type res_rabbitmq_update >/dev/null 2>&1 && res_rabbitmq_update || true
    [[ -n "${RES_RABBITMQ_VERSION:-}"      ]] && echo "$RES_RABBITMQ_VERSION"
    [[ -n "${RES_RABBITMQ_REMINDER:-}"     ]] && echo "$RES_RABBITMQ_REMINDER"
    [[ -n "${RES_RABBITMQ_INSTALLATION:-}" ]] && echo "$RES_RABBITMQ_INSTALLATION"
    type read_rabbitmq_update >/dev/null 2>&1 && read_rabbitmq_update || true
  fi
fi

# --- Erlang repo ---
# ARM/aarch64 — подтягиваем последний релиз напрямую; иначе — repo script (dist=9 как временный фоллбэк)
ARCH="$(uname -m)"
if [[ "$ARCH" =~ (arm|aarch) ]] && [[ "$REV" -gt 7 ]]; then
  ERLANG_LATEST_URL="$(curl -fsSL https://api.github.com/repos/rabbitmq/erlang-rpm/releases \
    | jq -r --arg rev "$REV" '.[] | .assets[]? | select(.name | test("erlang-[0-9\\.]+-1\\.el" + $rev + "\\.aarch64\\.rpm$")) | .browser_download_url' \
    | head -n1)"
  if [[ -n "$ERLANG_LATEST_URL" ]]; then
    yum -y install "$ERLANG_LATEST_URL"
  else
    curl -fsSL https://packagecloud.io/install/repositories/rabbitmq/erlang/script.rpm.sh | os=el dist=9 bash
  fi
else
  curl -fsSL https://packagecloud.io/install/repositories/rabbitmq/erlang/script.rpm.sh | os=el dist=9 bash
fi

# --- nginx.org repo (создаём, но можно не использовать) ---
cat > /etc/yum.repos.d/nginx.repo <<END
[nginx-stable]
name=nginx stable repo
baseurl=https://nginx.org/packages/centos/${REV}/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
END

# ===== EL10: Redis -> Valkey =====
if [[ "${REV:-0}" -ge 10 ]]; then
  REDIS_PKG="valkey"
  REDIS_CONF="/etc/valkey/valkey.conf"
  REDIS_SVC="valkey"
else
  REDIS_PKG="redis"
  REDIS_CONF="/etc/redis.conf"
  REDIS_SVC="redis"
fi

# --- Core packages ---
yum -y install \
  expect \
  nano \
  postgresql \
  postgresql-server \
  rabbitmq-server \
  "${REDIS_PKG}" \
  policycoreutils-python-utils

# --- Xvfb (только если нужно и отсутствует). Временный фоллбэк с CS9 ---
if [[ "${REV}" == "10" ]] && ! rpm -q xorg-x11-server-Xvfb >/dev/null 2>&1; then
  ARCH_RPM="$(rpm -E '%{_arch}')"
  XORG_VER="1.20.11-27.el9"
  echo "==> EL10: ставлю Xvfb/XScrnSaver из CentOS Stream 9 (временное решение)"
  dnf -y --nogpgcheck install \
    "https://mirror.stream.centos.org/9-stream/AppStream/${ARCH_RPM}/os/Packages/xorg-x11-server-common-${XORG_VER}.${ARCH_RPM}.rpm" \
    "https://mirror.stream.centos.org/9-stream/AppStream/${ARCH_RPM}/os/Packages/xorg-x11-server-Xvfb-${XORG_VER}.${ARCH_RPM}.rpm" \
    "https://mirror.stream.centos.org/9-stream/AppStream/${ARCH_RPM}/os/Packages/libXScrnSaver-1.2.3-10.el9.${ARCH_RPM}.rpm" || true
  # cabextract — нативно из EPEL10
  dnf -y --enablerepo=epel install cabextract || true
fi

# --- PostgreSQL upgrade/initdb ---
if [[ $PSQLExitCode -eq $UPDATE_AVAILABLE_CODE ]]; then
  yum -y install postgresql-upgrade || true
  postgresql-setup --upgrade || true
fi

postgresql-setup --initdb || true

# Harden PG auth to SCRAM
if [[ -f /var/lib/pgsql/data/pg_hba.conf ]]; then
  sed -E -i "s/(host\s+(all|replication)\s+all\s+(127\.0\.0\.1\/32|::1\/128)\s+)(ident|trust|md5)/\1scram-sha-256/" /var/lib/pgsql/data/pg_hba.conf
fi
if [[ -f /var/lib/pgsql/data/postgresql.conf ]]; then
  sed -i "s/^#\?password_encryption = .*/password_encryption = 'scram-sha-256'/" /var/lib/pgsql/data/postgresql.conf
fi

# SELinux: allow httpd permissive (если требуется интеграция)
semanage permissive -a httpd_t || true

# --- Key-Value store tune (Redis/Valkey) ---
if [[ -f "$REDIS_CONF" ]]; then
  sed -i "s/^bind .*/bind 127.0.0.1/" "$REDIS_CONF" || true
  sed -r -i "/^save\s[0-9]+/d" "$REDIS_CONF" || true
fi

# --- Service list (for later use) ---
package_services="rabbitmq-server postgresql ${REDIS_SVC}"

# (опционально можно сразу enable/ стартовать)
# systemctl enable --now rabbitmq-server postgresql "${REDIS_SVC}"

echo "==> Done. Installed services: ${package_services}"
