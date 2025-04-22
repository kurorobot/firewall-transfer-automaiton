output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.streamlit_app.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_eip.streamlit_eip.public_ip
}

output "streamlit_url" {
  description = "URL to access the Streamlit application"
  value       = "http://${aws_eip.streamlit_eip.public_ip}:8501"
}
