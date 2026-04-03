-- =============================================================================
-- python_udf_rest.sql
-- =============================================================================
-- Same sink pattern as python_udf.sql but uses the Timeplus HTTP Ingest REST
-- API instead of proton_driver (TCP).
--
-- Motivation: proton_driver's deep import chain causes a C stack overflow in
-- timeplusd's TCPHandler worker threads, which have a smaller stack than the
-- main thread. The built-in `requests` library has a shallow import tree and
-- runs safely in those threads.
--
-- Ingest API endpoint (self-hosted Proton / Timeplus Enterprise):
--   POST http://<host>:3218/proton/v1/ingest/streams/<stream_name>
--   Content-Type: application/json
--   Body: {"columns": ["col1", "col2"], "data": [["v1", "v2"], ...]}
--
-- Usage:
--   INSERT INTO sink_to_timeplus_rest(raw)
--   SELECT raw FROM source_stream;
-- =============================================================================

CREATE EXTERNAL STREAM sink_to_timeplus_rest
(
    raw string
)
AS $$

import json
import requests

_session    = None   # persistent HTTP session (connection reuse)
_ingest_url = None   # resolved once in init()
_headers    = {}


def init(config_: str):
    """
    Called once when the external stream starts.

    config_ JSON fields:
    {
        "host":        "127.0.0.1",       -- Timeplus host
        "port":        3218,              -- HTTP port (default 3218)
        "stream":      "target_stream",   -- destination stream name
        "username":    "default",         -- optional, for Basic auth
        "password":    "",                -- optional
        "api_key":     "",                -- optional, X-Api-Key header (Timeplus Cloud)
        "timeout":     10                 -- request timeout in seconds
    }
    """
    global _session, _ingest_url, _headers

    config = json.loads(config_)

    host    = config.get("host",    "127.0.0.1")
    port    = config.get("port",    3218)
    stream  = config["stream"]

    _ingest_url = f"http://{host}:{port}/timeplusd/v1/ingest/streams/{stream}"

    _headers = {"Content-Type": "application/json"}

    api_key = config.get("api_key", "")
    if api_key:
        _headers["X-Api-Key"] = api_key

    _session = requests.Session()
    _session.headers.update(_headers)

    username = config.get("username", "")
    password = config.get("password", "")
    if username:
        _session.auth = (username, password)

    # store timeout for use in sink function
    _session._tp_timeout = config.get("timeout", 10)


def deinit():
    global _session
    if _session is not None:
        _session.close()
        _session = None


def sink_to_timeplus_rest(raw_cols):
    """
    raw_cols : list of raw string values, one per row in the batch.

    Sends all rows in one HTTP POST for efficiency.
    """
    rows = [[v] for v in raw_cols]

    body = {
        "columns": ["raw"],
        "data":    rows,
    }

    resp = _session.post(
        _ingest_url,
        data    = json.dumps(body),
        timeout = _session._tp_timeout,
    )
    resp.raise_for_status()

$$
SETTINGS
    type                     = 'python',
    write_function_name      = 'sink_to_timeplus_rest',
    init_function_name       = 'init',
    init_function_parameters = '{"host":"127.0.0.1","port":3218,"stream":"target_stream","username":"default","password":"","timeout":10}',
    deinit_function_name     = 'deinit';
