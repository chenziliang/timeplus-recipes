-- SYSTEM INSTALL PYTHON PACKAGE 'proton-driver';
-- INSERT INTO sink_to_timeplus SELECT 'hello world ' || to_string(number) FROM system.numbers LIMIT 10;

create external stream sink_to_timeplus 
(
    raw string
)
AS $$

from proton_driver import client

import json

timeplus_client = None

def init(config_):
    """
    config_ is a JSON string with the following fields:
    {
        "database": "default",
        "user": "default",
        "password": ""
    }
    """
    global timeplus_client

    config = json.loads(config_)
    timeplus_client = client.Client(
        host='127.0.0.1', 
        port=8463, 
        user=__timeplus_local_api_user, # timeplusd inject these ephemeral credentials 
        password=__timeplus_local_api_password, 
        **config)

def deinit():
    if timeplus_client is not None:
        timeplus_client.disconnect()

def sink_to_timeplus(raw_cols):
    timeplus_client.execute(f"INSERT INTO target_stream(raw) VALUES", [[raw_col] for raw_col in raw_cols])

$$
SETTINGS
    type='python',
    write_function_name='sink_to_timeplus',
    init_function_name='init',
    init_function_parameters='{"database": "default"}',
    deinit_function_name='deinit';
