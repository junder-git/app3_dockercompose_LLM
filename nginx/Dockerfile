# nginx/Dockerfile - With redis2 module for direct Redis access

FROM nginx:alpine

# Install dependencies for building nginx modules
RUN apk add --no-cache \
    nginx-module-njs \
    curl \
    build-base \
    pcre-dev \
    zlib-dev \
    openssl-dev \
    git

# Build and install redis2 module
WORKDIR /tmp
RUN git clone https://github.com/openresty/redis2-nginx-module.git && \
    wget http://nginx.org/download/nginx-$(nginx -v 2>&1 | grep -o '[0-9.]*').tar.gz && \
    tar -xzf nginx-*.tar.gz && \
    cd nginx-* && \
    ./configure \
        --add-dynamic-module=/tmp/redis2-nginx-module \
        --with-compat && \
    make modules && \
    cp objs/ngx_http_redis2_module.so /usr/lib/nginx/modules/

# Clean up build dependencies
RUN apk del build-base pcre-dev zlib-dev openssl-dev git && \
    rm -rf /tmp/*

# Set working directory
WORKDIR /usr/share/nginx/html

# Remove default NGINX configuration and content
RUN rm /etc/nginx/conf.d/default.conf && \
    rm /etc/nginx/nginx.conf && \
    rm -rf /usr/share/nginx/html/*

# Copy NGINX configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Create directories first
RUN mkdir -p /etc/nginx/njs && \
    mkdir -p /usr/share/nginx/html/css && \
    mkdir -p /usr/share/nginx/html/js/lib && \
    mkdir -p /usr/share/nginx/html/assets && \
    mkdir -p /var/cache/nginx && \
    mkdir -p /var/log/nginx

# Download required libraries AFTER creating directories
RUN curl -o /usr/share/nginx/html/js/lib/jquery.min.js https://code.jquery.com/jquery-3.7.1.min.js && \
    curl -o /usr/share/nginx/html/js/lib/bootstrap.min.js https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js && \
    curl -o /usr/share/nginx/html/css/bootstrap.min.css https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css

# Copy server-side JavaScript modules
COPY njs/ /etc/nginx/njs/

# Copy static files
COPY static/ /usr/share/nginx/html/

# Set permissions
RUN chmod -R 755 /usr/share/nginx/html/ && \
    chmod -R 755 /etc/nginx/njs/ && \
    chown -R nginx:nginx /usr/share/nginx/html/ && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]