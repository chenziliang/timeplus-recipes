--

CREATE EXTERNAl stream kt1(raw string) settings type='kafka', brokers='192.168.1.121', topic='topic1';
CREATE EXTERNAl stream kt2(raw string) settings type='kafka', brokers='192.168.1.121', topic='topic2';
CREATE EXTERNAl stream kt3(raw string) settings type='kafka', brokers='192.168.1.121', topic='topic3';

SELECT 
    kt1.raw:p AS p,
    kt1.raw:c1 AS c1,
    kt1.raw:c2 AS c2,
    kt2.raw:c3 AS c3,
    kt2.raw:c4 AS c4,
    kt2.raw:c5 AS c5,
    kt2.raw:c6 AS c6
FROM 
kt1
FULL LATEST JOIN 
kt2
ON kt1.raw:p = kt2.raw:p 
FULL LATEST JOIN 
kt3
ON kt1.raw:p = kt3.raw:p;


INSERT INTO kt1(raw) VALUES ('{"p":"p1", "c1":"c1", "c2":"c2"}');
INSERT INTO kt2(raw) VALUES ('{"p":"p1", "c3":"c3", "c4":"c4"}');
INSERT INTO kt3(raw) VALUES ('{"p":"p1", "c5":"c5", "c6":"c6"}');
