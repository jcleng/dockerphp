# PHP 8.1 (ZTS) with the CVE-2026-109618 / CVE-2026-109619 fix applied.
#
# The php:8.1-zts base image ships the official PHP 8.1.34 release, which is still
# affected by:
#   CVE-2026-109618 (GHSA-w8hw-w9fx-j79w) - state corruption via bailout
#   CVE-2026-109619 (GHSA-6wmf-4rv5-p3rp)
# Both are fixed on the php-src branch PHP-8.1-CVE-2026-109618-109619, so PHP is
# compiled from that branch here and the usual extensions are installed on top of it.
#
# The build reuses the exact configure flags of the official php:8.1-zts image, so
# the resulting binary stays ABI/ini compatible with the base image
# (same $PHP_INI_DIR, same extension dir, same opcache/sodium modules).

FROM php:8.1-zts

ENV TZ=Asia/Shanghai \
    PHP_SRC_REPO=https://github.com/php/php-src.git \
    PHP_SRC_BRANCH=PHP-8.1-CVE-2026-109618-109619

# The commit the branch pointed at when this Dockerfile was written. The build fails
# if the branch moved, so that a new (unreviewed) commit is never built silently.
# Override with: --build-arg PHP_SRC_COMMIT=<sha>
ARG PHP_SRC_COMMIT=1d7dec178a094e6e75b229ce22754045f8c6070a
ENV PHP_SRC_COMMIT=${PHP_SRC_COMMIT}

ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/

# Build dependencies:
#   git/curl/wget/unzip      - fetch php-src, the extension installer and the PEAR installer
#   autoconf/re2c/bison      - php-src is a git checkout: "configure" and the
#                              re2c/bison generated parsers have to be created here
#   the *-dev packages        - the libraries PHP itself is linked against
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bison \
        ca-certificates \
        curl \
        git \
        libargon2-dev \
        libcurl4-openssl-dev \
        libonig-dev \
        libreadline-dev \
        libsodium-dev \
        libsqlite3-dev \
        libssl-dev \
        libxml2-dev \
        unzip \
        wget \
        xz-utils \
        zlib1g-dev \
    ; \
    rm -rf /var/lib/apt/lists/*

# 1) Fetch the patched php-src and make sure it is the expected commit.
RUN set -eux; \
    git clone --depth 1 --branch "$PHP_SRC_BRANCH" "$PHP_SRC_REPO" /usr/src/php-src; \
    cd /usr/src/php-src; \
    actual="$(git rev-parse HEAD)"; \
    if [ "$actual" != "$PHP_SRC_COMMIT" ]; then \
        echo >&2 "### $PHP_SRC_BRANCH is at $actual, but this image is pinned to $PHP_SRC_COMMIT ###"; \
        echo >&2 "### rebuild with --build-arg PHP_SRC_COMMIT=$actual to pick up the new commit ###"; \
        exit 1; \
    fi; \
    echo "$actual" > /usr/src/php-src.commit; \
    git log -1 --format='%H %s' "$actual"

# 2) Keep a pristine copy of the patched sources in /usr/src/php.tar.xz.
#    docker-php-source / docker-php-ext-install build the bundled extensions
#    (opcache, gd, intl, ...) from that tarball, so they have to be patched as well.
RUN set -eux; \
    cd /usr/src/php-src; \
    rm -rf .git; \
    tar -cJf /usr/src/php.tar.xz -C /usr/src/php-src .; \
    ls -lh /usr/src/php.tar.xz

# 3) Compile PHP from the patched sources.
RUN set -eux; \
    cd /usr/src/php-src; \
    \
    export CFLAGS="$PHP_CFLAGS" CPPFLAGS="$PHP_CPPFLAGS" LDFLAGS="$PHP_LDFLAGS"; \
    \
    # php-src is a git checkout, so "configure" has to be generated first
    ./buildconf --force; \
    \
    gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
    debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
    if [ -d "/usr/include/$debMultiarch/curl" ]; then \
        rm -rf /usr/local/include/curl; \
        ln -sT "/usr/include/$debMultiarch/curl" /usr/local/include/curl; \
    fi; \
    ./configure \
        --build="$gnuArch" \
        --sysconfdir="${PHP_INI_DIR%/php}" \
        --with-config-file-path="$PHP_INI_DIR" \
        --with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
        \
        --enable-option-checking=fatal \
        \
        --with-mhash \
        --with-pic \
        --enable-ftp \
        --enable-mbstring \
        --enable-mysqlnd \
        --with-password-argon2 \
        --with-sodium=shared \
        --with-pdo-sqlite=/usr \
        --with-sqlite3=/usr \
        \
        --with-curl \
        --with-iconv \
        --with-openssl \
        --with-readline \
        --with-zlib \
        \
        --enable-phpdbg \
        --enable-phpdbg-readline \
        \
        --with-pear \
        \
        --with-libdir="lib/$debMultiarch" \
        --enable-embed \
        \
        --enable-zts \
        --disable-zend-signals \
        --enable-zend-max-execution-timers \
    ; \
    make -j"$(nproc)"; \
    make install; \
    find \
        /usr/local \
        -type f \
        -perm '/0111' \
        -exec sh -euxc ' \
            strip --strip-all "$@" || : \
        ' -- '{}' + \
    ; \
    cp -v php.ini-* "$PHP_INI_DIR/"; \
    cd /; \
    rm -rf /usr/src/php-src; \
    php --version

# 4) Re-enable the shared modules of the new build and make sure pecl is usable
#    (install-php-extensions needs it to install the PECL extensions).
RUN set -eux; \
    docker-php-ext-enable opcache; \
    docker-php-ext-enable sodium; \
    if ! command -v pecl >/dev/null; then \
        curl -fsSL -o /tmp/go-pear.phar https://pear.php.net/go-pear.phar; \
        php /tmp/go-pear.phar \
            -d "preferred_state=stable" \
            -d "pear_installer=bin" \
            -d "install_pear=bin" \
            -d "auto_discover=0" \
            install; \
        rm -f /tmp/go-pear.phar; \
    fi; \
    pecl channel-update pecl.php.net || true; \
    php --version; \
    php -m

# Pin Swoole to 5.0.3 (the version used by the original project image) to keep the
# runtime baseline stable. Swoole 5.x does not include the io_uring file-async path
# that breaks coroutine file reads inside Docker's default seccomp profile.
RUN set -eux; \
    chmod +x /usr/local/bin/install-php-extensions; \
    install-php-extensions \
    amqp \
    apcu \
    bcmath \
    bz2 \
    calendar \
    decimal \
    enchant \
    event \
    exif \
    gd \
    gettext \
    gmp \
    igbinary \
    imagick \
    intl \
    lzf \
    memcached \
    mongodb \
    msgpack \
    mysqli \
    opcache \
    pcntl \
    pdo_mysql \
    pdo_pgsql \
    pgsql \
    redis \
    sockets \
    swoole-5.0.3 \
    sysvmsg \
    sysvsem \
    sysvshm \
    tidy \
    timezonedb \
    uuid \
    xlswriter \
    xsl \
    yac \
    yaml \
    zip \
    parallel

# Install Composer (the project uses `composer install` / `composer dump-autoload`).
# Uses the official signed phar from getcomposer.org.
ENV COMPOSER_ALLOW_SUPERUSER=1
RUN set -eux; \
    curl -fsSL -o /tmp/composer-setup.php https://getcomposer.org/installer; \
    php /tmp/composer-setup.php --quiet --install-dir=/usr/local/bin --filename=composer; \
    rm -f /tmp/composer-setup.php; \
    composer --version
