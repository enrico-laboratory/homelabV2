SOPS_KEY_PATH := /Users/$(USER)/.sops/age_key.txt
PUBLIC_KEY := $(shell age-keygen -y $(SOPS_KEY_PATH))

TFVARS_FILE := terraform.tfvars
ENCRYPTED_FILE := $(TFVARS_FILE).enc
DECRYPTED_FILE := $(TFVARS_FILE).decrypted

encrypt_tfvars:
	@sops --age "$(PUBLIC_KEY)" \
		  -e $(TFVARS_FILE) > $(ENCRYPTED_FILE)

decrypt_tfvars:
	SOPS_AGE_KEY_FILE=$(SOPS_KEY_PATH) sops -d $(ENCRYPTED_FILE) > $(DECRYPTED_FILE)

apply:
	@tmpfile=$$(mktemp) && \
	SOPS_AGE_KEY_FILE=$(SOPS_KEY_PATH) sops -d $(ENCRYPTED_FILE) > $$tmpfile && \
	terraform apply -y -var-file=$$tmpfile || \
	rm -f $$tmpfile

