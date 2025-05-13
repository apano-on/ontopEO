# ontopeo

## Description
This repository contains the pipeline and requirements for the project OntoEO.

Its components are the following:
- The code/branch of Ontop with the openEO functions
- A pipeline which loads geospatial and other data into a PostgreSQL database
- PL/Python functions which enable querying of openEO

## Pre-requisites
### Data
In order to run all of the examples please download:
- From MapView data for South Tyrol
- From Campania data on Ischia
- Netherlands data
### openEO
Executing the example queries requires access to an openEO cloud provider. 
The recommended provider is Copernicus where any user needs to follow the instructions and:
- Register for an account and obtain a user ID https://documentation.dataspace.copernicus.eu/Registration.html
- Register for authentication with OAuth2 https://documentation.dataspace.copernicus.eu/APIs/SentinelHub/Overview/Authentication.html
Both need to be provided at ...

## Execution
In order to run the experiments. Please run:
'''
docker compose up
'''
Go to localhost:8080 and run the example queries.
