output "instance_id" {
  value = aws_instance.ai_observability.id
}

output "public_ip" {
  value = aws_instance.ai_observability.public_ip
}

output "langfuse_url" {
  description = "Langfuse UI (traces, prompts, evals). Allow ~5-8 min after apply for first boot."
  value       = "http://${aws_instance.ai_observability.public_ip}:3000"
}

output "grafana_url" {
  description = "Grafana cost dashboards (user: admin)"
  value       = "http://${aws_instance.ai_observability.public_ip}:3001"
}

output "credentials_command" {
  description = "Run this to fetch all generated credentials (admin login, Grafana password, Langfuse API keys)"
  value       = var.key_name != null ? "ssh -i <your-key.pem> ubuntu@${aws_instance.ai_observability.public_ip} 'sudo cat /opt/ai-observability/credentials.txt'" : "SSH disabled (key_name=null) - use EC2 Session Manager or set key_name"
}
