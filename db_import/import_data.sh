#!/bin/bash

echo "Viewing the PostgreSQL Client Version"
psql -Version

echo "Set password"
export PGPASSWORD="openeopassword"

# shp2pgsql scripts

echo "Loading vector data for Region of Interest (ROI) South Tyrol"
shp2pgsql -s 25832 /data/Municipalities_polygon.shp municipalities_polygon | psql -h openeodb -p 5432 -U openeouser -d openeodb
shp2pgsql -s 25832 /data/EuropeanRegions_polygon.shp europeanregions_polygon | psql -h openeodb -p 5432 -U openeouser -d openeodb

# Copy the population data
# Handle potential BOM in the first column name and clean all column names
HEADER=$(head -n 1 /data/population_south_tyrol.csv)
# First, clean the entire header line of any BOM characters
HEADER=$(echo "$HEADER" | sed 's/^\xEF\xBB\xBF//')
IFS=',' read -ra COLUMNS <<< "$HEADER"

# Build CREATE TABLE statement with thorough cleaning
CREATE_STMT="CREATE TABLE IF NOT EXISTS population_south_tyrol ("
for COL in "${COLUMNS[@]}"; do
    # Remove quotes, non-printable characters, and trim whitespace
    CLEAN_COL=$(echo "$COL" | tr -d '"' | tr -dc '[:print:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    CREATE_STMT+="\"$CLEAN_COL\" TEXT,"
done
CREATE_STMT=${CREATE_STMT%,}  # Remove trailing comma
CREATE_STMT+=");"

# Create the table
psql -h openeodb -U openeouser -d openeodb -c "$CREATE_STMT"

# Import the data
psql -h openeodb -U openeouser -d openeodb -c "\COPY population_south_tyrol FROM '/data/population_south_tyrol.csv' WITH (FORMAT CSV, HEADER, DELIMITER ',');"

echo "Import completed"

#############################

sleep 5
ogr2ogr -f "PostgreSQL" \
  PG:"host=openeodb dbname=openeodb user=openeouser password=openeopassword" \
  /data/WijkBuurtkaart_2025_v0.gpkg \
  -nln region_netherlands \
  -nlt PROMOTE_TO_MULTI \
  -lco GEOMETRY_NAME=geom \
  -lco FID=gid \
  -lco SPATIAL_INDEX=GIST
sleep 10
shp2pgsql -s 32633 /data/SITRC_COMUNI_CAMPANIA.shp region_campania | psql -h openeodb -p 5432 -U openeouser -d openeodb


# Additional script to add geospatial index
psql -h openeodb -p 5432 -U openeouser -d openeodb -f adjust_tables.sql

echo "Unset password"
unset PGPASSWORD