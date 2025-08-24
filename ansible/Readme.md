Playbooks to manage lifecycle

bootc_update.yml : before running this edit to reflect the new version of the containerized OS you'd like to boot to next

inject_creds.yml : before running this put your robot credentials in vars/quay_secrets.yml and encrypt with `ansible-vault encrypt vars/inject_creds.yml`

inventory.yml : edit to reflect the IP of your VM and the location of your private ssh key

quadlet.yml : playbook to run an nginx server on your VM

rhsm_register.yml: before running this edit vars/rhsm_secrets.yml to reflect your Redhat username and password, and encrypt with `ansible-vault encrypt vars/rhsm_secrets.yml`
