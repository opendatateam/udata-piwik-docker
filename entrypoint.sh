#!/bin/bash

## MYSQL ##


DATADIR=/var/lib/mysql
COMMAND=mysqld

set -eo pipefail
shopt -s nullglob

# skip setup if they want an option that stops mysqld
wantHelp=
for arg; do
	case "$arg" in
		-'?'|--help|--print-defaults|-V|--version)
			wantHelp=1
			break
			;;
	esac
done

_check_config() {
	toRun=( "$COMMAND" --verbose --help )
	if ! errors="$("${toRun[@]}" 2>&1 >/dev/null)"; then
		cat >&2 <<-EOM
			ERROR: mysqld failed while attempting to check config
			command was: "${toRun[*]}"
			$errors
		EOM
		exit 1
	fi
}

# Fetch value from server config
# We use mysqld --verbose --help instead of my_print_defaults because the
# latter only show values present in config files, and not server defaults
_get_config() {
	local conf="$1"; shift
	"$COMMAND" --verbose --help --log-bin-index="$(mktemp -u)" 2>/dev/null | awk '$1 == "'"$conf"'" { print $2; exit }'
}

if [ ! -d "$DATADIR/mysql" ]; then
	if [ -z "$MYSQL_ROOT_PASSWORD" -a -z "$MYSQL_ALLOW_EMPTY_PASSWORD" -a -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
		echo >&2 'error: database is uninitialized and password option is not specified '
		echo >&2 '  You need to specify one of MYSQL_ROOT_PASSWORD, MYSQL_ALLOW_EMPTY_PASSWORD and MYSQL_RANDOM_ROOT_PASSWORD'
		exit 1
	fi

	mkdir -p "$DATADIR"

	echo 'Initializing database'
	"$COMMAND" --initialize-insecure
	echo 'Database initialized'

	if command -v mysql_ssl_rsa_setup > /dev/null && [ ! -e "$DATADIR/server-key.pem" ]; then
		# https://github.com/mysql/mysql-server/blob/23032807537d8dd8ee4ec1c4d40f0633cd4e12f9/packaging/deb-in/extra/mysql-systemd-start#L81-L84
		echo 'Initializing certificates'
		mysql_ssl_rsa_setup --datadir="$DATADIR"
		echo 'Certificates initialized'
	fi

	SOCKET="$(_get_config 'socket' "$COMMAND")"
	"$COMMAND" --user=root --skip-networking --socket="${SOCKET}" &
	pid="$!"

	mysql=( mysql --protocol=socket -uroot -hlocalhost --socket="${SOCKET}" )

	for i in {30..0}; do
		if echo 'SELECT 1' | "${mysql[@]}" &> /dev/null; then
			break
		fi
		echo 'MySQL init process in progress...'
		sleep 1
	done
	if [ "$i" = 0 ]; then
		echo >&2 'MySQL init process failed.'
		exit 1
	fi

	if [ -z "$MYSQL_INITDB_SKIP_TZINFO" ]; then
		# sed is for https://bugs.mysql.com/bug.php?id=20545
		mysql_tzinfo_to_sql /usr/share/zoneinfo | sed 's/Local time zone must be set--see zic manual page/FCTY/' | "${mysql[@]}" mysql
	fi

	if [ ! -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
		export MYSQL_ROOT_PASSWORD="$(pwgen -1 32)"
		echo "GENERATED ROOT PASSWORD: $MYSQL_ROOT_PASSWORD"
	fi

	rootCreate=
	# default root to listen for connections from anywhere
	if [ ! -z "$MYSQL_ROOT_HOST" -a "$MYSQL_ROOT_HOST" != 'localhost' ]; then
		# no, we don't care if read finds a terminating character in this heredoc
		# https://unix.stackexchange.com/questions/265149/why-is-set-o-errexit-breaking-this-read-heredoc-expression/265151#265151
		read -r -d '' rootCreate <<-EOSQL || true
			CREATE USER 'root'@'${MYSQL_ROOT_HOST}' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}' ;
			GRANT ALL ON *.* TO 'root'@'${MYSQL_ROOT_HOST}' WITH GRANT OPTION ;
		EOSQL
	fi

	"${mysql[@]}" <<-EOSQL
		-- What's done in this file shouldn't be replicated
		--  or products like mysql-fabric won't work
		SET @@SESSION.SQL_LOG_BIN=0;
		DELETE FROM mysql.user WHERE user NOT IN ('mysql.session', 'mysql.sys', 'root') OR host NOT IN ('localhost') ;
		SET PASSWORD FOR 'root'@'localhost'=PASSWORD('${MYSQL_ROOT_PASSWORD}') ;
		GRANT ALL ON *.* TO 'root'@'localhost' WITH GRANT OPTION ;
		${rootCreate}
		DROP DATABASE IF EXISTS test ;
		FLUSH PRIVILEGES ;
	EOSQL

	if [ ! -z "$MYSQL_ROOT_PASSWORD" ]; then
		mysql+=( -p"${MYSQL_ROOT_PASSWORD}" )
	fi

	if [ "$MYSQL_DATABASE" ]; then
		echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` ;" | "${mysql[@]}"
		mysql+=( "$MYSQL_DATABASE" )
	fi

	if [ "$MYSQL_USER" -a "$MYSQL_PASSWORD" ]; then
		echo "CREATE USER '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD' ;" | "${mysql[@]}"

		if [ "$MYSQL_DATABASE" ]; then
			echo "GRANT ALL ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_USER'@'%' ;" | "${mysql[@]}"
		fi

		echo 'FLUSH PRIVILEGES ;' | "${mysql[@]}"
	fi

	if ! kill -s TERM "$pid" || ! wait "$pid"; then
		echo >&2 'MySQL init process failed.'
		exit 1
	fi

	echo
	echo 'MySQL init process done. Ready for start up.'
	echo
fi

$COMMAND --user=root &

## INSTALL PIWIK ##

if [ ! -e /var/www/html/config/config.ini.php ]; then
  php /piwik-cli-setup/install.php
  chown -R www-data /var/www/html
fi

## LAUNCH SERVICES ##

apache2-foreground
