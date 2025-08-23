edit rhsm_secrets.yml file to include your red hat login and password, then encrypt it with

ansible-vault encrypt rhsm_secrets.yml

edit quay_secrets.yml file to include your quay robotoken username and token, then encrypt it with 

ansible-vault encrypt quay_secrets.yml
