CREATE EXTERNAL STREAM timeplusd_err_log(
    raw string,
    _tp_time ALIAS to_time(extract(raw, '^(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2}\.\d+)')),
    level ALIAS extract(raw, '} <(\w+)>'),
    message ALIAS extract(raw, '} <\w+> (.*)'))
SETTINGS
type='log',
log_files='timeplusd-server.err.log',
log_dir='./timeplusd-data/var/log/timeplusd-server',
row_delimiter='(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2}\.\d+) \[ \d+ \] \{',
timestamp_regex='^(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2}\.\d+)';


CREATE EXTERNAL STREAM timeplusd_log(
    raw string,
    _tp_time ALIAS to_time(extract(raw, '^(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2}\.\d+)')),
    level ALIAS extract(raw, '} <(\w+)>'),
    message ALIAS extract(raw, '} <\w+> (.*)'))
SETTINGS
type='log',
log_files='timeplusd-server.log',
log_dir='./timeplusd-data/var/log/timeplusd-server',
row_delimiter='(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2}\.\d+) \[ \d+ \] \{',
timestamp_regex='^(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2}\.\d+)';
