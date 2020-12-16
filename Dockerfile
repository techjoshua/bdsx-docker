FROM ubuntu:20.04 AS vmtouch
RUN apt-get update && apt-get install -y \
    build-essential \ 
    git

RUN cd /usr/share/ \
 && git clone https://github.com/hoytech/vmtouch.git \
 && cd vmtouch \
 && make \
 && make install

FROM ubuntu:20.04

COPY --from=vmtouch /usr/local/bin/vmtouch /usr/local/bin/vmtouch

# Install wine, curl, unzip, jq
#  - wine for running the windows bedrock server
#  - jq for producing the whitelist.json and permissions.json files
#  - curl for downloading nodejs install script and easy-add
#  - unzip because we need it to install node
RUN apt-get update && apt-get install -y --no-install-recommends \
    wine wine64 \
    curl unzip jq \
    && apt-get clean autoclean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/cache/apt/lists

# Install nodejs and npm - these are used to run the bdsx installer
RUN curl -sL https://deb.nodesource.com/setup_12.x | bash -E - \
    && apt-get update && apt-get install -y --no-install-recommends nodejs npm \
    && apt-get clean autoclean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/cache/apt/lists

# Install itzg helper binaries for bedrock servers
#   - entrypoint-demoter: among other things, translates SIGTERM signals to stdin "stop" commands to gracefully stop the server
#   - set-property: used to generate the server.properties file from ENV variables
#   - mc-monitor: provides status of bedrock server... used for docker HEALTHCHECK
ARG ARCH=amd64
ARG EASY_ADD_VERSION=0.7.1

RUN curl -L https://github.com/itzg/easy-add/releases/download/${EASY_ADD_VERSION}/easy-add_linux_${ARCH} --output /usr/local/bin/easy-add --silent \
    && chmod +x /usr/local/bin/easy-add \
    && easy-add --var version=0.2.1 --var app=entrypoint-demoter --file {{.app}} --from https://github.com/itzg/{{.app}}/releases/download/{{.version}}/{{.app}}_{{.version}}_linux_${ARCH}.tar.gz \
    && easy-add --var version=0.1.1 --var app=set-property --file {{.app}} --from https://github.com/itzg/{{.app}}/releases/download/{{.version}}/{{.app}}_{{.version}}_linux_${ARCH}.tar.gz \
    && easy-add --var version=0.5.0 --var app=mc-monitor --file {{.app}} --from https://github.com/itzg/{{.app}}/releases/download/{{.version}}/{{.app}}_{{.version}}_linux_${ARCH}.tar.gz

# Set the server port for the container... generally you shouldn't mess with this.
# if you want your server to run on a different port, change the port mapping of the container
# in your `docker run` command or docker-compose file.
ARG SERVER_PORT=19132/udp

# Setup ENV variables
# WINEDEBUG adjusts how noisy wine is... -all disables all debug statements
# SERVER_PORT is used in the server.properties and in the HEALTHCHECK statement...
# BDSX_VERSION specifies which version of the npm module 'bdsx' should be used.
#  ('LATEST' tells the scripts to use the most recent version and is probably what you should leave it at)
ENV WINEDEBUG=-all \
    SERVER_PORT=${SERVER_PORT} \
    BDSX_VERSION=LATEST

# Expose the minecraft bedrock server port
EXPOSE ${SERVER_PORT}

# Start the server using entrypoint-demoter.  Note that we're using ENTRYPOINT.  Your bdsx script directory should be
# passed in as the "CMD" (if using a dockerfile), "command" (if using a docker-compose file), or the first parameter
# after the image name in a `docker run` command.
ENTRYPOINT ["/usr/local/bin/entrypoint-demoter", "--match", "/data", "--stdin-on-term", "stop", "/opt/bedrock-entry.sh"]

# Checks the bedrock server periodically to ensure it is still running correctly.
HEALTHCHECK --start-period=1m CMD /usr/local/bin/mc-monitor status-bedrock --host 127.0.0.1 --port ${SERVER_PORT}

# Setup the volume where the installed bedrock server will live with all its configuration and world files
VOLUME [ "/data" ]
WORKDIR /data

# Copy the startup script and the JSON file which contains the metadata used to generate a server.properties file
COPY bedrock-entry.sh /opt/
COPY property-definitions.json /etc/bds-property-definitions.json