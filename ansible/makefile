ansible_inventory_path = inventories/hosts.yaml
playbooks_path = playbooks
sops_key_path_env_var = SOPS_AGE_KEY_FILE=$(HOME)/.config/sops/age/keys.txt
bin_path = $(shell which ansible-playbook)

# Generic runner
run:
	$(sops_key_path_env_var) \
	$(bin_path) -i $(ansible_inventory_path) $(playbooks_path)/$(play).yaml

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
