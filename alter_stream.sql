-- For mutable stream

ALTER STREAM db.stream ADD INDEX sidx1 (s);
ALTER STREAM db.stream CLEAR INDEX sid1;
ALTER STREAM db.stream CLEAR INDEX `1`;
ALTER STREAM db.stream MATERIALIZE INDEX sidx1 WITH CLEAR; 
ALTER STREAM db.stream DROP INDEX sidx1;

-- For append stream
ALTER STREAM db.stream ADD INDEX sidx1 (i) TYPE minmax GRANULARITY 32;
