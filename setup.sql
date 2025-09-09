 USE ROLE sysadmin;

    /*--
    • database, schema and warehouse creation
    --*/

    -- create tb_voc database
    CREATE OR REPLACE DATABASE tb_voc;

    -- create raw_pos schema
    CREATE OR REPLACE SCHEMA tb_voc.raw_pos;

    -- create raw_customer schema
    CREATE OR REPLACE SCHEMA tb_voc.raw_support;

    -- create harmonized schema
    CREATE OR REPLACE SCHEMA tb_voc.harmonized;

    -- create analytics schema
    CREATE OR REPLACE SCHEMA tb_voc.analytics;

    -- create media schema
    CREATE OR REPLACE SCHEMA tb_voc.media;

    /*--
    • file format and stage creation
    --*/

    CREATE OR REPLACE FILE FORMAT tb_voc.public.csv_ff 
    type = 'csv';

    CREATE OR REPLACE STAGE tb_voc.public.s3load
    COMMENT = 'Quickstarts S3 Stage Connection'
    url = 's3://sfquickstarts/tastybytes-voc/'
    file_format = tb_voc.public.csv_ff;

    /*--
    raw zone table build 
    --*/

    -- menu table build
    CREATE OR REPLACE TABLE tb_voc.raw_pos.menu
    (
        menu_id NUMBER(19,0),
        menu_type_id NUMBER(38,0),
        menu_type VARCHAR(16777216),
        truck_brand_name VARCHAR(16777216),
        menu_item_id NUMBER(38,0),
        menu_item_name VARCHAR(16777216),
        item_category VARCHAR(16777216),
        item_subcategory VARCHAR(16777216),
        cost_of_goods_usd NUMBER(38,4),
        sale_price_usd NUMBER(38,4),
        menu_item_health_metrics_obj VARIANT
    );

    -- truck table build 
    CREATE OR REPLACE TABLE tb_voc.raw_pos.truck
    (
        truck_id NUMBER(38,0),
        menu_type_id NUMBER(38,0),
        primary_city VARCHAR(16777216),
        region VARCHAR(16777216),
        iso_region VARCHAR(16777216),
        country VARCHAR(16777216),
        iso_country_code VARCHAR(16777216),
        franchise_flag NUMBER(38,0),
        year NUMBER(38,0),
        make VARCHAR(16777216),
        model VARCHAR(16777216),
        ev_flag NUMBER(38,0),
        franchise_id NUMBER(38,0),
        truck_opening_date DATE
    );

    -- order_header table build
    CREATE OR REPLACE TABLE tb_voc.raw_pos.order_header
    (
        order_id NUMBER(38,0),
        truck_id NUMBER(38,0),
        location_id FLOAT,
        customer_id NUMBER(38,0),
        discount_id VARCHAR(16777216),
        shift_id NUMBER(38,0),
        shift_start_time TIME(9),
        shift_end_time TIME(9),
        order_channel VARCHAR(16777216),
        order_ts TIMESTAMP_NTZ(9),
        served_ts VARCHAR(16777216),
        order_currency VARCHAR(3),
        order_amount NUMBER(38,4),
        order_tax_amount VARCHAR(16777216),
        order_discount_amount VARCHAR(16777216),
        order_total NUMBER(38,4)
    );

    -- truck_reviews table build
    CREATE OR REPLACE TABLE tb_voc.raw_support.truck_reviews
    (
        order_id NUMBER(38,0),
        language VARCHAR(16777216),
        source VARCHAR(16777216),
        review VARCHAR(16777216),
        review_id NUMBER(18,0)
    );

    /*--
    • harmonized view creation
    --*/

    -- truck_reviews_v view
    CREATE OR REPLACE VIEW tb_voc.harmonized.truck_reviews_v
        AS
    SELECT DISTINCT
        r.review_id,
        r.order_id,
        oh.truck_id,
        r.language,
        source,
        r.review,
        t.primary_city,
        oh.customer_id,
        TO_DATE(oh.order_ts) AS date,
        m.truck_brand_name
    FROM tb_voc.raw_support.truck_reviews r
    JOIN tb_voc.raw_pos.order_header oh
        ON oh.order_id = r.order_id
    JOIN tb_voc.raw_pos.truck t
        ON t.truck_id = oh.truck_id
    JOIN tb_voc.raw_pos.menu m
        ON m.menu_type_id = t.menu_type_id;

    /*--
    • analytics view creation
    --*/

    -- truck_reviews_v view
    CREATE OR REPLACE VIEW tb_voc.analytics.truck_reviews_v
        AS
    SELECT * FROM harmonized.truck_reviews_v;


    /*--
    raw zone table load 
    --*/


    -- menu table load
    COPY INTO tb_voc.raw_pos.menu
    FROM @tb_voc.public.s3load/raw_pos/menu/;

    -- truck table load
    COPY INTO tb_voc.raw_pos.truck
    FROM @tb_voc.public.s3load/raw_pos/truck/;

    -- order_header table load
    COPY INTO tb_voc.raw_pos.order_header
    FROM @tb_voc.public.s3load/raw_pos/order_header/;

    -- truck_reviews table load
    COPY INTO tb_voc.raw_support.truck_reviews
    FROM @tb_voc.public.s3load/raw_support/truck_reviews/;

    USE SCHEMA tb_voc.analytics;

    CREATE OR REPLACE TABLE CONCATENATED_REVIEWS AS
    WITH RANKED_REVIEWS AS (
        SELECT 
            TRUCK_BRAND_NAME,
            REVIEW,
            ROW_NUMBER() OVER (PARTITION BY TRUCK_BRAND_NAME ORDER BY REVIEW) AS ROW_NUM
        FROM TRUCK_REVIEWS_V
    ),
    FILTERED_REVIEWS AS (
        SELECT *
        FROM RANKED_REVIEWS
        WHERE ROW_NUM <= 20
    ),
    AGGREGATED_REVIEWS AS (
        SELECT 
            TRUCK_BRAND_NAME,
            ARRAY_AGG(REVIEW) AS ALL_REVIEWS
        FROM FILTERED_REVIEWS
        GROUP BY TRUCK_BRAND_NAME
    ),
    CONCATENATED_REVIEWS AS (
        SELECT 
            TRUCK_BRAND_NAME,
            ARRAY_TO_STRING(ALL_REVIEWS, ' ') AS ALL_REVIEWS_TEXT
        FROM AGGREGATED_REVIEWS
    )

    SELECT * FROM CONCATENATED_REVIEWS;

-- Create image storage stage
CREATE STAGE IF NOT EXISTS tb_voc.MEDIA.IMAGES
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
  DIRECTORY = (ENABLE = true);

-- Create audio storage stage  
CREATE STAGE IF NOT EXISTS tb_voc.MEDIA.AUDIO
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
  DIRECTORY = (ENABLE = true);

ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';

  -- setup completion note
  SELECT 'Setup is complete' AS note;
