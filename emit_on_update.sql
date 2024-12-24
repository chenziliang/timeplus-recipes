-- Whenever there is a change for a group key, emit its latest aggregation result

CREATE STREAM emit_on_update(k string, i int);

SELECT k, count(), sum(i), min(i), max(i)
GROUP BY k
EMIT ON UPDATE;