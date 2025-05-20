# File: Dockerfile
# Directory: /deepseek-coder-setup/db/

FROM postgres:15-alpine

# Copy initialization scripts
COPY init.sql /docker-entrypoint-initdb.d/01-init.sql
COPY create_tables.sql /docker-entrypoint-initdb.d/02-create_tables.sql

# Set permissions
RUN chmod 755 /docker-entrypoint-initdb.d/*.sql

# Default PostgreSQL port
EXPOSE 5432

