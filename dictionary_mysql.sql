-- Dictionary over Remote MySQL: cached

-- Create a table in mysql
CREATE Table products(
    `id` varchar(100) PRIMARY KEY,
    `name` varchar(100) NOT NULL,
    `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
);


CREATE DICTIONARY mysql_products_dict_cached(
    `id` string,
    `name` string,
    `created_at` datetime64(3) 
)
PRIMARY KEY id
SOURCE(MYSQL(DB 'test' TABLE 'products' HOST '127.0.0.1' PORT 3306 USER 'root' PASSWORD 'my' BG_RECONNECT true))
LIFETIME(MIN 1800 MAX 3600) -- in seconds
LAYOUT(complex_key_cache(size_in_cells 1000000000 allow_read_expired_keys 1 max_update_queue_size 100000 update_queue_push_timeout_milliseconds 100 query_wait_timeout_milliseconds 60000 max_threads_for_updates 4));


CREATE DICTIONARY mysql_products_dict_ssd_cached(
    `id` string,
    `name` string,
    `created_at` datetime64(3) 
)
PRIMARY KEY id
SOURCE(MYSQL(DB 'test' TABLE 'products' HOST '127.0.0.1' PORT 3306 USER 'root' PASSWORD 'my' BG_RECONNECT true))
LIFETIME(MIN 1800 MAX 3600) -- in seconds
LAYOUT(complex_key_ssd_cache(block_size 4096 file_size 1073741824 read_buffer_size 131072 write_buffer_size 1048576 path '/var/lib/timeplusd/user_files/products_mysql_dict'));


CREATE DICTIONARY mysql_products_dict_direct(
    `id` string,
    `name` string,
    `created_at` datetime64(3) 
)
PRIMARY KEY id
SOURCE(MYSQL(DB 'test' TABLE 'products' HOST '127.0.0.1' PORT 3306 USER 'root' PASSWORD 'my' BG_RECONNECT true))
LAYOUT(complex_key_direct());


CREATE MUTABLE STREAM mysql_mutable_cache
(
    `id` string,
    `name` string,
    `created_at` datetime64(3) 
)
PRIMARY KEY id;

insert into mysql_mutable_cache(id, name) values ('pid_0005', 'p111');

CREATE DICTIONARY mysql_products_dict_mutable(
    `id` string,
    `name` string,
    `created_at` datetime64(3) 
)
PRIMARY KEY id
SOURCE(MYSQL(DB 'test' TABLE 'products' HOST '127.0.0.1' PORT 3306 USER 'root' PASSWORD 'my' BG_RECONNECT true))
LAYOUT(mutable_cache(database 'default' stream 'mysql_mutable_cache' update_from_source false));


-- Test connectivity via dict_get for product id `pid_0001`
SELECT dict_get('mysql_products_dict_direct', 'name', 'pid_0001');

-- Direct join
CREATE STREAM orders (
    `id` string,
    `product_id` string,
    `quantity` uint32
);

SELECT * FROM orders JOIN mysql_products_dict_direct AS products
ON orders.product_id = products.id
SETTINGS join_algorithm = 'direct';
