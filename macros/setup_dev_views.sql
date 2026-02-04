{% macro setup_dev_views() %}
    {#
        Creates views in DEV_S3_DATA schema that point to production S3_DATA tables.
        This allows dev environment to read from prod source data without duplicating it.

        Run with: dbt run-operation setup_dev_views

        Note: Requires SYSADMIN or appropriate permissions to create views.
    #}

    {% set source_tables = [
        'IOS_EVENTS',
        'ANDROID_EVENTS'
    ] %}

    {% for table in source_tables %}
        {% set create_view_sql %}
            CREATE OR REPLACE VIEW ADJUST.DEV_S3_DATA.{{ table }} AS
            SELECT * FROM ADJUST.S3_DATA.{{ table }}
        {% endset %}

        {% do run_query(create_view_sql) %}
        {{ log("Created view DEV_S3_DATA." ~ table ~ " -> S3_DATA." ~ table, info=True) }}
    {% endfor %}

    {{ log("Dev views setup complete!", info=True) }}
{% endmacro %}
