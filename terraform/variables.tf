variable "region" {
  default = "ap-south-1"
}

variable "ami_id" {
  description = "Ubuntu 22.04 LTS - ap-south-1"
  default     = "ami-0f58b397bc5c1f2e8"
}

variable "key_name" {
  default = "devops-intern-key"
}

variable "worker_instance_type" {
  description = "Inference worker needs min 4GB RAM for Gemma model"
  default     = "t2.medium"
}
