# CloudFormation template — AWS Marketplace delivery

`ai-observability-stack.yaml` is the CloudFormation equivalent of the Terraform harness.
It exists because AWS Marketplace AMI products are delivered either as a **single AMI**
or as an **AMI + CloudFormation template** — Terraform is not a Marketplace delivery
method. Terraform remains the internal dev/test harness; this template is the
customer-facing deployment artifact.

## Deploy (test mode — works today, no product AMI needed)

Console: CloudFormation → Create stack → Upload template → fill parameters:

| Parameter | Example |
|---|---|
| VpcId / SubnetId | your default VPC + any public subnet |
| KeyName | `ai-obs-test-mumbai` (or your key pair in the region) |
| AllowedCIDR | `<your-ip>/32` or your ISP range, e.g. `171.76.0.0/16` |
| InstanceType | `t3.large` |

Or CLI:

```bash
aws cloudformation create-stack \
  --stack-name ai-observability \
  --template-body file://ai-observability-stack.yaml \
  --region ap-south-1 \
  --parameters \
    ParameterKey=VpcId,ParameterValue=vpc-XXXX \
    ParameterKey=SubnetId,ParameterValue=subnet-XXXX \
    ParameterKey=KeyName,ParameterValue=ai-obs-test-mumbai \
    ParameterKey=AllowedCIDR,ParameterValue=YOUR.IP.0.0/16
```

Stack completes in ~2 minutes; the application needs a further 5–8 minutes of
first-boot provisioning. Outputs include the Langfuse/Grafana URLs and the
credentials command. Delete the stack to stop billing.

In test mode the template resolves the latest Canonical Ubuntu 24.04 AMI via a
public SSM parameter and installs the stack at first boot — identical behavior
to the Terraform harness.

## Marketplace conversion (after the product AMI exists)

Three edits, marked with `MARKETPLACE` comments in the template:

1. Replace the `UbuntuAmiId` SSM parameter with the `RegionMap` mapping of the
   Marketplace-cloned product AMI IDs — one entry per region enabled in the
   Product Load Form (regions must match exactly).
2. Point `ImageId` at `!FindInMap [RegionMap, !Ref 'AWS::Region', AmiId]`.
3. Delete the `UserData` blob — the baked AMI carries the stack and runs the
   same secret-generation provisioning from a first-boot systemd unit.

Marketplace also requires the template to launch successfully via the
CloudFormation console in every enabled region, and the usage instructions to
document any IAM roles needed (this template needs none).
