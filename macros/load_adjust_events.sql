{% macro load_adjust_events() %}

    {% set ios_copy %}
        COPY INTO ADJUST_S3.DATA.IOS_EVENTS
        FROM @ADJUST_S3_STAGE
        FILE_FORMAT = (FORMAT_NAME = 'ADJUST_CSV_FORMAT')
        PATTERN = '.*acqu46kv92ss.*\.csv\.gz'
        ON_ERROR = 'CONTINUE';
    {% endset %}

    {% set android_copy %}
        COPY INTO ADJUST_S3.DATA.ANDROID_EVENTS
        FROM @ADJUST_S3_STAGE
        FILE_FORMAT = (FORMAT_NAME = 'ADJUST_CSV_FORMAT')
        PATTERN = '.*q9nlmhlmwjec.*\.csv\.gz'
        ON_ERROR = 'CONTINUE';
    {% endset %}

    {% do log("Loading iOS events from S3...", info=True) %}
    {% do run_query(ios_copy) %}
    {% do log("iOS events loaded.", info=True) %}

    {% do log("Loading Android events from S3...", info=True) %}
    {% do run_query(android_copy) %}
    {% do log("Android events loaded.", info=True) %}

    {{ return("OK") }}

{% endmacro %}
