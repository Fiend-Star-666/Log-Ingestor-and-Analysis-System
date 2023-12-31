#!/bin/bash

# Set AIO max number of events
echo 3048576 > /proc/sys/fs/aio-max-nr

# Run Scylla I/O setup
scylla_io_setup

# Start Scylla in the background with additional options if needed
/docker-entrypoint.py &

# Wait for ScyllaDB to be ready
until cqlsh -e "describe cluster"
do
    echo "Waiting for ScyllaDB to be ready..."
    sleep 10
done

echo "ScyllaDB is now ready."

# Function to check if all nodes are up
check_all_nodes_up() {
    # Assuming a 3-node cluster
    local expected_nodes=5
    local up_nodes

    up_nodes=$(nodetool status | grep '^UN' | wc -l)
    [[ $up_nodes -eq $expected_nodes ]]
}

#Wait for all nodes to be up and running
until check_all_nodes_up
do
    echo "Waiting for all ScyllaDB nodes to be operational..."
    sleep 10
done

sleep 60

echo "All ScyllaDB nodes are up and operational."

# Create keyspace
cqlsh -e "CREATE KEYSPACE IF NOT EXISTS logKeySpace WITH REPLICATION = { 'class' : 'NetworkTopologyStrategy', 'datacenter1' : 3 };"

# Create table
cqlsh -e "CREATE TABLE IF NOT EXISTS logKeySpace.logs (
    traceId text,
    spanId text,
    timestamp timestamp,
    level text,
    message text,
    resourceId text,
    commit text,
    metadata map<text, text>,
    PRIMARY KEY ((traceId, spanId), timestamp)
) WITH CLUSTERING ORDER BY (timestamp DESC);"

# Create Indexes
cqlsh -e "CREATE INDEX IF NOT EXISTS idx_level ON logKeySpace.logs (level);"
cqlsh -e "CREATE INDEX IF NOT EXISTS idx_resource_id ON logKeySpace.logs (resourceId);"
cqlsh -e "CREATE INDEX IF NOT EXISTS idx_commit ON logKeySpace.logs (commit);"

# Create Materialized View
cqlsh -e "CREATE MATERIALIZED VIEW IF NOT EXISTS logKeySpace.logs_by_timestamp AS SELECT * FROM logKeySpace.logs WHERE timestamp IS NOT NULL AND traceId IS NOT NULL AND spanId IS NOT NULL PRIMARY KEY (timestamp, traceId, spanId) WITH CLUSTERING ORDER BY (traceId ASC, spanId ASC);"

cqlsh -e "CONSISTENCY QUORUM";

# Ensure that /cql_log_data.cql is optimized for batch inserts
cqlsh -f /cql_log_data.cql

nodetool repair

# Keep the container running
tail -f /dev/null
