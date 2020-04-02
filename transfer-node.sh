#!/bin/bash
# Auto transfer Nucypher node to another machine #

# Specify your passwords
KEYRING_PASSWORD=$1
WORKER_ETH_PASSWORD=$2
GETH_SERVICE_NAME="geth.service"
GETH_NODE_MODE="fast"
WORKER_SERVICE_NAME="ursula-worker.service"

REQUIREMENTS="ethereum curl jq python3-pip libffi-dev python3-virtualenv build-essential python3-dev python3-venv"
green="\e[92m"
red="\e[91m"
normal="\e[39m"

# Check if user is root
if [[ $USER == "root"  ]]; then
  SUDO=""
else
  SUDO="sudo"
fi

echo -e $green"Installing requirements:"
echo -e $normal"ethereum\ncurl\njq\npython3-pip\nlibffi-dev\npython3-virtualenv\nbuild-essential\npython3-dev\npython3-venv"
$SUDO apt install software-properties-common -y
$SUDO add-apt-repository -y ppa:ethereum/ethereum
$SUDO apt update
$SUDO apt install $REQUIREMENTS -y

NODE_IP=`curl -s https://api.ipify.org`
echo -e $green"Current user: $USER, current external IP: $NODE_IP"

echo -e $normal"Trying to find backup archive"
BACKUP_ARCHIVE=`find $HOME -type f -name nucypher_*.tar.gz`
if [ -f "$BACKUP_ARCHIVE" ]; then
  echo -e $green"Backup file found $BACKUP_ARCHIVE"
else
  echo -e $red"Can't find backup file"
  exit 1
fi

echo -e $green"Extracting archive to home folder"
cd $HOME && tar xzf $BACKUP_ARCHIVE

echo -e $green"Creating virtual environment and install Nucpyher"
$(which python3) -m venv ~/nucypher-venv
source ~/nucypher-venv/bin/activate
pip3 install nucypher


URSULA_JSON="$HOME/.local/share/nucypher/ursula.json"
echo -e $green"Replacing home path and external ip in $URSULA_JSON"
JSON_DATA=`cat $URSULA_JSON | \
jq '.keyring_root="'$HOME'/.local/share/nucypher/keyring"' | \
jq '.node_storage.storage_root="'$HOME'/.local/share/nucypher/known_nodes"' | \
jq '.node_storage.metadata_dir="'$HOME'/.local/share/nucypher/known_nodes/metadata"' | \
jq '.node_storage.certificates_dir="'$HOME'/.local/share/nucypher/known_nodes/certificates"' | \
jq '.provider_uri="'$HOME'/.ethereum/goerli/geth.ipc"' | \
jq '.rest_host="'$NODE_IP'"' | \
jq '.db_filepath="'$HOME'/.local/share/nucypher/ursula.db"'`
echo $JSON_DATA | jq '.' > $URSULA_JSON

STAKER_JSON="$HOME/.local/share/nucypher/stakeholder.json"
if [[ -f "$STAKER_JSON" ]]; then
  echo -e $green"Replacing home path in $STAKER_JSON"
  STAKER_DATA=`cat $STAKER_JSON | jq '.provider_uri="'$HOME'/.ethereum/goerli/geth.ipc"'`
  echo $STAKER_DATA | jq '.' > $STAKER_JSON
fi


echo -e $green"Creating '$GETH_SERVICE_NAME'"
$SUDO echo "[Unit]
Description=geth-light-node

[Service]
User=$USER
ExecStart=/usr/bin/geth --goerli --syncmode $GETH_NODE_MODE --nousb
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target" > $GETH_SERVICE_NAME
$SUDO chmod 600 $GETH_SERVICE_NAME
$SUDO mv $GETH_SERVICE_NAME /etc/systemd/system/


echo -e $green"Creating '$WORKER_SERVICE_NAME"
$SUDO echo "[Unit]
Description="Run 'Ursula', a NuCypher Staking Node."
After=$GETH_SERVICE_NAME

[Service]
User=$USER
Type=simple
Environment=NUCYPHER_KEYRING_PASSWORD=$KEYRING_PASSWORD
Environment=NUCYPHER_WORKER_ETH_PASSWORD=$WORKER_ETH_PASSWORD
ExecStart=$HOME/nucypher-venv/bin/nucypher ursula run --teacher gemini.nucypher.network:9151 --poa
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target" > $WORKER_SERVICE_NAME
$SUDO chmod 600 $WORKER_SERVICE_NAME
$SUDO mv $WORKER_SERVICE_NAME /etc/systemd/system/

echo -e $green"Starting geth service"
$SUDO systemctl daemon-reload
$SUDO systemctl enable $GETH_SERVICE_NAME 
$SUDO systemctl enable $WORKER_SERVICE_NAME 
$SUDO systemctl start $GETH_SERVICE_NAME

echo "Waiting while Geth start sync"
sleep 10

echo -e $green"Waiting for Geth synchronization"
GETH_IP_PATH=`cat $URSULA_JSON | jq .provider_uri | tr -d '"'`
GETH_TIMESTAMP_DIFF=`geth --exec "Date.now()/1000 - eth.getBlock('latest').timestamp" attach $GETH_IP_PATH`
while [[ $GETH_TIMESTAMP_DIFF > 120 ]]; do
  GETH_CURRENT_BLOCK=`geth --exec "eth.blockNumber" attach $GETH_IP_PATH`
  echo "Current block: $GETH_CURRENT_BLOCK"
  sleep 5
  GETH_TIMESTAMP_DIFF=`geth --exec "Date.now()/1000 - eth.getBlock('latest').timestamp" attach $GETH_IP_PATH`
done

echo -e $green"Geth synced --> Ursula service restart"
$SUDO systemctl start $WORKER_SERVICE_NAME 

echo -e $green"If Ursula status is online, then all started properly"
$SUDO systemctl status $WORKER_SERVICE_NAME 
