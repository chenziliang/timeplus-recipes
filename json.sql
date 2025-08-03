-- json text

SELECT json_extract_keys_and_values_raw('{"key1":"value1","key2":"value2"}');
-- [('key1','"value1"'),('key2','"value2"')] 

SELECT json_extract('{"key1":"value1","key2":"value2"}', 'map(String, string)');
-- {'key1':'value1','key2':'value2'} 

-- json type column (json object) 
