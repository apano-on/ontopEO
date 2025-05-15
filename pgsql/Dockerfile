# Use bookworm version of the PostgreSQL image to get Python 3.11
FROM postgres:17.2-bookworm

# Install system dependencies and GDAL components
RUN apt-get update && apt-get install -y \
    wget \
    postgresql-17-postgis-3 \
    postgresql-plpython3-17 \
    python3-pip \
    python3-dev \
    python3-venv \
    build-essential \
    libgdal-dev \
    gdal-bin \
    python3-gdal \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*


# Set GDAL-related environment variables for debugging
ENV GDAL_HTTP_VERBOSE=YES
ENV CPL_LOG=/tmp/gdal.log
ENV CPL_LOG_ERRORS=/tmp/gdal_errors.log
ENV GDAL_DATA=/usr/share/gdal
ENV GDAL_DRIVER_PATH=/usr/lib/gdal/plugins

# Set include paths for GDAL
ENV CPLUS_INCLUDE_PATH=/usr/include/gdal
ENV C_INCLUDE_PATH=/usr/include/gdal

# Create virtual environment
RUN python3 -m venv /opt/envopeneo --system-site-packages

# Copy requirements
COPY requirements.txt /opt/envopeneo/requirements.txt

# Install packages with explicit GDAL version
RUN /opt/envopeneo/bin/pip install --no-cache-dir \
    wheel \
    setuptools \
    && /opt/envopeneo/bin/pip install --no-cache-dir \
    GDAL==3.6.2 \
    && /opt/envopeneo/bin/pip install --no-cache-dir -r /opt/envopeneo/requirements.txt

# Verify GDAL installation
RUN /opt/envopeneo/bin/python3 -c "from osgeo import gdal; print(gdal.__version__)"

# Set Python path
ENV PYTHONPATH=/opt/envopeneo/lib/python3.11/site-packages

# Add template files and SQL scripts
ENV TEMPLATE_DIR=/opt/envopeneo/templates
COPY templates /opt/envopeneo/templates
COPY *.sql /docker-entrypoint-initdb.d/
COPY *.sql.gz /docker-entrypoint-initdb.d/

EXPOSE 5432