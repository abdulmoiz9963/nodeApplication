variable "repository_names" {
  description = "List of ECR repository names"
  type        = list(string)
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
}
