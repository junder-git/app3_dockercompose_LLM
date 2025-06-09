FROM nginx:alpine

# Remove default configuration
RUN rm /etc/nginx/conf.d/default.conf && \
    rm /etc/nginx/nginx.conf

# Copy NGINX configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Copy error pages
COPY error-pages/ /usr/share/nginx/html/

# Expose ports
EXPOSE 80 443

# Start NGINX
CMD ["nginx", "-g", "daemon off;"]