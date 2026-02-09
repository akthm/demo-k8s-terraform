################################################################################
# OCI Bastion Module - Outputs
################################################################################

output "bastion_id" {
  description = "The OCID of the bastion"
  value       = oci_bastion_bastion.main.id
}

output "bastion_name" {
  description = "The name of the bastion"
  value       = oci_bastion_bastion.main.name
}

output "bastion_state" {
  description = "The current state of the bastion"
  value       = oci_bastion_bastion.main.state
}

output "bastion_lifecycle_details" {
  description = "Lifecycle details of the bastion"
  value       = oci_bastion_bastion.main.lifecycle_details
}

output "bastion_private_endpoint_ip" {
  description = "The private IP address of the bastion endpoint"
  value       = oci_bastion_bastion.main.private_endpoint_ip_address
}

# Helper output for session creation command
output "session_create_command_template" {
  description = "Template command to create a bastion session"
  value       = <<-EOT
    # Create a managed SSH session to a target instance:
    oci bastion session create-managed-ssh \
      --bastion-id ${oci_bastion_bastion.main.id} \
      --target-resource-id <INSTANCE_OCID> \
      --target-os-username opc \
      --session-ttl-in-seconds 1800 \
      --key-type PUB \
      --ssh-public-key-file ~/.ssh/id_rsa.pub

    # Then use the SSH command provided in the session output
  EOT
}
