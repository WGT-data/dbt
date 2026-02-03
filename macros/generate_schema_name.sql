{% macro generate_schema_name(custom_schema_name, node) -%}

    {#
        This macro controls where models are written based on target environment.

        For dev target: Prefixes schema with 'DEV_' (e.g., S3_DATA -> DEV_S3_DATA)
        For prod target: Uses the schema as-is (e.g., S3_DATA)

        If no custom schema is provided, falls back to the target schema.
    #}

    {%- set default_schema = target.schema -%}

    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- elif target.name == 'prod' -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        DEV_{{ custom_schema_name | trim }}
    {%- endif -%}

{%- endmacro %}
