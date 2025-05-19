CREATE OR REPLACE FUNCTION ontop_openeo.process_graph_function(
input JSONB,
out result TEXT)
RETURNS TEXT
LANGUAGE 'plpython3u'
AS $BODY$


from shapely.wkt import loads as load_wkt
from shapely.geometry import Polygon, MultiPolygon, GeometryCollection
import openeo
import json
import os
import re
import rasterio
from rasterio.io import MemoryFile
import numpy as np
from io import BytesIO

# Fetch the environment variables
client_id = os.getenv('OPENEO_CLIENT_ID')
client_secret = os.getenv('OPENEO_CLIENT_SECRET')

# 0. Add helper functions
#If the geometry is a linestring, multilinestring, point, multipoint, break and return null
#If the geometry is a polygon or multipolygon return the same formatted input as in the previous example
#If the geometry is a geometrycollection, if it has polygons apply the logic above only to the polygons, and ignore the rest
def process_geometry(geom_text):
    try:
        # Load geometry from WKT
        geom = load_wkt(geom_text)

        # Handle Polygon and MultiPolygon
        if isinstance(geom, Polygon):
            return str({
                "type": "Polygon",
                "coordinates": [[list(coord) for coord in geom.exterior.coords]]
            })[1:-1]
        elif isinstance(geom, MultiPolygon):
            return str({
                "type": "MultiPolygon",
                "coordinates": [
                    [[list(coord) for coord in p.exterior.coords]] for p in geom.geoms
                ]
            })[1:-1]

        # Handle GeometryCollection
        elif isinstance(geom, GeometryCollection):
            polygons = [g for g in geom.geoms if isinstance(g, (Polygon, MultiPolygon))]
            if not polygons:
                return None  # No polygons in the collection
            multi_polygon = MultiPolygon(polygons)
            return str({
                "type": "MultiPolygon",
                "coordinates": [
                    [[list(coord) for coord in p.exterior.coords]] for p in multi_polygon.geoms
                ]
            })[1:-1]

        # Handle unsupported geometries
        else:
            return None

    except Exception as e:
        print(f"Error processing geometry: {e}")
        return None


#TODO: Not robust since there might be non-geometry columns which start with those strings, better detection of which columns need transformation needed
def transform_list(input_list, f2):
    return [f2(element) if (
        isinstance(element, str) and
        any(element.lower().startswith(geom_type) for geom_type in [
            'multipolygon', 'polygon', 'linestring', 'multilinestring',
            'point', 'multipoint', 'geometrycollection'
        ])
    ) else element for element in input_list if element is not None]

def process_template(template_str, args):
    result = template_str
    for i, arg in enumerate(args, 1):
        placeholder = rf"\barg{i}\b"  # Raw f-string for easier regex
        replacement = ""

        if isinstance(arg, str) and arg.startswith('from_node_'):
            node_id = arg.replace('from_node_', '')
            replacement = f'"{node_id}"'
        elif isinstance(arg, str) and arg.startswith('to_node_'):
            node_id = arg.replace('to_node_', '')
            replacement = f'"{node_id}"'
        elif isinstance(arg, str) and arg.startswith('\'type\''):
            formatted_arg = arg.replace("'", '"')
            replacement = f'{arg}' # No extra quotes
        # Scenario with JSON string, multiple arguments
        #elif isinstance(arg, str) and arg.startswith('{'):
        #    formatted_arg = arg.replace("{", '').replace("}", '')
        #    replacement = f'{formatted_arg}'
        # Only replace first and last curly braces, apply_neighborhood arguments e.g. size use subarrays
        # problem for oneof where we add an extra one
        elif isinstance(arg, str) and arg.startswith('{') and arg.endswith('}'):
            formatted_arg = arg[1:-1]  # removes the first and last characters
            replacement = f'{formatted_arg}'
        else:
            # Escape any backslashes in the string to preserve \n
            if isinstance(arg, str):
                arg = arg.replace('\\', '\\\\')
            replacement = f'"{arg}"'

        result = re.sub(placeholder, replacement, result) # Use re.sub for regex replacement

    return result

"""Parse input list into groups of id and arguments."""
def parse_input_list(input_list):
    result = []
    current_group = []

    for item in input_list:
        if isinstance(item, str) and item.startswith('id_'):
            if current_group:
                result.append(current_group)
            current_group = [item]
        else:
            current_group.append(item)

    if current_group:
        result.append(current_group)

    return result

"""Process each group and generate output using appropriate template."""
def process_groups(groups):

    final_result = []

    for group in groups:
        node_id = group[0]  # First item is the id
        process_name = group[1].lower()  # Second item is the process name

        # Special case for functions that can take multiple arguments
        if (process_name == 'merge_cubes') and (len(group) == 4): process_name = 'merge_cubes_stack'
        if (process_name == 'reduce_dimension_comparison'): group[1] = 'reduce_dimension'

        args = group  # All items after id are arguments

        # Read template file
        if process_name == 'oneof':
            # Special handling for oneOf, generate subgraph with equal/or pattern
            args_str = "ARRAY[" + ", ".join(f"'{str(arg)}'" for arg in args) + "]::TEXT[]"
            query = f"SELECT ontop_openeo.process_args_to_graph({args_str})"
            result = plpy.execute(query)[0]['process_args_to_graph']
            args = [args[0], args[2], '{'+result[3]+'}']

        if process_name == 'band_math':
            # Special handling for band_math, generate subgraph with calculation
            result = plpy.execute(f"SELECT ontop_openeo.apply_band_math('{args[3]}')")[0]['apply_band_math']
            args = [args[0], args[2], json.loads(result)]

        if process_name == 'apply_kernel_gaussian':
        # Generate kernel by calling the PL/Python function

            # Function returning a dictionary for some reason, and we need to return the v based on k create_gaussian_kernel
            kernel_text = plpy.execute(f"SELECT ontop_openeo.create_gaussian_kernel('{args[3]}', '{args[4]}')")[0]['create_gaussian_kernel']
            # Convert to a PostgreSQL array if needed (or leave as text if used directly)
            args = [args[0], args[2], json.loads(kernel_text)]

        if process_name == 'apply' and not any(item in ["gt", "gte", "lt", "lte"] for item in group):
        # Apply with math operations and just comparison, requires more logic

            quoted_items = ["'%s'" % item.replace("'", "''") for item in group]  # SQL-escape single quotes
            array_string = "ARRAY[%s]" % ",".join(quoted_items)
            query = f"SELECT ontop_openeo.apply_custom_operation({array_string});"
            res = plpy.execute(query)
            apply_text = res[0]['apply_custom_operation']
            # remove first and last curly braces
            cleaned = apply_text.strip()[1:-1]
            # replace single with double quotation marks
            cleaned = cleaned.replace("'", '"')
            final_result.append(cleaned)
            continue

        if process_name == 'apply' and "or" in group:
        # Apply with comparison and boolean logic

            quoted_items = ["'%s'" % item.replace("'", "''") for item in group]  # SQL-escape single quotes
            array_string = "ARRAY[%s]" % ",".join(quoted_items)
            query = f"SELECT ontop_openeo.apply_boolean_operation({array_string});"
            res = plpy.execute(query)
            apply_text = res[0]['apply_boolean_operation']
            # remove first and last curly braces
            cleaned = apply_text.strip()[1:-1]
            # replace single with double quotation marks
            cleaned = cleaned.replace("'", '"')
            final_result.append(cleaned)
            continue

        template_filename = os.path.join(os.environ['TEMPLATE_DIR'], f"{process_name}.txt")
        try:
            with open(template_filename, 'r') as f:
                template = f.read()

            # Process template with arguments
            processed = process_template(template, args)

            # Add to final result
            final_result.append(processed)

        except FileNotFoundError:
            print(f"Warning: Template file {template_filename} not found")
        except json.JSONDecodeError:
            print(f"Warning: Invalid JSON generated for {node_id}")

    return final_result

def add_result_to_process_graph(process_graph_str):
    # Convert string to dictionary
    try:
        process_graph = json.loads(process_graph_str)
    except json.JSONDecodeError:
        raise ValueError("Input string is not valid JSON")

    # Create a copy to avoid modifying the input
    modified_graph = process_graph.copy()

    if "process_graph" not in modified_graph:
        raise ValueError("Input must contain a 'process_graph' key")

    # Find nodes that are not referenced by other nodes
    nodes = modified_graph["process_graph"]
    referenced_nodes = set()

    # Collect all referenced node IDs
    for node_id, node in nodes.items():
        if "arguments" in node:
            for arg in node["arguments"].values():
                if isinstance(arg, dict) and "from_node" in arg:
                    referenced_nodes.add(arg["from_node"])

    # Find terminal nodes (nodes not referenced by others)
    terminal_nodes = set(nodes.keys()) - referenced_nodes

    if len(terminal_nodes) != 1:
        raise ValueError(f"Expected exactly one terminal node, found {len(terminal_nodes)}")

    terminal_node = terminal_nodes.pop()

    # Add result flag to the terminal node
    nodes[terminal_node]["result"] = True

    # Convert back to string
    return json.dumps(modified_graph)

def convert_quoted_numbers(process_graph_str):
    """
    Converts quoted numbers in JSON string to actual numbers
    for keys 'x', 'y', or 'base'.
    For example: "y": "16384" becomes "y": 16384
    Handle negatives, scientific notation, and spaces.
    """
    pattern = r'("(?:x|y|base)":\s*)"(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)"'
    return re.sub(pattern, r'\1\2', process_graph_str)

def transform_band_list(text):
    # Find the exact pattern with quotes around a list-like string
    pattern = r'"bands":\s*\[(\s*"\[.*?\]"\s*)\]'

    def replace_match(match):
        # Extract the inner list string, remove brackets and quotes
        inner_list = match.group(1).strip()[1:-1].strip()

        # Split by comma, strip, remove leading [ and trailing ], and requote
        bands = [f'"{band.strip().lstrip("[").rstrip("]")}"' for band in inner_list.split(',')]

        # Return the transformed bands section
        return f'"bands": [{", ".join(bands)}]'

    # Use re.sub to replace the matched pattern
    return re.sub(pattern, replace_match, text, flags=re.DOTALL)


# 1. Start a session
session = openeo.connect("openeo.dataspace.copernicus.eu")
# Authenticate using your client ID and token
session.authenticate_oidc_client_credentials(
    client_id=client_id,
    client_secret=client_secret)

# 2. Process input
# 2.1 Parse the initial input list
input_list_initial = json.loads(input)
# 2.2 Transform wkt geometries to coordinates
input_list = transform_list(input_list_initial, process_geometry)
# 2.3 Split input list into groups where each group is an openEO function
groups = parse_input_list(input_list)

# 3. Generate basic process graph
# 3.1 Process groups by substituting arguments into templates
processed_groups = process_groups(groups)
# 3.2 Combine all generated process graph process templates with proper formatting
# Join groups with comma and newline
groups_text = ',\n'.join(processed_groups)
# 3.3 Read header
header_path = os.path.join(os.environ['TEMPLATE_DIR'], 'header.txt')
with open(header_path, 'r') as f:
    header = f.read()
# 3.4 Read footer
footer_path = os.path.join(os.environ['TEMPLATE_DIR'], 'footer.txt')
with open(footer_path, 'r') as f:
    footer = f.read()
# 3.5 Combine header, groups, and footer
complete_json_process_graph = f"{header}\n{groups_text}\n{footer}"

# 4. Special handling considerations
# TODO: Can be rationalized
# 4.1 Special handling for type Polygon/Multipolygon JSON components
# No quotation marks are allowed
#process_graph = complete_json_process_graph.replace("'", '"')
# 4.2 Apply kernel generating unnecessary quotation marks
#modified_graph_applykernel = process_graph.replace('\"[[', '[[').replace(']]\"', ']]')
# 4.3 OneOf generating unnecessary quotation marks
#modified_graph_oneof = modified_graph_applykernel.replace('\"{', '{').replace('}\"', '}')
modified_graph_string_rep = complete_json_process_graph.replace("'", '"').replace('\"[[', '[[').replace(']]\"', ']]').replace('\"{', '{').replace('}\"', '}')
# 4.4 Drop load collection with parameter, use proper name
modified_graph_loadcoll = modified_graph_string_rep.replace('load_collection_with_parameter', 'load_collection')
# 4.5 Transform band list
modified_graph_bandlist = transform_band_list(modified_graph_loadcoll)
# 4.6 OpenEO graphs require a result node, true needs to be lower case
modified_graph = add_result_to_process_graph(modified_graph_bandlist.replace("\"result\": True", "\"result\": true"))
# 4.7 Numbers must not have quotation marks
modified_graph_fixed_numerics = convert_quoted_numbers(modified_graph)


# Create a synchronous job
#job = session.create_job(modified_graph_fixed_numerics)

#result = job.start_and_wait().get_results().get_assets()[0]

# Create an asynchronous job
import asyncio
import openeo
import requests
from io import BytesIO
import rasterio

# Async status checker
async def check_status(job):
    while True:
        status = job.status()
        print(f"Job status: {status}")
        if status in ["finished", "error", "canceled"]:
            break
        await asyncio.sleep(5)
    return status

# Streaming download to avoid memory spikes
def stream_result(url):
    with requests.get(url, stream=True) as r:
        r.raise_for_status()
        buffer = BytesIO()
        for chunk in r.iter_content(chunk_size=8192):
            buffer.write(chunk)
        buffer.seek(0)
        return buffer

# Main asynchronous function
async def run_openeo_job(process_graph, client_id, client_secret):
    session = openeo.connect("openeo.dataspace.copernicus.eu")
    session.authenticate_oidc_client_credentials(
        client_id=client_id,
        client_secret=client_secret
    )

    job = session.create_job(process_graph)
    job.start()

    status = await check_status(job)

    if status == "finished":
        print("Job finished successfully!")
        result = job.get_results().get_assets()[0]

        try:
            if isinstance(result, openeo.rest.job.ResultAsset) and "timeseries.json" in result.href:
                import requests
                response = requests.get(result.href)
                # Try to extract [0][0] if possible
                try:
                    return response.json()[0][0]
                except (IndexError, TypeError, KeyError):
                    # If it fails, return the full JSON response instead
                    return response.json()

            #TODO: Redundant?
            # Attempt to load JSON and return a numeric value
            final_result = result.load_json()
            return final_result[0][0]
        except:
            # If JSON loading fails, continue with raster processing
            buffer = stream_result(result.href)

            with rasterio.open(buffer) as dataset:
                # Read all bands
                raster_data = dataset.read()
                print(f"Raster shape (bands, height, width): {raster_data.shape}")

                # Convert each band to a list (to be JSON serializable)
                json_serializable = [band.tolist() for band in raster_data]

                # Serialize to JSON string
                json_output = json.dumps(json_serializable)

                # Return JSON as TEXT for PostgreSQL
                return json_output
    elif status == "error":
        error = job.logs()
        print(f"Job failed with error: {error}")
        raise RuntimeError(f"OpenEO Job failed with error: {error}")
    elif status == "canceled":
        print("Job was canceled.")
        raise RuntimeError("OpenEO Job was canceled.")

result = asyncio.run(run_openeo_job(modified_graph_fixed_numerics, client_id=client_id, client_secret=client_secret))
return result
$BODY$;