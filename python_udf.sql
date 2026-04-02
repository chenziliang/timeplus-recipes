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
        "host": "127.0.0.1",
        "port": 8463,
        "database": "default",
        "user": "default",
        "password": ""
    }
    """

    global timeplus_client

    config = json.loads(config_)
    timeplus_client = client.Client(host='127.0.0.1', port=8463, **config)

def deinit():
    if timeplus_client is not None:
        timeplus_client.disconnect()

def sink_to_timeplus(raw_cols):
    timeplus_client.execute("INSERT INTO target_stream(raw) VALUES", [[raw_col] for raw_col in raw_cols])

$$
SETTINGS
    type='python',
    write_function_name='sink_to_timeplus',
    init_function_name='init',
    init_function_parameters='{"user": "default", "password": "", "database": "default"}',
    deinit_function_name='deinit';
