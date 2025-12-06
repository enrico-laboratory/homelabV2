sops_key_path_env_var = SOPS_AGE_KEY_FILE=$(HOME)/.config/sops/age/keys.txt
sops_file = auth.enc.yaml
bin_path = $(shell which terraform)
auto_approve ?=
define sops_env
eval "$$($(sops_key_path_env_var) sops -d --output-type dotenv $(sops_file))"
endef

tf:
	@export TF_VAR_home_folder=$$HOME; \
	$(sops_key_path_env_var) sops -d --output-type dotenv $(sops_file) > /tmp/secrets.env && \
	env $$(cat /tmp/secrets.env) $(bin_path) $(action) $(auto_approve) && \
	rm /tmp/secrets.env

test-var:
	@$(call sops_env) && set

tf-init: ; $(MAKE) tf action=init
tf-plan: ; $(MAKE) tf action=plan
tf-apply: ; $(MAKE) tf action=apply auto_approve="-auto-approve"
