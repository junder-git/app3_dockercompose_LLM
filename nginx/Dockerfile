# nginx/Dockerfile - Clean NGINX container with static files

FROM nginx:alpine

# Set working directory
WORKDIR /usr/share/nginx/html

# Copy NGINX configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Copy static HTML error pages
COPY html/unauthorized.html /usr/share/nginx/html/
COPY html/rate_limited.html /usr/share/nginx/html/

# Copy static assets (CSS, JS, etc.)
COPY static/ /usr/share/nginx/html/static/

# Set proper permissions
RUN chmod -R 755 /usr/share/nginx/html/ && \
    chown -R nginx:nginx /usr/share/nginx/html/

# Expose port
EXPOSE 80 443

# Start NGINX
CMD ["nginx", "-g", "daemon off;"]