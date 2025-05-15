FROM debian:bookworm-slim
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    postgis postgresql-client gdal-bin wget && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy shapefiles and other sql files
COPY data /data
COPY import_data.sh .
COPY adjust_tables.sql .
RUN chmod +x import_data.sh

# Load data
ENTRYPOINT ["/import_data.sh"]