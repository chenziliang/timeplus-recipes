--

CREATE EXTERNAL STREAM splunk
(
    event string,
    sourcetype string default 'otel_trace'
)
SETTINGS type='http', url='http://127.0.0.1:8088/services/collector', http_header_Authorization='Splunk c9851fde-641d-4a1d-8609-ac808d3a5e5f';
