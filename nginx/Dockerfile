# nginx/Dockerfile - Simple version

FROM nginx:alpine

# Install nginx-module-njs for server-side JavaScript
RUN apk add --no-cache nginx-module-njs curl

# Set working directory
WORKDIR /usr/share/nginx/html

# Remove default NGINX configuration and content
RUN rm /etc/nginx/conf.d/default.conf && \
    rm /etc/nginx/nginx.conf && \
    rm -rf /usr/share/nginx/html/*

# Copy NGINX configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Create directories
RUN mkdir -p /etc/nginx/njs && \
    mkdir -p /var/cache/nginx && \
    mkdir -p /var/log/nginx

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
    
# Download required libraries
RUN curl -o /usr/share/nginx/html/js/lib/jquery.min.js https://code.jquery.com/jquery-3.7.1.min.js && \
    curl -o /usr/share/nginx/html/js/lib/bootstrap.min.js https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js && \
    curl -o /usr/share/nginx/html/css/bootstrap.min.css https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]

