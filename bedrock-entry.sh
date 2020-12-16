#!/bin/bash

# bdsx wants to install the bedrock server to the ~/.bds directory
# but for consistency and ease of volume mapping we symlink that
# directory to /data, which is a volume defined in the dockerfile 
ln -s /data ~/.bds

# Ensure EULA is accepted
if [[ ${EULA^^} != TRUE ]]; then
  echo
  echo "EULA must be set to TRUE to indicate agreement with the Minecraft End User License"
  echo "See https://minecraft.net/terms"
  echo
  echo "Current value is '${EULA}'"
  echo
  exit 1
fi

# Determine which bdsx version to use.
# if LATEST is specified the latest version of bdsx from the npm repository is used
if [[ ${BDSX_VERSION^^} == LATEST ]]; then
  BDSX_VERSION=$(npm view bdsx version)
fi

# run bdsx install
echo "Installing bdsx version ${BDSX_VERSION} from npm registry..."
if [[ ${MANUAL_BDS^^} != TRUE ]]; then
  npx bdsx@${AVAILABLE_VERSION} install -y
else
  npx bdsx@${AVAILABLE_VERSION} install -y --manual-bds
fi

# run npm install on script directory
if [ $# -ne 0 ]; then
  echo "Running NPM install on script directory $1"
  pushd $1
  npm install
  popd
fi

# populate permissions.json from env variables
if [ -n "$OPS" ] || [ -n "$MEMBERS" ] || [ -n "$VISITORS" ]; then
  echo "Updating permissions"
  jq -n --arg ops "$OPS" --arg members "$MEMBERS" --arg visitors "$VISITORS" '[
  [$ops      | split(",") | map({permission: "operator", xuid:.})],
  [$members  | split(",") | map({permission: "member", xuid:.})],
  [$visitors | split(",") | map({permission: "visitor", xuid:.})]
  ]| flatten' > permissions.json
fi

# populate whitelist from env variables
if [ -n "$WHITE_LIST_USERS" ]; then
  echo "Setting whitelist"
  rm -rf whitelist.json
  jq -n --arg users "$WHITE_LIST_USERS" '$users | split(",") | map({"name": .})' > whitelist.json
  # flag whitelist to true so the server properties process correctly
  export WHITE_LIST=true
fi

# populate server.propertes from env variables
set-property --file server.properties --bulk /etc/bds-property-definitions.json

# use vmtouch to keep the world files loaded in memory...
if [[ ${KEEP_WORLD_IN_RAM^^} == TRUE ]]; then
  echo "vmtouch: --- Attempting to keep world files in RAM ---"
  vmtouch -ld /data/worlds
fi

# Start the server
exec wine64 "bedrock_server.exe" "$@"