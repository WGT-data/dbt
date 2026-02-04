{% macro generate_schema_name(custom_schema_name, node) -%}

    {#
        This macro controls where models are written based on target environment.

        - Adjust activity models (schema='S3_DATA'):
            - dev: DEV_S3_DATA
            - prod: S3_DATA
        - All other models:
            - dev: DBT_WGTDATA
            - prod: DBT_ANALYTICS
    #}

    {%- if custom_schema_name is not none and custom_schema_name | trim | upper == 'S3_DATA' -%}
        {# Adjust activity models go to S3_DATA or DEV_S3_DATA #}
        {%- if target.name == 'prod' -%}
            S3_DATA
        {%- else -%}
            DEV_S3_DATA
        {%- endif -%}
    {%- else -%}
        {# Everything else goes to DBT_WGTDATA (dev) or PROD (prod) #}
        {%- if target.name == 'prod' -%}
            PROD
        {%- else -%}
            DBT_WGTDATA
        {%- endif -%}
    {%- endif -%}

{%- endmacro %}
