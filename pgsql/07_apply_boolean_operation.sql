CREATE OR REPLACE FUNCTION ontop_openeo.apply_boolean_operation(arg TEXT[])
RETURNS TEXT AS $$
DECLARE
result TEXT;
    process_node_id TEXT;
    from_node_id TEXT;
    operator TEXT;
    comparisons JSONB = '[]'::JSONB;
    i INTEGER := 1;
    current_comparison JSONB;
    comparison_type TEXT;
    comparison_value TEXT;
BEGIN
    -- Extract the process node ID (first element)
    process_node_id := arg[1];

    -- Find the 'apply' keyword position
    WHILE i <= array_length(arg, 1) LOOP
        IF arg[i] = 'apply' THEN
            -- Get the from_node_id (should be next element)
            IF i+1 <= array_length(arg, 1) THEN
                from_node_id := arg[i+1];
END IF;
            EXIT;
END IF;
        i := i + 1;
END LOOP;

    -- Find logical operator ('or', 'and')
    i := 1;
    WHILE i <= array_length(arg, 1) LOOP
        IF arg[i] = 'or' OR arg[i] = 'and' THEN
            operator := arg[i];
            EXIT;
END IF;
        i := i + 1;
END LOOP;

    -- Process comparison operators (gt, lt, eq, etc.) and their values
    i := 1;
    WHILE i <= array_length(arg, 1) LOOP
        IF arg[i] IN ('gt', 'lt', 'eq', 'gte', 'lte', 'neq') THEN
            comparison_type := arg[i];

            -- Get comparison value (should be next element)
            IF i+1 <= array_length(arg, 1) THEN
                comparison_value := arg[i+1];

                -- Create a comparison object
                current_comparison := jsonb_build_object(
                    'process_id', comparison_type,
                    'arguments', jsonb_build_object(
                        'x', jsonb_build_object('from_parameter', 'x'),
                        'y', comparison_value
                    )
                );

                -- Add to comparisons array
                comparisons := comparisons || current_comparison;
END IF;
END IF;
        i := i + 1;
END LOOP;

    -- Build the final apply process with the logical operation
    result := jsonb_build_object(
        'process_id', 'apply',
        'arguments', jsonb_build_object(
            'data', jsonb_build_object('from_node', from_node_id),
            'process', jsonb_build_object(
                'process_graph', jsonb_build_object(
                    process_node_id, jsonb_build_object(
                        'process_id', operator,
                        'arguments', jsonb_build_object(
                            'data', comparisons
                        ),
                        'result', TRUE
                    )
                )
            )
        )
    )::TEXT;

RETURN result;
END;
$$ LANGUAGE plpgsql;