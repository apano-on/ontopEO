# ontopEO

**ontopEO** runs queries over Virtual Knowledge Graphs (VKG)s integrating relational
data in Postgresql and openEO data from Copernicus using the [Ontop](https://ontop-vkg.org/]
platform).

## Description
In this repository we provide instructions and code on how to run
a sample pipeline with queries over openEO using a VKG.

The entirety of the pipeline consists of 3 main components:
- A branch of [Ontop](https://github.com/ontop/ontop) with the openEO SPARQL functions 
which can be found in [ontop/openeo-v2](https://github.com/apano-on/ontop/tree/feature/openeo-v2)
  - A list of supported openEO functions implemented in SPARQL are present in the file
  [OPENEO.java](https://github.com/apano-on/ontop/blob/feature/openeo-v2/core/model/src/main/java/it/unibz/inf/ontop/model/vocabulary/OPENEO.java) 
- PL/Python functions which enable querying of openEO which can
be found in the folder [pgsql](./pgsql/)
- A docker pipeline which showcases integrated Ontop queries that make use of openEO
and other data into a PostgreSQL database

## Pre-requisites
### Data
In order to run all of the examples please download:
- From MapView data for South Tyrol. In the [themes](https://mapview.civis.bz.it/?context=PROV-BZ-GEOBROWSER-MAPVIEW&lang=it&bbox=590000,5120000,765000,5220000&epsg=EPSG:25832) 
to the left select "comuni" and send downloaded data to your email. Note that South Tyrol
data has already been added in this repo
- Download data on administrative divisions of Campania from [Geoportale Regione Campania](https://sit2.regione.campania.it/content/dati-di-base)
- Netherlands data from the [Dutch National Georegister](https://www.nationaalgeoregister.nl/geonetwork/srv/dut/catalog.search#/metadata/216FF6D5-9BC0-4B19-A4D7-FC131238D621)

All of the files should be placed in [db_import/data](./db_import/data) and a respective
script to import the files should be updated in [db_import/import_data.sh](./db_import/import_data.sh).
For the PostGIS backend services like shp2pgsql and ogr2ogr can import the data.

### openEO
Executing the example queries requires access to an openEO cloud provider. 
The recommended provider is Copernicus where any user needs to follow the instructions and:
- Register for an account and obtain a user ID: https://documentation.dataspace.copernicus.eu/Registration.html
- Log in and navigate to Sentinel Hub 

<img src="CopernicusUserPage.png" alt="user page" width="300">

- Navigate to "User Settings" below on the left and add an OAuth2 client secret

**Action**: Set in the file `.env` the two respective environment variables
`USER_OPENEO_CLIENT_ID` and `USER_OPENEO_CLIENT_SECRET`
based on the credentials generated in openEO

### Ontop
We have also created a docker image for [ontop-openeo](https://hub.docker.com/repository/docker/albulenpano/ontop-openeo/general)
which we use in this example and can be updated in the docker compose file.

For every new dataset being mapped from the PostgreSQL database to Ontop, a respective mapping
needs to be added in [vkg/openeo.obda](./vkg/openeo.obda). Note, that unused mappings can
be removed or commented using a semicolon ";".

## Running the demo
In order to run the experiments. Please execute from the root directory of this project:
```
docker compose up
```
This will initialize a PostgreSQL database at port 7777 and
Ontop at port 8081, where you can run the example queries at localhost:8081 in your browser.


### Reference metadata
DOI: 10.5281/zenodo.15409222

apano-on. apano-on/ontopEO: beta-1 (beta-1). Zenodo, 2025. DOI: https://doi.org/10.5281/zenodo.15423395.
