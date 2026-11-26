ansible_inventory_path = inventories
ansible_inventory ?= hosts.yaml
ansible_user ?=
args ?=
playbooks_path = playbooks
sops_key_path_env_var = SOPS_AGE_KEY_FILE=$(HOME)/.config/sops/age/keys.txt
bin_path = $(shell which ansible-playbook)

# Generic runner
run:
	$(sops_key_path_env_var) \
	$(bin_path) -i $(ansible_inventory_path)/$(ansible_inventory) $(playbooks_path)/$(play).yaml --private-key ~/.ssh/id_rsa $(ansible_user) $(args)
	# Convenience wrappers
sops_test:      ; $(MAKE) run play=sops_test
dns_config:     ; $(MAKE) run play=dns_2_config
cronjob:        ; $(MAKE) run play=cronjob
update_hosts:   ; $(MAKE) run play=update_hosts
ops:            ; $(MAKE) run play=ops
# ops as router; parallel mode by default, cutover: make router args="-e router_cutover=true"
router:         ; $(MAKE) run play=router
compose_apps:   ; $(MAKE) run play=compose_apps
ai_config:      ; $(MAKE) run play=ai_config
ai_compose:     ; $(MAKE) run play=compose_personal_ai
website_update: ; $(MAKE) run play=compose_website_update
nas_config:     ; $(MAKE) run play=nas_config
pve_bootstrap:  ; $(MAKE) run play=pve_1_bootstrap_node3 ansible_user="--user root"
pve_monitoring: ; $(MAKE) run play=pve_monitoring ansible_user="--user root"
truenas_monitoring: ; $(MAKE) run play=truenas_monitoring
