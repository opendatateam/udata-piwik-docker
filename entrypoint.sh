#!/bin/bash
set -e
if [ ! -e /var/www/html/config/config.ini.php ]; then
  php /piwik-cli-setup/install.php
  chown -R www-data /var/www/html
fi
exec "$@"
