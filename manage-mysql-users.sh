#!/usr/bin/env bash
# manage-mysql-users.sh — safe MySQL/MariaDB user management from the CLI.
#
# Commands:
#   list [--host HOST]
#   create USER --password [PASS] [--host HOST] [--privileges "db.*:SELECT,INSERT"] [--yes]
#   drop USER [--host HOST] [--yes]
#   reset-password USER [--password PASS] [--host HOST]
#
# Notes:
# - Credentials come from ~/.my.cnf (preferred) or the mysql client defaults;
#   this script never asks you to paste a root password on the command line.
# - Usernames/hosts are validated against [A-Za-z0-9_.-] so they cannot
#   break out of the quoted SQL. Privilege lists are allow-listed.
# - Passwords are generated with openssl when --password is omitted.
# - Drop and create are destructive/overwriting: both refuse to run without
#   --yes, and drop always prints the grants it is about to remove first.
set -euo pipefail

MYSQL_BIN="${MYSQL_BIN:-mysql}"
ALLOWED_PRIVS="SELECT INSERT UPDATE DELETE CREATE DROP INDEX ALTER CREATE TEMPORARY TABLES LOCK TABLES EXECUTE CREATE VIEW SHOW VIEW CREATE ROUTINE ALTER ROUTINE EVENT TRIGGER REFERENCES GRANT OPTION"

usage() {
    sed -n '2,13p' "$0"
    exit "${1:-0}"
}

die() { echo "ERROR: $*" >&2; exit 1; }

# Validate a MySQL identifier component (username or host, not a DB name with *).
valid_name() { [[ "$1" =~ ^[A-Za-z0-9_.\-]+$ ]]; }

# Validate a privileges spec like "shop.*:SELECT,INSERT" or "ALL" (whole server).
# Prints the SQL GRANT fragment, or dies. Database names allow _ and alphanumerics.
grant_sql() {
    local spec="$1" user="$2" host="$3"
    if [[ "$spec" == "ALL" ]]; then
        echo "GRANT ALL PRIVILEGES ON *.* TO '${user}'@'${host}' WITH GRANT OPTION"
        return 0
    fi
    local db="${spec%%:*}" privs="${spec#*:}"
    [[ "$db" =~ ^[A-Za-z0-9_]+(\.\*)?$ ]] || die "bad database spec: $db (use dbname or dbname.*)"
    [[ "$db" == *.* ]] || db="${db}.*"
    local out="" p
    IFS=',' read -ra parts <<< "$privs"
    for p in "${parts[@]}"; do
        p="$(echo "$p" | tr 'a-z' 'A-Z' | tr -d ' ')"
        [[ " $ALLOWED_PRIVS " == *" $p "* ]] || die "privilege not allowed: $p"
        out+="${out:+,}$p"
    done
    [[ -n "$out" ]] || die "no privileges given"
    echo "GRANT $out ON $db TO '${user}'@'${host}'"
}

run_mysql() { "$MYSQL_BIN" --batch --skip-column-names -e "$1"; }

cmd_list() {
    local host="%"
    while [[ $# -gt 0 ]]; do case "$1" in
        --host) host="$2"; shift 2 ;;
        *) usage 1 ;;
    esac; done
    valid_name "$host" || die "invalid host: $host"
    run_mysql "SELECT CONCAT(User, '@', Host) FROM mysql.user WHERE Host = '${host}' ORDER BY User;"
}

cmd_create() {
    local user="" host="%" password="" privs="" yes=0
    [[ $# -ge 1 ]] || usage 1
    user="$1"; shift
    while [[ $# -gt 0 ]]; do case "$1" in
        --host) host="$2"; shift 2 ;;
        --password) password="$2"; shift 2 ;;
        --privileges) privs="$2"; shift 2 ;;
        --yes) yes=1; shift ;;
        *) usage 1 ;;
    esac; done
    valid_name "$user" || die "invalid username: $user"
    valid_name "$host" || die "invalid host: $host"
    [[ -n "$privs" ]] || die "--privileges is required (e.g. --privileges 'shop.*:SELECT,INSERT' or ALL)"
    [[ "$yes" == 1 ]] || die "refusing to create/overwrite without --yes (create replaces an existing user of the same name)"
    [[ -n "$password" ]] || password="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
    local grant
    grant="$(grant_sql "$privs" "$user" "$host")"
    # Escape single quotes in the password for the SQL literal (rare, but safe).
    local esc_pass="${password//\'/\'\'}"
    run_mysql "CREATE USER IF NOT EXISTS '${user}'@'${host}' IDENTIFIED BY '${esc_pass}'; ALTER USER '${user}'@'${host}' IDENTIFIED BY '${esc_pass}'; ${grant}; FLUSH PRIVILEGES;"
    echo "Created ${user}@${host}"
    echo "Password: ${password}"
    echo "Store it now — it is not printed again."
}

cmd_drop() {
    local user="" host="%" yes=0
    [[ $# -ge 1 ]] || usage 1
    user="$1"; shift
    while [[ $# -gt 0 ]]; do case "$1" in
        --host) host="$2"; shift 2 ;;
        --yes) yes=1; shift ;;
        *) usage 1 ;;
    esac; done
    valid_name "$user" || die "invalid username: $user"
    valid_name "$host" || die "invalid host: $host"
    echo "Current grants for ${user}@${host}:"
    run_mysql "SHOW GRANTS FOR '${user}'@'${host}';" || die "user ${user}@${host} does not exist"
    [[ "$yes" == 1 ]] || die "refusing to drop without --yes"
    run_mysql "DROP USER '${user}'@'${host}'; FLUSH PRIVILEGES;"
    echo "Dropped ${user}@${host}"
}

cmd_reset_password() {
    local user="" host="%" password=""
    [[ $# -ge 1 ]] || usage 1
    user="$1"; shift
    while [[ $# -gt 0 ]]; do case "$1" in
        --host) host="$2"; shift 2 ;;
        --password) password="$2"; shift 2 ;;
        *) usage 1 ;;
    esac; done
    valid_name "$user" || die "invalid username: $user"
    valid_name "$host" || die "invalid host: $host"
    [[ -n "$password" ]] || password="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
    local esc_pass="${password//\'/\'\'}"
    run_mysql "ALTER USER '${user}'@'${host}' IDENTIFIED BY '${esc_pass}'; FLUSH PRIVILEGES;"
    echo "Password reset for ${user}@${host}"
    echo "New password: ${password}"
}

[[ $# -ge 1 ]] || usage 1
cmd="$1"; shift
case "$cmd" in
    list) cmd_list "$@" ;;
    create) cmd_create "$@" ;;
    drop) cmd_drop "$@" ;;
    reset-password) cmd_reset_password "$@" ;;
    -h|--help) usage 0 ;;
    *) usage 1 ;;
esac
