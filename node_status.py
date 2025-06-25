from proton_driver import client
import time

c = client.Client(host='127.0.0.1', port=8463, user='test', password='test1234')


while True:
    try:
        rows = c.execute_iter("SELECT cluster_id, node_id, node_state FROM system.cluster")

        offlines = []
        for row in rows:
            if row[2] != 'Online':
                offlines.append(row)

        if offlines:
            print(offlines)
            c.execute('INSERT INTO node_statuses(cluster, node_id, status) VALUES', offlines)

    except Exception:
        pass

    time.sleep(2)
