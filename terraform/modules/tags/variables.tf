variable "project" {
  description = "Project name"
  type        = string
  default     = "netlix"
}

variable "tags" {
  description = "Additional tags to merge"
  type        = map(string)
  default     = {}
}
