-- SQL to generate data in ClickHouse

CREATE TABLE products 
(
    `id` String,
    `name` String,
    `d1` String,
    `d2` String,
    `d3` String,
    `d4` String,
    `d5` String,
    `d6` String,
    `d7` String,
    `d8` String,
    `d9` String,
    `d10` String,
    `d11` String,
    `d12` String,
    `d13` String,
    `d14` String,
    `d15` String,
    `d16` String,
    `d17` String,
    `d18` String,
    `d19` String,
    `d20` String,
    `d21` String,
    `d22` String,
    `d23` String,
    `d24` String,
    `d25` String,
    `d26` String,
    `d27` String,
    `d28` String,
    `d29` String,
    `d30` String,
    `d31` String,
    `d32` String,
    `d33` String,
    `d34` String,
    `d35` String,
    `d36` String,
    `d37` String,
    `d39` String,
    `d40` String,
    `d41` String,
    `d42` String,
    `d43` String,
    `d44` String,
    `d45` String,
    `d46` String,
    `d47` String,
    `d48` String,
    `d49` String,
    `d50` String,
    `dt` DateTime,
)
ENGINE = ReplacingMergeTree
PRIMARY KEY id
ORDER BY id;


-- Generate ~200 million unique keys

INSERT INTO products 
SELECT 'key_' || toString(id % 300000000) as id, * except(id) FROM generateRandom(
    '`id` UInt64,
    `name` String,
    `d1` String,
    `d2` String,
    `d3` String,
    `d4` String,
    `d5` String,
    `d6` String,
    `d7` String,
    `d8` String,
    `d9` String,
    `d10` String,
    `d11` String,
    `d12` String,
    `d13` String,
    `d14` String,
    `d15` String,
    `d16` String,
    `d17` String,
    `d18` String,
    `d19` String,
    `d20` String,
    `d21` String,
    `d22` String,
    `d23` String,
    `d24` String,
    `d25` String,
    `d26` String,
    `d27` String,
    `d28` String,
    `d29` String,
    `d30` String,
    `d31` String,
    `d32` String,
    `d33` String,
    `d34` String,
    `d35` String,
    `d36` String,
    `d37` String,
    `d39` String,
    `d40` String,
    `d41` String,
    `d42` String,
    `d43` String,
    `d44` String,
    `d45` String,
    `d46` String,
    `d47` String,
    `d48` String,
    `d49` String,
    `d50` String,
    `dt` DateTime', 1, 48
) LIMIT 200000000;