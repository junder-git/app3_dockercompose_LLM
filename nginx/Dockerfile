# nginx/Dockerfile - JWT workaround using OpenSSL for HMAC

FROM openresty/openresty:1.25.3.1-0-alpine-fat

# Install additional dependencies including OpenSSL for HMAC
RUN apk add --no-cache \
    curl \
    wget \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# Install lua-resty-jwt and lua-resty-http
RUN /usr/local/openresty/bin/opm get SkyLothar/lua-resty-jwt && \
    /usr/local/openresty/bin/opm get ledgetech/lua-resty-http

# Set working directory
WORKDIR /usr/local/openresty/nginx/dynamic_content

# Remove default configuration and content
RUN rm -f /etc/nginx/conf.d/default.conf 2>/dev/null || true && \
    rm -f /usr/local/openresty/nginx/conf/nginx.conf && \
    rm -rf /usr/local/openresty/nginx/html/*

# Create directories
RUN mkdir -p /usr/local/openresty/nginx/lua && \
    mkdir -p /usr/local/openresty/nginx/dynamic_content/css && \
    mkdir -p /usr/local/openresty/nginx/dynamic_content/js/lib && \
    mkdir -p /usr/local/openresty/nginx/dynamic_content/assets && \
    mkdir -p /var/cache/nginx && \
    mkdir -p /var/log/nginx

# Download external libraries
RUN curl -o /usr/local/openresty/nginx/dynamic_content/js/lib/jquery.min.js https://code.jquery.com/jquery-3.7.1.min.js && \
    curl -o /usr/local/openresty/nginx/dynamic_content/js/lib/bootstrap.min.js https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js && \
    curl -o /usr/local/openresty/nginx/dynamic_content/css/bootstrap.min.css https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css

# Copy NGINX configuration and Lua files
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY lua/ /usr/local/openresty/nginx/lua/
COPY dynamic_content/ /usr/local/openresty/nginx/dynamic_content/
COPY static/ /usr/local/openresty/nginx/dynamic_content/

# Set proper permissions
RUN chmod -R 755 /usr/local/openresty/nginx/dynamic_content/ && \
    chmod -R 755 /usr/local/openresty/nginx/lua/ && \
    chown -R nobody:nobody /usr/local/openresty/nginx/dynamic_content/ && \
    chown -R nobody:nobody /usr/local/openresty/nginx/lua/ && \
    chown -R nobody:nobody /var/cache/nginx && \
    chown -R nobody:nobody /var/log/nginx


# Expose port
EXPOSE 80

# Start OpenResty directly
CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]