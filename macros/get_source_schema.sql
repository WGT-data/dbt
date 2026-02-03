{% macro get_source_schema(base_schema) -%}
    {#
        Returns the appropriate source schema based on target environment.

        For dev target: Prefixes schema with 'DEV_' (e.g., S3_DATA -> DEV_S3_DATA)
        For prod target: Uses the schema as-is (e.g., S3_DATA)
    #}
    {%- if target.name == 'prod' -%}
        {{ base_schema }}
    {%- else -%}
        DEV_{{ base_schema }}
    {%- endif -%}
{%- endmacro %}
