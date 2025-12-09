{% macro refresh_adjust_activity_tables() %}

{% set platforms = {
    'IOS': [
        'att_update',
        'sk_install',
        'install_update',
        'event',
        'click',
        'session',
        'rejected_install',
        'reattribution_update',
        'impression',
        'sk_qualifier',
        'sk_install_direct',
        'rejected_reattribution',
        'sk_cv_update',
        'sk_event',
        'install',
        'reattribution'
    ],
    'ANDROID': [
        'rejected_reattribution',
        'install_update',
        'install',
        'reattribution',
        'rejected_install',
        'session',
        'click',
        'reattribution_update',
        'event',
        'impression'
    ]
} %}

{% for platform, activity_kinds in platforms.items() %}
    {% for activity_kind in activity_kinds %}
        {% set table_name = platform ~ '_ACTIVITY_' ~ activity_kind | upper %}
        {% set source_table = platform ~ '_EVENTS' %}
        {% set sql %}
            CREATE OR REPLACE TABLE ADJUST_S3.DATA.{{ table_name }} AS
            SELECT *
            FROM ADJUST_S3.DATA.{{ source_table }}
            WHERE ACTIVITY_KIND = '{{ activity_kind }}'
        {% endset %}
        
        {% do run_query(sql) %}
        {{ log('Created ADJUST_S3.DATA.' ~ table_name, info=True) }}
    {% endfor %}
{% endfor %}

{% endmacro %}