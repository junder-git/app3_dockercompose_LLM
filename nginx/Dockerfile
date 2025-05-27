# File: Dockerfile 
# Directory: /deepseek-coder-setup/nginx/

FROM nginx:alpine

WORKDIR /usr/share/nginx/html

# Remove default configuration
RUN rm /etc/nginx/conf.d/default.conf
RUN rm /etc/nginx/nginx.conf

# Copy our complete configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Copy static HTML files
COPY unauthorized.html /usr/share/nginx/html/
COPY rate_limited.html /usr/share/nginx/html/

# Create directory structure for static files - VOLUME MOUNTING THE SATIC FILES INSTEAD IN MY COMPOSE
#RUN mkdir -p /usr/share/nginx/html/static/css /usr/share/nginx/html/static/js
# Copy static CSS and JS files
#COPY static/css/styles.css /usr/share/nginx/html/static/css/
#COPY static/js/main.js /usr/share/nginx/html/static/js/

# Set proper permissions
RUN chmod -R 755 /usr/share/nginx/html/

EXPOSE 80

# Default CMD - no need to modify
CMD ["nginx", "-g", "daemon off;"]