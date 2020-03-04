# nucypher-node-migrate
Migrate Nucypher node to another server

## Description
The script is designed to deploy the Nucypher node backup on a new machine

## How to use
1. Make backup using command below  
`curl -s https://raw.githubusercontent.com/c29r3/nucypher-backup-script/master/backup.sh | bash`

2. Move the backup to the machine where you plan to deploy it  
`scp ~/*.tar.gz user@new_machine_ip:~/`   
`user` - username on remote machine  
`new_machine_ip` - ip of remote machine  

3. Log in via ssh on a new machine and run command below  
`curl -s https://raw.githubusercontent.com/c29r3/nucypher-node-migrate/master/transfer-node.sh | bash KEYRING_PASSWORD WORKER_ETH_PASSWORD`    
  
Don't forget to replace `KEYRING_PASSWORD` and `WORKER_ETH_PASSWORD` on your values


## Note
I recommend forking both repositories and replacing links in steps 1 and 3
