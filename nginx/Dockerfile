FROM nginx:alpine

# Remove default configuration
RUN rm /etc/nginx/conf.d/default.conf && \
    rm /etc/nginx/nginx.conf

# Copy NGINX configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Copy error pages
COPY error-pages/ /usr/share/nginx/html/

# Expose port 443 for HTTPS (Cloudflare handles SSL termination)
EXPOSE 443

# Start NGINX
CMD ["nginx", "-g", "daemon off;"]