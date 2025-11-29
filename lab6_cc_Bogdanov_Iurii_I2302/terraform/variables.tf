variable "aws_region" {
  description = "AWS region for lab 6"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for web server"
  type        = string
  default     = "t3.micro"
}
