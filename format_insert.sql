CREATE STREAM j(json json(max_dynamic_paths=1)) ENGINE = Memory;
INSERT INTO j FORMAT JSONEachRow {"json" : {"a" : 42}}, {"json" : {"b" : "Hello"}}, {"json" : {"a" : [1, 2, 3], "c" : "2020-01-01"}}