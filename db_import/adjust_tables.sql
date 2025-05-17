-- Add the new column
ALTER TABLE region_south_tyrol ADD COLUMN geom1 geometry(Geometry, 4326);

-- Update the column:
-- If ST_NumGeometries=1, convert to POLYGON
-- Otherwise keep as MULTIPOLYGON
UPDATE region_south_tyrol
SET geom1 = CASE
                WHEN ST_NumGeometries(geom) = 1 THEN ST_GeometryN(geom, 1)
                ELSE geom
    END;

-- Add index
CREATE INDEX south_tyrol_geom_idx ON region_south_tyrol USING gist (geom1);

-- Drop the old column and rename the new one
ALTER TABLE region_south_tyrol DROP COLUMN geom;
ALTER TABLE region_south_tyrol RENAME COLUMN geom1 TO geom;

ALTER TABLE municipalities_polygon
    ADD COLUMN istat_code_t TEXT;

-- Update the new column with the concatenated values
UPDATE municipalities_polygon
SET istat_code_t = TRIM_SCALE("istat_code")::TEXT;

ALTER TABLE municipalities_polygon
    ADD CONSTRAINT unique_istat_code UNIQUE (istat_code_t);

-- Drop the existing primary key
ALTER TABLE municipalities_polygon
DROP CONSTRAINT IF EXISTS municipalities_polygon_pkey; -- Replace with actual constraint name if different

-- Add NOT NULL constraint to istat_code
ALTER TABLE municipalities_polygon
    ALTER COLUMN istat_code_t SET NOT NULL;

-- Add the new primary key
ALTER TABLE municipalities_polygon
    ADD CONSTRAINT municipalities_polygon_pkey PRIMARY KEY (istat_code_t);

ALTER TABLE municipalities_polygon
    ADD COLUMN geom2d GEOMETRY;

UPDATE municipalities_polygon
SET geom2d = ST_TRANSFORM(ST_FORCE2d("geom"),4326);

-- Add PK to South Tyrol population table
ALTER TABLE population_south_tyrol
    ADD CONSTRAINT municipalities_pkey PRIMARY KEY ("CodiceComune");