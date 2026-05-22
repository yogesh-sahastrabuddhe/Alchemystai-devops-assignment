output "api_gateway_public_ip" {
  value = aws_instance.api_gateway.public_ip
}

output "inference_worker_private_ip" {
  value = aws_instance.inference_worker.private_ip
}

output "caller_worker_private_ip" {
  value = aws_instance.caller_worker.private_ip
}

output "curl_test_command" {
  value = "curl -X POST http://${aws_instance.api_gateway.public_ip}:3111/v1/chat/completions -H 'Content-Type: application/json' -d '{\"messages\": [{\"role\": \"user\", \"content\": \"hello\"}]}'"
}
