# nginx/Dockerfile - JWT workaround using OpenSSL for HMAC

FROM openresty/openresty:1.25.3.1-0-alpine-fat

# Install additional dependencies including OpenSSL for HMAC
RUN apk add --no-cache \
    curl \
    wget \
    openssl

# Set working directory
WORKDIR /usr/local/openresty/nginx/html

# Remove default configuration and content
RUN rm -f /etc/nginx/conf.d/default.conf 2>/dev/null || true && \
    rm -f /usr/local/openresty/nginx/conf/nginx.conf && \
    rm -rf /usr/local/openresty/nginx/html/*

# Create directories
RUN mkdir -p /usr/local/openresty/nginx/lua && \
    mkdir -p /usr/local/openresty/nginx/html/css && \
    mkdir -p /usr/local/openresty/nginx/html/js/lib && \
    mkdir -p /usr/local/openresty/nginx/html/assets && \
    mkdir -p /var/cache/nginx && \
    mkdir -p /var/log/nginx

# Download external libraries
RUN curl -o /usr/local/openresty/nginx/html/js/lib/jquery.min.js https://code.jquery.com/jquery-3.7.1.min.js && \
    curl -o /usr/local/openresty/nginx/html/js/lib/bootstrap.min.js https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js && \
    curl -o /usr/local/openresty/nginx/html/css/bootstrap.min.css https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css

# Copy NGINX configuration and Lua files
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY lua/ /usr/local/openresty/nginx/lua/
COPY html/ /usr/local/openresty/nginx/html/
COPY static/ /usr/local/openresty/nginx/html/

# Set proper permissions
RUN chmod -R 755 /usr/local/openresty/nginx/html/ && \
    chmod -R 755 /usr/local/openresty/nginx/lua/ && \
    chown -R nobody:nobody /usr/local/openresty/nginx/html/ && \
    chown -R nobody:nobody /usr/local/openresty/nginx/lua/ && \
    chown -R nobody:nobody /var/cache/nginx && \
    chown -R nobody:nobody /var/log/nginx

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

# Expose port
EXPOSE 80

# Start OpenResty directly
CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]