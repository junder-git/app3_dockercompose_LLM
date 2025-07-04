# nginx/Dockerfile - Fixed to match nginx.conf expectations

FROM nginx:alpine

# Set working directory
WORKDIR /usr/share/nginx/html

# Remove default NGINX configuration and content
RUN rm /etc/nginx/conf.d/default.conf && \
    rm /etc/nginx/nginx.conf && \
    rm -rf /usr/share/nginx/html/*

# Copy NGINX configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Copy static HTML error pages to root
COPY html/unauthorized.html /usr/share/nginx/html/
COPY html/rate_limited.html /usr/share/nginx/html/

# Create static directory structure and copy CSS
RUN mkdir -p /usr/share/nginx/html/static/css
COPY css/styles.css /usr/share/nginx/html/static/css/

# Set proper permissions
RUN chmod -R 755 /usr/share/nginx/html/ && \
    chown -R nginx:nginx /usr/share/nginx/html/

# Expose port
EXPOSE 80

# Start NGINX
CMD ["nginx", "-g", "daemon off;"]