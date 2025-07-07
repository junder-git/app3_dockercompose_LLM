# nginx/Dockerfile - Nginx with njs JavaScript runtime

FROM nginx:alpine

# Install nginx-module-njs for server-side JavaScript
RUN apk add --no-cache \
    nginx-module-njs \
    curl \
    && rm -rf /var/cache/apk/*

# Set working directory
WORKDIR /usr/share/nginx/html

# Remove default NGINX configuration and content
RUN rm /etc/nginx/conf.d/default.conf && \
    rm /etc/nginx/nginx.conf && \
    rm -rf /usr/share/nginx/html/*

# Copy NGINX configuration with njs
COPY nginx.conf /etc/nginx/nginx.conf

# Create directory structure
RUN mkdir -p /etc/nginx/njs && \
    mkdir -p /usr/share/nginx/html/css && \
    mkdir -p /usr/share/nginx/html/js && \
    mkdir -p /usr/share/nginx/html/assets && \
    mkdir -p /var/cache/nginx && \
    mkdir -p /var/log/nginx

# Copy server-side JavaScript modules (for njs)
COPY njs/ /etc/nginx/njs/

# Copy static files
COPY static/css/ /usr/share/nginx/html/css/
COPY static/js/ /usr/share/nginx/html/js/
COPY static/html/ /usr/share/nginx/html/
COPY static/assets/ /usr/share/nginx/html/assets/

# Copy error pages to root for nginx error_page directives
RUN cp /usr/share/nginx/html/404.html /usr/share/nginx/html/ && \
    cp /usr/share/nginx/html/50x.html /usr/share/nginx/html/ && \
    cp /usr/share/nginx/html/rate_limited.html /usr/share/nginx/html/ && \
    cp /usr/share/nginx/html/unauthorized.html /usr/share/nginx/html/

# Set proper permissions
RUN chmod -R 755 /usr/share/nginx/html/ && \
    chmod -R 755 /etc/nginx/njs/ && \
    chown -R nginx:nginx /usr/share/nginx/html/ && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

# Expose port
EXPOSE 80

# Start NGINX with njs
CMD ["nginx", "-g", "daemon off;"]