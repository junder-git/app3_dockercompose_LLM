# File: Dockerfile 
# Directory: /deepseek-coder-setup/nginx/

FROM nginx:1.25-alpine

# Remove default configuration
RUN rm /etc/nginx/conf.d/default.conf

# Create templates directory (nginx 1.19+ feature)
RUN mkdir -p /etc/nginx/templates

# Copy our template configuration to the templates directory
# nginx will automatically process *.template files and output to /etc/nginx/conf.d/
COPY default.conf.template /etc/nginx/templates/default.conf.template

# Copy static HTML files
COPY unauthorized.html /usr/share/nginx/html/
COPY rate_limited.html /usr/share/nginx/html/

# Create directory structure for static files - MOUNTING IN THE COMPOSE INSTEAD
#RUN mkdir -p /usr/share/nginx/html/static/css /usr/share/nginx/html/static/js
# Copy static files
#COPY static/css/styles.css /usr/share/nginx/html/static/css/
#COPY static/js/main.js /usr/share/nginx/html/static/js/

# Set proper permissions
RUN chmod -R 755 /usr/share/nginx/html/

WORKDIR /usr/share/nginx/html

EXPOSE 80

# Use default nginx command - it will automatically process templates
CMD ["nginx", "-g", "daemon off;"]