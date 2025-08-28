-- SQL UDF

-- null + null => null
-- null + non_null => non_null
CREATE FUNCTION null_plus AS (lhs, rhs) -> if (lhs is null and rhs is null, null, coalesce(lhs, 0) + coalesce(rhs, 0));

CREATE FUNCTION null_minus AS (lhs, rhs) -> if (lhs is null and rhs is null, null, coalesce(lhs, 0) - coalesce(rhs, 0));

CREATE FUNCTION null_least AS (lhs, rhs) -> if (lhs is null and rhs is null, null, least(coalesce(lhs, rhs), coalesce(lhs, rhs)));

CREATE FUNCTION null_greatest AS (lhs, rhs) -> if (lhs is null and rhs is null, null, greatest(coalesce(lhs, rhs), coalesce(rhs, lhs)));

CREATE FUNCTION null_least3 AS (p1, p2, p3) -> if (p1 is null and p2 is null and p3 is null, null, least(coalesce(p1, p2, p3), coalesce(p2, p1, p3), coalesce(p3, p1, p2)));

CREATE FUNCTION null_greatest3 AS (p1, p2, p3) -> if (p1 is null and p2 is null and p3 is null, null, greatest(coalesce(p1, 0), coalesce(p2, 0), coalesce(p2, 0)));

-- file_path_history
CREATE FUNCTION file_path_history AS (n) -> if(empty(n),  [], array_concat([n], file_path_history_01((SELECT if(empty(old_path), null, old_path) FROM git.file_changes WHERE path = n AND (change_type = 'Rename' OR change_type = 'Add') LIMIT 1))));

CREATE FUNCTION file_path_history_01 AS (n) -> if(is_null(n), [], array_concat([n], file_path_history_02((SELECT if(empty(old_path), null, old_path) FROM git.file_changes WHERE path = n AND (change_type = 'Rename' OR change_type = 'Add') LIMIT 1))));

CREATE FUNCTION file_path_history_02 AS (n) -> if(is_null(n), [], array_concat([n], file_path_history_03((SELECT if(empty(old_path), null, old_path) FROM git.file_changes WHERE path = n AND (change_type = 'Rename' OR change_type = 'Add') LIMIT 1))));

CREATE FUNCTION file_path_history_03 AS (n) -> if(is_null(n), [], array_concat([n], file_path_history_04((SELECT if(empty(old_path), null, old_path) FROM git.file_changes WHERE path = n AND (change_type = 'Rename' OR change_type = 'Add') LIMIT 1))));

CREATE FUNCTION file_path_history_04 AS (n) -> if(is_null(n), [], array_concat([n], file_path_history_05((SELECT if(empty(old_path), null, old_path) FROM git.file_changes WHERE path = n AND (change_type = 'Rename' OR change_type = 'Add') LIMIT 1))));

CREATE FUNCTION file_path_history_05 AS (n) -> if(is_null(n), [], [n]);