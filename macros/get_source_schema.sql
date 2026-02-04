{% macro get_source_schema(base_schema) -%}
    {#
        Returns the source schema for reading raw data.
        Always reads from prod S3_DATA since that's where the raw events live.
    #}
    {{- base_schema -}}
{%- endmacro %}
