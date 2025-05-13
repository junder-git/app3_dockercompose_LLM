# File: Dockerfile
# Directory: /deepseek-coder-setup/nginx/

FROM nginx:alpine

# Copy nginx configuration files
COPY nginx.conf /etc/nginx/nginx.conf
COPY gzip.conf /etc/nginx/gzip.conf

# Create directory for static files
RUN mkdir -p /usr/share/nginx/html/static

# Create custom error pages
RUN echo '<!DOCTYPE html>\
<html>\
<head>\
    <title>Rate Limit Exceeded</title>\
    <meta http-equiv="refresh" content="10">\
    <style>\
        body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }\
        .container { max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 5px; }\
        h1 { color: #d9534f; }\
        .timer { color: #d9534f; font-weight: bold; }\
    </style>\
</head>\
<body>\
    <div class="container">\
        <h1>Rate Limit Exceeded</h1>\
        <p>You have made too many requests. Please wait before trying again.</p>\
        <p>Page will refresh in <span class="timer">10</span> seconds...</p>\
        <script>\
            let seconds = 10;\
            const timerElement = document.querySelector(".timer");\
            const intervalId = setInterval(() => {\
                seconds--;\
                timerElement.textContent = seconds;\
                if (seconds <= 0) clearInterval(intervalId);\
            }, 1000);\
        </script>\
    </div>\
</body>\
</html>' > /usr/share/nginx/html/rate_limited.html

# Set proper permissions
RUN chmod -R 755 /usr/share/nginx/html/

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]