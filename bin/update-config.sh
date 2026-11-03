#!/bin/bash -e

script_dir=$(cd $(dirname "$0"); pwd)
token_file="$TOKEN_FILE_LOCATION"

AUTH_ARG=""

if [ -f $token_file ]; then
    AUTH_ARG="-auth $(cat $token_file)"
fi

if [ ! -f $script_dir/jenkins-cli.jar ]; then
    curl -o $script_dir/jenkins-cli.jar http://localhost:8080/jnlpJars/jenkins-cli.jar
fi


# -http: the default WebSocket transport is rejected by newer Jenkins (403, "Unexpected request
# origin") because the Origin localhost:8080 does not match the configured Jenkins root URL.
echo "Updating Jenkins Configuration"
java -jar $script_dir/jenkins-cli.jar \
    -s http://localhost:8080/ -http $AUTH_ARG \
    groovy = < /var/jenkins_home/init.groovy.d/JenkinsConfigLoader.groovy
echo "Jenkins Configuration Updated"
