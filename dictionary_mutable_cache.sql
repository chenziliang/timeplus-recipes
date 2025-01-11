-- Local mutable stream as dictionary cache storage 

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
SELECT dict_get('mysql_products_dict_mutable', 'name', 'pid_0001');

-- The join will first lookup keys in mutable stream, if the all keys are found in mutable stream, 
-- the join can finish without falling back to do remote mysql lookup; otherwise it will send 
-- fetch query to remote mysql for missing keys and stitch the two parts (keys from mutable 
-- stream and keys from remtoe mysql) to finish the query. 
SELECT * FROM orders JOIN mysql_products_dict_mutable AS products
ON orders.product_id = products.id
SETTINGS join_algorithm = 'direct';
