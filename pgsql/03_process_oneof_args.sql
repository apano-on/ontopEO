-- Process oneof function arguments to a process graph

CREATE OR REPLACE FUNCTION ontop_openeo.process_args_to_graph(args text[])
RETURNS text[] AS $$
import json

def generate_process_structure(nums):
    if not nums or len(nums) < 1:
        return {}

    processes = {}
    counter = 1

    # Create all eq nodes for numbers
    eq_nodes = []
    for num in nums:
        if str(num).isdigit():
            node_name = f"eq{counter}"
            processes[node_name] = {
                "process_id": "eq",
                "arguments": {
                    "x": {
                        "from_parameter": "x"
                    },
                    "y": int(num)
                }
            }
            eq_nodes.append(node_name)
            counter += 1

    # Create or nodes connecting them
    def create_or_node(node1, node2):
        nonlocal counter
        node_name = f"or{counter}"
        processes[node_name] = {
            "process_id": "or",
            "arguments": {
                "x": {
                    "from_node": node1
                },
                "y": {
                    "from_node": node2
                }
            }
        }
        counter += 1
        return node_name

    # Build the or tree
    current = eq_nodes[0]
    for i in range(1, len(eq_nodes)):
        current = create_or_node(current, eq_nodes[i])

    # Add result=true to the last node
    last_node = f"or{counter-1}"
    if last_node in processes:
        processes[last_node]["result"] = True

    return json.dumps(processes)

# Main function logic
try:
    # Find the index of "or"
    #plpy.notice(f"Received args: {args}")  # Debugging
    args_inner = args[0]
    or_index = args_inner.index("or")
    #plpy.notice(f"or index: {or_index}")  # Debugging

    # Split the list at "or"
    first_part = args_inner[:or_index]
    numbers_part = args_inner[or_index + 1:]

    # Generate the process graph for the numbers
    process_graph = generate_process_structure(numbers_part)

    # Create the new list with the first part and the process graph
    result = first_part + [process_graph]

    return result
except ValueError:
    # If "or" is not found
    plpy.error("Input array must contain 'or'")
except Exception as e:
    plpy.error(f"Error processing input: {str(e)}")

$$ LANGUAGE plpython3u;