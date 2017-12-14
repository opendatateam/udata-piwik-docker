FROM php:7-apache

ENV PIWIK_VERSION 3.2.0

RUN docker-php-ext-install -j$(nproc) pdo_mysql

RUN curl -fsSL -o piwik.tar.gz \
      "https://builds.piwik.org/piwik-${PIWIK_VERSION}.tar.gz" \
 && tar -xzf piwik.tar.gz -C /tmp/ \
 && rm piwik.tar.gz

COPY php.ini /usr/local/etc/php/php.ini

RUN cp -a /tmp/piwik/* /var/www/html/
RUN chown -R www-data /var/www/html
ADD piwik-cli-setup /piwik-cli-setup
ADD reset.php /var/www/html/

ADD entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]
