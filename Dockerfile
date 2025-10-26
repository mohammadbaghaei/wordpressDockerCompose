FROM wordpress:php8.4-fpm

# Install required tools and dependencies
RUN set -eux; \
    apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    libzip-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libwebp-dev \
    libonig-dev \
    libxml2-dev \
    libicu-dev \
    && rm -rf /var/lib/apt/lists/*

# Configure GD with support for modern image formats
RUN docker-php-ext-configure gd \
    --with-freetype \
    --with-jpeg \
    --with-webp

# Install PHP extensions for WordPress optimization
RUN docker-php-ext-install -j$(nproc) \
    gd \
    mysqli \
    zip \
    opcache \
    exif \
    bcmath \
    intl

# Install Redis extension
RUN pecl install redis && docker-php-ext-enable redis

# Install ionCube Loader
RUN set -eux; \
    PHP_EXT_DIR=$(php -r "echo ini_get('extension_dir');"); \
    PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;"); \
    ARCH=$(uname -m); \
    \
    case "$ARCH" in \
    x86_64) IONCUBE_ARCH="x86-64" ;; \
    aarch64) IONCUBE_ARCH="aarch64" ;; \
    *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;; \
    esac; \
    \
    echo "📥 Downloading ionCube Loader for PHP ${PHP_VERSION} - ${IONCUBE_ARCH}..."; \
    curl -fsSL "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_${IONCUBE_ARCH}.tar.gz" -o /tmp/ioncube.tar.gz; \
    \
    tar xzf /tmp/ioncube.tar.gz -C /tmp; \
    LOADER_FILE="/tmp/ioncube/ioncube_loader_lin_${PHP_VERSION}.so"; \
    \
    if [ ! -f "$LOADER_FILE" ]; then \
    echo "❌ Loader file for PHP ${PHP_VERSION} not found!"; \
    ls -la /tmp/ioncube/; \
    exit 1; \
    fi; \
    \
    cp "$LOADER_FILE" "${PHP_EXT_DIR}/"; \
    echo "zend_extension=${PHP_EXT_DIR}/ioncube_loader_lin_${PHP_VERSION}.so" > /usr/local/etc/php/conf.d/00-ioncube.ini; \
    \
    rm -rf /tmp/ioncube*; \
    \
    echo "✅ Verifying ionCube Loader installation..."; \
    php -v | grep -i ioncube || (echo "❌ ionCube Loader is not installed!"; exit 1)

# PHP Configuration - OPcache optimization
RUN { \
    echo 'opcache.enable=1'; \
    echo 'opcache.memory_consumption=256'; \
    echo 'opcache.interned_strings_buffer=16'; \
    echo 'opcache.max_accelerated_files=10000'; \
    echo 'opcache.revalidate_freq=2'; \
    echo 'opcache.fast_shutdown=1'; \
    echo 'opcache.enable_cli=0'; \
    echo 'opcache.validate_timestamps=1'; \
    echo 'opcache.huge_code_pages=1'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini

# PHP Configuration - Performance tuning
RUN { \
    echo 'memory_limit=1024M'; \
    echo 'upload_max_filesize=1024M'; \
    echo 'post_max_size=1024M'; \
    echo 'max_execution_time=600'; \
    echo 'max_input_time=600'; \
    echo 'max_input_vars=3000'; \
    echo 'default_socket_timeout=600'; \
    } > /usr/local/etc/php/conf.d/wordpress-performance.ini

# PHP Configuration - Redis session handler (optional but recommended)
RUN { \
    echo 'session.save_handler=redis'; \
    echo 'session.save_path="tcp://redis:6379"'; \
    } > /usr/local/etc/php/conf.d/redis-session.ini

# PHP-FPM Configuration optimization
RUN { \
    echo '[www]'; \
    echo 'pm = dynamic'; \
    echo 'pm.max_children = 50'; \
    echo 'pm.start_servers = 10'; \
    echo 'pm.min_spare_servers = 5'; \
    echo 'pm.max_spare_servers = 20'; \
    echo 'pm.max_requests = 500'; \
    echo 'pm.process_idle_timeout = 10s'; \
    echo 'request_terminate_timeout = 600s'; \
    } > /usr/local/etc/php-fpm.d/zz-performance.conf

# Security: Disable dangerous PHP functions
# RUN { \
#     echo 'disable_functions=exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source'; \
#     } > /usr/local/etc/php/conf.d/security.ini

# Display installed extensions for verification
RUN echo "✅ Installed PHP extensions:" && php -m

# Display ionCube status
RUN echo "✅ ionCube Loader status:" && php -v | grep -i ioncube

# Display Redis status
RUN echo "✅ Redis extension status:" && php -m | grep -i redis

# Set correct permissions
RUN chown -R www-data:www-data /var/www/html

WORKDIR /var/www/html

CMD ["php-fpm"]