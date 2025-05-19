# File: Dockerfile 
# Directory: /deepseek-coder-setup/nginx/

FROM nginx:alpine

WORKDIR /usr/share/nginx/html

# Create templates directory (official NGINX Docker template support)
RUN mkdir -p /etc/nginx/templates

# Copy template files for environment variable substitution
COPY templates/nginx.conf.template /etc/nginx/templates/
COPY templates/gzip.conf.template /etc/nginx/templates/

# Copy static HTML files
COPY unauthorized.html /usr/share/nginx/html/
COPY rate_limited.html /usr/share/nginx/html/

# Create directory structure for static files
RUN mkdir -p /usr/share/nginx/html/static/css /usr/share/nginx/html/static/js

# Copy static CSS and JS files
COPY static/css/styles.css /usr/share/nginx/html/static/css/
COPY static/js/main.js /usr/share/nginx/html/static/js/

# Set proper permissions
RUN chmod -R 755 /usr/share/nginx/html/

# Environment variables with defaults (for reference only, actual values come from docker-compose)
ENV MAX_BODY_SIZE=10M
ENV RATE_LIMIT_REQS=10
ENV RATE_LIMIT_WINDOW=60s
ENV FAILED_LOGIN_LIMIT=5
ENV WEB_UI_HOST=web-ui

EXPOSE 80

# Default CMD - no need to modify
CMD ["nginx", "-g", "daemon off;"]