#!/bin/bash

set -e

cat<<EOF

#######################################
#  INSTALL APP
#######################################

EOF

for SVC in $package_services; do
    systemctl start $SVC
    systemctl enable $SVC
done

if [ "$INSTALLATION_TYPE" = "COMMUNITY" ]; then
    ds_pkg_name="${package_sysname}-documentserver"
elif [ "$INSTALLATION_TYPE" = "ENTERPRISE" ]; then
    ds_pkg_name="${package_sysname}-documentserver-ee"
elif [ "$INSTALLATION_TYPE" = "DEVELOPER" ]; then
    ds_pkg_name="${package_sysname}-documentserver-de"
fi

if [ "$UPDATE" = "true" ] && [ "$DOCUMENT_SERVER_INSTALLED" = "true" ]; then
    ds_pkg_installed_name=$(rpm -qa --qf '%{NAME}\n' | grep ${package_sysname}-documentserver)
    if [ ${ds_pkg_installed_name} != ${ds_pkg_name} ]; then
        ${package_manager} -y remove ${ds_pkg_installed_name}
        DOCUMENT_SERVER_INSTALLED="false"
    else
        ${package_manager} -y update ${ds_pkg_installed_name}
    fi
fi

# === helper: repack DS RPM for EL10 by removing ICU files ===
install_ds_el10_without_icu() {
  set -euo pipefail

  local PM="${package_manager:-dnf}"

  # 1) инструменты для перепаковки
  $PM -y --setopt=install_weak_deps=False install rpm-build rpmdevtools cpio file rsync

  # 2) скачиваем оригинальный RPM из подключённого репозитория ONLYOFFICE
  local DL="/var/tmp/onlyoffice-dl"
  mkdir -p "$DL"
  $PM -y --setopt=install_weak_deps=False --downloadonly --downloaddir="$DL" install "${ds_pkg_name}"

  # 3) ищем скачанный RPM
  local SRC_RPM
  SRC_RPM="$(ls -1t "${DL}/${ds_pkg_name}"-*.x86_64.rpm | head -n1)"
  [[ -n "${SRC_RPM:-}" ]] || { echo "Не найден RPM ${ds_pkg_name}"; exit 1; }

  # 4) распаковываем payload и получаем список файлов
  local TMP="/tmp/oods-repack.$$"
  mkdir -p "${TMP}/orig" "${TMP}/rootfs"
  ( cd "${TMP}/orig" && rpm2cpio "${SRC_RPM}" | cpio -idmv )

  local FILELIST="${TMP}/files.txt"
  rpm -qlp "${SRC_RPM}" > "${FILELIST}"

  # 5) вырезаем только ICU-файлы из /usr/lib64
  local ICU_GLOB='^/usr/lib64/libicu.*\.so(\.|$)'
  grep -Ev "${ICU_GLOB}" "${FILELIST}" > "${TMP}/files.filtered"

  # переносим все остальные файлы в будущий BUILDROOT
  while read -r f; do
    [[ -z "$f" || "$f" == */ ]] && continue
    [[ "$f" =~ ^/usr/lib64/libicu.*\.so(\.|$) ]] && continue
    src="${TMP}/orig/$(echo "$f" | sed 's#^/##')"
    [[ -e "$src" ]] || continue
    install -d "${TMP}/rootfs$(dirname "$f")"
    if [[ -x "$src" ]]; then
      install -m 0755 "$src" "${TMP}/rootfs$f"
    else
      install -m 0644 "$src" "${TMP}/rootfs$f"
    fi
  done < "${TMP}/files.filtered"

  # 6) метаданные из исходного RPM
  local NAME VERSION RELEASE SUMMARY
  NAME="$(rpm -qp --queryformat '%{NAME}\n'     "${SRC_RPM}")"
  VERSION="$(rpm -qp --queryformat '%{VERSION}\n' "${SRC_RPM}")"
  RELEASE="$(rpm -qp --queryformat '%{RELEASE}\n' "${SRC_RPM}")"
  SUMMARY="$(rpm -qp --queryformat '%{SUMMARY}\n' "${SRC_RPM}")"

  # 7) готовим rpmbuild окружение
  rpmdev-setuptree
  local SPECDIR="$HOME/rpmbuild/SPECS"
  local BUILDROOT="$HOME/rpmbuild/BUILDROOT/${NAME}-${VERSION}-${RELEASE}.x86_64"
  mkdir -p "$SPECDIR" "$BUILDROOT"
  rsync -a "${TMP}/rootfs/" "${BUILDROOT}/"

  # 8) минимальный SPEC без ICU; на EL10 требуем системный libicu
  cat > "${SPECDIR}/${NAME}.spec" <<SPEC
Name:           ${NAME}
Version:        ${VERSION}
Release:        ${RELEASE}
Summary:        ${SUMMARY}
License:        as-is
BuildArch:      x86_64
%if 0%{?rhel} >= 10
Requires:       libicu >= 74
%endif

%description
Repacked ${NAME} without bundled ICU libraries to avoid file conflicts on EL10.

%install
mkdir -p %{buildroot}

%files
%defattr(-,root,root,-)
$(sed 's#^#/#' "${TMP}/files.filtered")

%post
/sbin/ldconfig >/dev/null 2>&1 || :
%postun
/sbin/ldconfig >/dev/null 2>&1 || :
SPEC

  # 9) собираем и устанавливаем перепакованный RPM
  rpmbuild -bb "${SPECDIR}/${NAME}.spec"
  local OUT_RPM
  OUT_RPM="$(ls -1t "$HOME/rpmbuild/RPMS/x86_64/${NAME}-${VERSION}-${RELEASE}.x86_64.rpm" | head -n1)"
  $PM -y --setopt=install_weak_deps=False install "${OUT_RPM}"

  # 10) уборка
  rm -rf "${TMP}" "${DL}"
}

if [ "$DOCUMENT_SERVER_INSTALLED" = "false" ]; then
    declare -x DS_PORT=${DS_PORT:-80}

    DS_RABBITMQ_HOST=localhost
    DS_RABBITMQ_USER=guest
    DS_RABBITMQ_PWD=guest

    DS_REDIS_HOST=localhost

    DS_COMMON_NAME=${DS_COMMON_NAME:-"ds"}

    DS_DB_HOST=localhost
    DS_DB_NAME=$DS_COMMON_NAME
    DS_DB_USER=$DS_COMMON_NAME
    DS_DB_PWD=$DS_COMMON_NAME

    declare -x JWT_ENABLED=${JWT_ENABLED:-true}
    declare -x JWT_SECRET=${JWT_SECRET:-$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)}
    declare -x JWT_HEADER=${JWT_HEADER:-AuthorizationJwt}

    if ! su - postgres -s /bin/bash -c "psql -lqt" | cut -d \| -f 1 | grep -q ${DS_DB_NAME}; then
        su - postgres -s /bin/bash -c "psql -c \"CREATE USER ${DS_DB_USER} WITH password '${DS_DB_PWD}';\""
        su - postgres -s /bin/bash -c "psql -c \"CREATE DATABASE ${DS_DB_NAME} OWNER ${DS_DB_USER};\""
    fi

    # === установка DS: на EL10 — репак без ICU, на остальных — обычная установка ===
    if [ "$(rpm -E %rhel)" -ge 10 ]; then
        install_ds_el10_without_icu
    else
        ${package_manager} -y --setopt=install_weak_deps=False install ${ds_pkg_name}
    fi

expect << EOF

    set timeout -1
    log_user 1

    spawn documentserver-configure.sh

    expect "Configuring database access..."

    expect -re "Host"
    send "\025$DS_DB_HOST\r"

    expect -re "Database name"
    send "\025$DS_DB_NAME\r"

    expect -re "User"
    send "\025$DS_DB_USER\r"

    expect -re "Password"
    send "\025$DS_DB_PWD\r"

    if { "${INSTALLATION_TYPE}" == "ENTERPRISE" || "${INSTALLATION_TYPE}" == "DEVELOPER" } {
        expect "Configuring redis access..."
        send "\025$DS_REDIS_HOST\r"
    }

    expect "Configuring AMQP access... "
    expect -re "Host"
    send "\025$DS_RABBITMQ_HOST\r"

    expect -re "User"
    send "\025$DS_RABBITMQ_USER\r"

    expect -re "Password"
    send "\025$DS_RABBITMQ_PWD\r"

    expect eof

EOF
    systemctl restart nginx
    systemctl enable nginx

    DOCUMENT_SERVER_INSTALLED="true"
fi

NGINX_ROOT_DIR="/etc/nginx"
NGINX_WORKER_PROCESSES=${NGINX_WORKER_PROCESSES:-$(grep processor /proc/cpuinfo | wc -l)}
NGINX_WORKER_CONNECTIONS=${NGINX_WORKER_CONNECTIONS:-$(ulimit -n)}

sed 's/^worker_processes.*/'"worker_processes ${NGINX_WORKER_PROCESSES};"'/' -i ${NGINX_ROOT_DIR}/nginx.conf
sed 's/worker_connections.*/'"worker_connections ${NGINX_WORKER_CONNECTIONS};"'/' -i ${NGINX_ROOT_DIR}/nginx.conf

if systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --zone=public --add-service=http
    firewall-cmd --permanent --zone=public --add-service=https
    firewall-cmd --permanent --zone=public --add-port=${DS_PORT:-80}/tcp
    firewall-cmd --reload
fi

systemctl restart nginx

echo ""
echo "$RES_INSTALL_SUCCESS"
echo "$RES_QUESTIONS"
echo ""
