CREATE OR REPLACE FUNCTION ontop_openeo.apply_custom_operation(arg TEXT[])
RETURNS TEXT AS $$
import json

def build_process_graph(arg):
    node_id = arg[0]
    process_id = arg[1]
    input_node = arg[2].replace("from_node_", "")
    constant = arg[3]
    operations = arg[4:]

    process_graph = {}
    last_node_id = None

    if (len(operations)==1):
       current_node_id = f"{operations[0]}1"
       process_graph[current_node_id] = {
                "process_id": operations[0],
                "arguments": {
                    "x": constant,
                    "y": {"from_parameter": "x"}
                },
                    "result": True
            }


    if (len(operations)>1):
        # Build inner process graph from last operation to first
        for idx, op in enumerate(reversed(operations)):
            current_node_id = f"{op}1"
            if op == "log":
                process_graph[current_node_id] = {
                    "process_id": op,
                    "arguments": {
                        "base": constant,
                        "x": {"from_parameter": "x"} if last_node_id is None else {"from_node": last_node_id}
                    }
                }
            else:
                process_graph[current_node_id] = {
                    "process_id": op,
                    "arguments": {
                        "x": constant,
                        "y": {"from_node": last_node_id if last_node_id else f"{operations[-1]}1"}
                    },
                    "result": True
                }

            last_node_id = current_node_id

    result = {
        node_id: {
            "process_id": process_id,
            "arguments": {
                "data": {
                    "from_node": input_node
                },
                "process": {
                    "process_graph": process_graph
                }
            }
        }
    }

    return result

return build_process_graph(arg)
$$ LANGUAGE plpython3u;
