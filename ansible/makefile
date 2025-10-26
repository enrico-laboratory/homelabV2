ansible_inventory_path = inventories/hosts.yaml
playbooks_path = playbooks
sops_key_path_env_var = SOPS_AGE_KEY_FILE=/home/$$USER/.config/sops/age/keys.txt
bin_path = /home/$$USER/.local/bin/ansible-playbook

sops_test:
	$(sops_key_path_env_var) $(bin_path) -i $(ansible_inventory_path) $(playbooks_path)/sops_test.yaml

dns_config:
	$(sops_key_path_env_var) $(bin_path) -i $(ansible_inventory_path) $(playbooks_path)/dns_2_config.yaml

cronjob:
	$(sops_key_path_env_var) $(bin_path) -i $(ansible_inventory_path) $(playbooks_path)/cronjob.yaml

update_hosts:
	$(sops_key_path_env_var) $(bin_path) -i $(ansible_inventory_path) $(playbooks_path)/update_hosts.yaml | tee ansible.log

k3s_config:
	$(sops_key_path_env_var) $(bin_path) -i $(ansible_inventory_path) $(playbooks_path)/k3s_1_config.yaml

ops:
	$(sops_key_path_env_var) $(bin_path) -i $(ansible_inventory_path) $(playbooks_path)/ops.yaml

ops_compose:
	$(sops_key_path_env_var) $(bin_path) -i $(ansible_inventory_path) $(playbooks_path)/ops_compose.yaml
