# Packer — bake the AWS Marketplace AMI

Turns the proven bootstrap into a product AMI: application files and all Docker
images are **baked at build time**; secrets are still **generated at each
customer's first boot** (systemd unit `ai-observability-firstboot.service`),
satisfying the Marketplace no-hardcoded-secrets rule. Customer launches need no
internet downloads and reach a running stack in ~2–3 minutes.

```
packer/
├── ai-observability.pkr.hcl     # builder: Ubuntu 24.04 → product AMI (us-east-1)
└── scripts/
    ├── install-stack.sh         # BUILD time: app files, docker pull/build,
    │                            #   first-boot unit, Marketplace hardening
    └── firstboot.sh             # CUSTOMER first boot: secrets, .env,
                                 #   credentials.txt, docker compose up
```

## Prerequisites

- Packer >= 1.10 (https://developer.hashicorp.com/packer/install)
- AWS CLI credentials (same as Terraform); builds in **us-east-1**

## Build

```bash
cd packer
packer init .
packer validate .
packer build .
```

Takes ~15–25 minutes (image pulls dominate). Cost: ~$0.05 of temporary
t3.large time, auto-terminated. Output: the AMI ID, also written to
`build-manifest.json`.

## Verify the AMI before submission

1. Launch a test instance **from the new AMI** (console or CLI) in us-east-1
   with your key pair and the usual security group ports (22/3000/3001).
2. Within ~3 minutes: `http://<ip>:3000` (Langfuse) and `:3001` (Grafana) live.
3. `ssh ubuntu@<ip> 'sudo cat /opt/ai-observability/credentials.txt'` — fresh
   per-instance secrets prove first-boot generation works.
4. `sudo systemctl status ai-observability-firstboot` — `active (exited)`.
5. Terminate the test instance (the AMI remains).

## Marketplace hardening included

- No hardcoded secrets or `.env` in the image (placeholder used at build is removed)
- `PasswordAuthentication no`; Packer's temporary key removed
  (`ssh_clear_authorized_keys`), root/ubuntu `authorized_keys` deleted
- SSH host keys removed and `machine-id` truncated → regenerated per customer
- `cloud-init clean --logs` → buyer launch is a true first boot
- Product AMI snapshot left **unencrypted** (Marketplace requirement);
  buyer-side launches encrypt their volumes (our CFN/Terraform both do)

## After the build

1. Note the AMI ID from `build-manifest.json`
2. Fill it into `cloudformation/ai-observability-stack.yaml` RegionMap
   (Marketplace clones it to other enabled regions after submission)
3. Marketplace Management Portal → Server products → self-service listing:
   run **Test Add Version** (automated security scan) against the AMI,
   then complete the listing details
4. Rebuild + resubmit as a new version whenever the stack changes
   (bump `product_version`)

Keeping old AMIs costs ~$0.05/GB-month of snapshot data (₹100–250/month
typically); deregister superseded builds you no longer need.
