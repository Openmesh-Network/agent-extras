##################### Keygen + SnowSQL + POST Snowflake-connector

# RISK: Random generation may solve this (need input), cannot go into production with this.
CONST_PASS=openmesh-password

# Keygen
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8 -passin pass:$CONST_PASS -passout pass:$CONST_PASS;
SECRET=$(echo `sed -e '2,$!d' -e '$d' -e 's/\n/ /g' rsa_key.p8`|tr -d ' ');
openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub -passin pass:$CONST_PASS -passout pass:$CONST_PASS;
PUBKEY=$(echo `sed -e '2,$!d' -e '$d' -e 's/\n/ /g' rsa_key.pub`|tr -d ' ');

# Use GPG keys to verify snowsql installation
verify_snowsql () {
    gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 630D9F3CAB551AF3
    gpg --verify snowsql-1.2.31-linux_x86_64.bash.sig snowsql-1.2.31-linux_x86_64.bash
}

#Install SnowSQL
{ # try AWS download
       curl -O https://sfc-repo.snowflakecomputing.com/snowsql/bootstrap/1.2/linux_x86_64/snowsql-1.2.31-linux_x86_64.bash

} || { # otherwise try Azure
       curl -O https://sfc-repo.azure.snowflakecomputing.com/snowsql/bootstrap/1.2/linux_x86_64/snowsql-1.2.31-linux_x86_64.bash
}
verify_snowsql

# 
# Use SnowSQL to create connect user with our public key. 
snowsql -a $ORGURL -u XNODE_CONNECT_USER -f snowflake.sql --token $OAUTH -D CONNECT_USER_KEY=$PUBKEY


# Post connector config to kafka connect
echo "Waiting for Kafka Connect to start listening on kafka-connect  "
while :; do
    # Check if the connector endpoint is ready
    # If not check again
    curl_status=$(curl -s -o /dev/null -w %{http_code} http://connect.confluent:{{ .Values.servicePort }}/connectors)
    echo -e $(date) "Kafka Connect listener HTTP state: " $curl_status " (waiting for 200)"
    if [ $curl_status -eq 200 ]; then
        break
    fi
    sleep 5
done

# Can be hardcoded if this is correct, needs testing.
CONNECT_REST_ADVERTISED_HOST_NAME=localhost

echo "======> Creating connectors"
# Send a simple POST request to create the connector
curl -X POST \
    -H "Content-Type: application/json" \
    --data '{
    "name":"XnodeSnowflakeConnector",
        "config":{
            "connector.class":"com.snowflake.kafka.connector.SnowflakeSinkConnector",
            "tasks.max":"8",
            "topics":"ethereum_logs",
            "buffer.count.records":"10000",
            "buffer.flush.time":"60",
            "buffer.size.bytes":"5000000",
            "snowflake.url.name":"ytclduc-wk11656.snowflakecomputing.com",
            "snowflake.user.name":"XNODE_CONNECT_USER", 	
            "snowflake.private.key":'$SECRET',    
            "snowflake.private.key.passphrase":'$CONST_PASS',
            "snowflake.database.name":"XNODE_DB",
            "snowflake.schema.name":"XNODE_SCHEMA",
            "snowflake.warehouse.name":"KAFKA_CONNECT",
            "key.converter":"org.apache.kafka.connect.storage.StringConverter",
        "value.converter":"com.snowflake.kafka.connector.records.SnowflakeAvroConverter",
            "value.converter.schema.registry.url":"http://schema-registry:8081"
        }
    }' http://$CONNECT_REST_ADVERTISED_HOST_NAME:8083/connectors

# TO-DO: Fix topics
# Might be able to do all topics if we map every topic to a table
# TO-DO: Passphrase 'CONST_PASS' is fixed