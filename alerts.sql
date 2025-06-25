-- Install slack_sdk
-- timeplusd python --config-file /etc/timeplusd-server/config.yaml -m pip install --user slack_sdk
-- Create alert to slack UDF 

CREATE OR REPLACE FUNCTION send_to_slack(cluster string, node_id uint32)
RETURNS bool LANGUAGE PYTHON AS
$$
import logging
logging.basicConfig(level=logging.DEBUG)
                                                                                   
import json

from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

slack_token = 'xoxb-...'
client = WebClient(token=slack_token)
 
def send_to_slack(clusters, offline_nodes):
    if not offline_nodes:
        return []

    cluster_offline_nodes = {}
    for i in range(len(clusters)):
        if clusters[i] in cluster_offline_nodes:
            cluster_offline_nodes[clusters[i]].append(offline_nodes[i])
        else:
            cluster_offline_nodes[clusters[i]] = [offline_nodes[i]]

    data = json.dumps({"cluster_offline_nodes": cluster_offline_nodes})
    try:
        client.chat_postMessage(channel="alert-demo", text=data)
        return [True for v in offline_nodes]
    except SlackApiError as e:
        return [False for v in offline_nodes]
$$;

-- Create test stream
CREATE STREAM node_statuses(cluster string, node_id uint32, status string);

-- Create Alert
CREATE OR REPLACE ALERT offline_nodes_alert 
BATCH 5 EVENT WITH TIMEOUT 1 SECOND
LIMIT 1 PER 1 SECOND
CALL send_to_slack 
AS 
SELECT cluster, node_id FROM node_statuses WHERE status != 'Online'; 

-- Emulate node status
-- INSERT INTO node_statuses(cluster, node_id, status) VALUES ('timeplus_cluster_exp', 1, 'Online');
-- INSERT INTO node_statuses(cluster, node_id, status) VALUES ('timeplus_cluster_exp', 2, 'Offline');
