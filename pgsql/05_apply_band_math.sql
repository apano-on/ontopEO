CREATE OR REPLACE FUNCTION ontop_openeo.apply_band_math(arg TEXT)
RETURNS TEXT AS $$

import plpy
import json
import re
import ast
import operator

def apply_band_math(input_expr):
    """
    Parse a mathematical expression and generate a JSON workflow.

    :param input_expr: String containing mathematical expression with x1, x2, etc. and constants
    :return: JSON string representing the computational graph
    """
    # Remove whitespaces
    input_expr = input_expr.replace(' ', '')

    # Validate input
    if not re.match(r'^[\s\(\)x0-9\+\-\*/\.]+$', input_expr):
        plpy.error("Invalid input expression")

    # Track nodes and counters
    nodes = {}
    node_counters = {
        'add': 1,
        'subtract': 1,
        'multiply': 1,
        'divide': 1,
        'constant': 1
    }

    # Find all variables
    variables = sorted(set(re.findall(r'x\d+', input_expr)), key=lambda x: int(x[1:]))

    # Create array elements for each variable
    for i, var in enumerate(variables):
        nodes[var] = {
            "process_id": "array_element",
            "arguments": {
                "data": {"from_parameter": "data"},
                "index": i
            }
        }

    # Function to generate unique node names
    def get_unique_node_name(operation):
        node_name = f"{operation}{node_counters[operation]}"
        node_counters[operation] += 1
        return node_name

    # Define a new class to handle our custom variables during parsing
    class BandMathTransformer(ast.NodeTransformer):
        def visit_Name(self, node):
            if node.id.startswith('x') and node.id[1:].isdigit():
                return ast.Name(id=node.id, ctx=ast.Load())
            return node

    # Custom evaluator for parse tree
    def build_computation_graph(node):
        if isinstance(node, ast.BinOp):
            left_node = build_computation_graph(node.left)
            right_node = build_computation_graph(node.right)

            if isinstance(node.op, ast.Add):
                node_name = get_unique_node_name('add')
                nodes[node_name] = {
                    "process_id": "add",
                    "arguments": {
                        "x": {"from_node": left_node},
                        "y": {"from_node": right_node}
                    }
                }
                return node_name

            elif isinstance(node.op, ast.Sub):
                node_name = get_unique_node_name('subtract')
                nodes[node_name] = {
                    "process_id": "subtract",
                    "arguments": {
                        "x": {"from_node": left_node},
                        "y": {"from_node": right_node}
                    }
                }
                return node_name

            elif isinstance(node.op, ast.Mult):
                node_name = get_unique_node_name('multiply')
                nodes[node_name] = {
                    "process_id": "multiply",
                    "arguments": {
                        "x": {"from_node": left_node},
                        "y": {"from_node": right_node}
                    }
                }
                return node_name

            elif isinstance(node.op, ast.Div):
                node_name = get_unique_node_name('divide')
                nodes[node_name] = {
                    "process_id": "divide",
                    "arguments": {
                        "x": {"from_node": left_node},
                        "y": {"from_node": right_node}
                    }
                }
                return node_name

        elif isinstance(node, ast.Name):
            # Return variable name directly (already defined in nodes)
            return node.id

        elif isinstance(node, ast.Constant):
            # Handle numeric constants
            node_name = get_unique_node_name('constant')
            nodes[node_name] = {
                "process_id": "constant",
                "arguments": {
                    "x": node.value
                }
            }
            return node_name

        elif isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
            # Handle negative numbers
            if isinstance(node.operand, ast.Constant):
                node_name = get_unique_node_name('constant')
                nodes[node_name] = {
                    "process_id": "constant",
                    "arguments": {
                        "x": -node.operand.value
                    }
                }
                return node_name
            else:
                # Handle negative expressions like -(x1+x2)
                inner_node = build_computation_graph(node.operand)
                node_name = get_unique_node_name('multiply')
                const_name = get_unique_node_name('constant')

                nodes[const_name] = {
                    "process_id": "constant",
                    "arguments": {
                        "x": -1
                    }
                }

                nodes[node_name] = {
                    "process_id": "multiply",
                    "arguments": {
                        "x": {"from_node": const_name},
                        "y": {"from_node": inner_node}
                    }
                }
                return node_name

        plpy.error(f"Unsupported node type: {type(node)}")

    try:
        # Prepare expression for the parser - substitute variable names for parsing
        parser_expr = input_expr

        # Parse the expression into an AST
        parsed_expr = ast.parse(parser_expr, mode='eval')

        # Transform variable names
        transformed = BandMathTransformer().visit(parsed_expr)

        # Build the computational graph
        final_node = build_computation_graph(transformed.body)

        # Mark the final node as result
        nodes[final_node]['result'] = True

        # OpenEO requires lowercase true for result node
        return json.dumps(nodes).replace('True', 'true')

    except SyntaxError as e:
        plpy.error(f"Syntax error in expression: {str(e)}")
    except Exception as e:
        plpy.error(f"Error processing expression: {str(e)}")


return apply_band_math(arg)
$$ LANGUAGE plpython3u;