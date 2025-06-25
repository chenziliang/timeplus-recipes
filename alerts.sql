-- Install slack_sdk
-- timeplusd python --config-file /etc/timeplusd-server/config.yaml -m pip install --user slack_sdk
-- Create alert to slack UDF 

CREATE OR REPLACE FUNCTION alert_to_slack(node_id uint32)
RETURNS bool LANGUAGE PYTHON AS
$$
import logging
logging.basicConfig(level=logging.DEBUG)
                                                                                   
import json

from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

slack_token = 'xoxb-...'          
client = WebClient(token=slack_token)
 
def alert_to_slack(offline_nodes):
    if not offline_nodes:
        return []

    data = json.dumps({"offline_node_ids": offline_nodes})
    try:
        client.chat_postMessage(channel="alert-demo", text=data)
        return [True for v in offline_nodes]
    except SlackApiError as e:
        return [False for v in offline_nodes]
$$;

-- Create test stream
CREATE STREAM node_statuses(node_id uint32, status string);

-- Create Alert
CREATE OR REPLACE ALERT nodes_status_alert 
BATCH 5 EVENT WITH TIMEOUT 1 SECOND
LIMIT 1 PER 1 SECOND
CALL alert_to_slack 
AS 
SELECT node_id FROM node_statuses WHERE status = 'Offline'; 


-- Emulate node status
INSERT INTO node_statuses(node_id, status) VALUES (1, 'Online');
INSERT INTO node_statuses(node_id, status) VALUES (2, 'Offline');
