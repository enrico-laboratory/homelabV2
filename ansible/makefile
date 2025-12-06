ansible_inventory_path = inventories
ansible_inventory ?= hosts.yaml
ansible_user ?=
playbooks_path = playbooks
sops_key_path_env_var = SOPS_AGE_KEY_FILE=$(HOME)/.config/sops/age/keys.txt
bin_path = $(shell which ansible-playbook)

# Generic runner
run:
	$(sops_key_path_env_var) \
	$(bin_path) -i $(ansible_inventory_path)/$(ansible_inventory) $(playbooks_path)/$(play).yaml --private-key ~/.ssh/id_rsa $(ansible_user)
	# Convenience wrappers
sops_test:      ; $(MAKE) run play=sops_test
dns_config:     ; $(MAKE) run play=dns_2_config
cronjob:        ; $(MAKE) run play=cronjob
update_hosts:   ; $(MAKE) run play=update_hosts
k3s_config:     ; $(MAKE) run play=k3s_1_config
ops:            ; $(MAKE) run play=ops
compose_apps:   ; $(MAKE) run play=compose_apps
ai_config:      ; $(MAKE) run play=ai_config
ai_compose:     ; $(MAKE) run play=compose_personal_ai
website_update: ; $(MAKE) run play=compose_website_update
pve_bootstrap:  ; $(MAKE) run play=pve_1_bootstrap_node3 ansible_inventory=hosts_bare_metal.yaml ansible_user="--user root"

# Fails if run from makefile
#k3s_ansible:
#	$(sops_key_path_env_var) \
#	cd playbooks/k3s-ansible && \
#	$(bin_path) -i ../../$(ansible_inventory_path)/$(ansible_inventory) \
#	$(playbooks_path)/site.yml \
#	--private-key ~/.ssh/id_rsa $(ansible_user)
