sops_key_path_env_var = SOPS_AGE_KEY_FILE=$(HOME)/.config/sops/age/keys.txt
sops_file = auth.enc.yaml
bin_path = $(shell which terraform)
auto_approve ?=

# auth.enc.yaml holds PROXMOX_VE_USERNAME, PROXMOX_VE_PASSWORD and TF_VAR_github_token (see auth.example.yaml).
# SOPS_AGE_KEY_FILE is also passed to terraform (sops provider reads the CCM config from k8s-talos/).
# The age private key for Flux is read straight from the key file, never stored in the encrypted file.
tf:
	@export TF_VAR_sops_age_key="$$(cat $(HOME)/.sops/age_key.txt)"; \
	$(sops_key_path_env_var) sops -d --output-type dotenv $(sops_file) > /tmp/talos_secrets.env && \
	$(sops_key_path_env_var) env $$(cat /tmp/talos_secrets.env) $(bin_path) $(action) $(auto_approve); \
	rc=$$?; rm -f /tmp/talos_secrets.env; exit $$rc

tf-init: ; $(MAKE) tf action=init
tf-validate: ; $(MAKE) tf action=validate
tf-plan: ; $(MAKE) tf action=plan
tf-apply: ; $(MAKE) tf action=apply

# Write talosconfig / kubeconfig out of state (not committed)
configs:
	@mkdir -p $(HOME)/.talos && \
	$(bin_path) output -raw talosconfig > $(HOME)/.talos/config && \
	$(bin_path) output -raw kubeconfig > $(HOME)/.kube/talos-config && \
	chmod 600 $(HOME)/.talos/config $(HOME)/.kube/talos-config && \
	echo "export KUBECONFIG=$(HOME)/.kube/talos-config"
