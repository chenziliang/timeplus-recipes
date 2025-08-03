-- Install slack_sdk
-- timeplusd python --config-file /etc/timeplusd-server/config.yaml -m pip install --user slack_sdk
-- Create alert to slack UDF 

CREATE OR REPLACE FUNCTION send_to_slack(cluster_id string, node_id uint32)
RETURNS bool LANGUAGE PYTHON AS
$$
import os
import json
import logging

logging.basicConfig(level=logging.DEBUG)
                                                                                   

from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

# slack_token = os.environ['slack_token']
slack_token = 'xoxb-'
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

CREATE STREAM IF NOT EXISTS node_states (cluster_id string, node_id string, node_state string);

-- Create task to populate target stream node_states
CREATE TASK refresh_node_states
SCHEDULE 5s
TIMEOUT 2s
INTO node_states
AS
  SELECT cluster_id, node_id, node_state FROM system.cluster;

-- Create Alert
CREATE OR REPLACE ALERT offline_nodes_alert 
BATCH 5 EVENTS WITH TIMEOUT 1s
LIMIT 1 ALERTS PER 1s
CALL send_to_slack 
AS 
SELECT cluster_id, node_id FROM node_states WHERE status != 'Online'; 

-- Emulate node status
-- INSERT INTO node_statuses(cluster, node_id, status) VALUES ('timeplus_cluster_exp', 1, 'Online');
-- INSERT INTO node_statuses(cluster, node_id, status) VALUES ('timeplus_cluster_exp', 2, 'Offline');
