variable "name" {
  type = string
}

variable "base_image" {
  type = string
}

variable "prefix" {
  type = string
}

variable "env_vars" {
    type = map(string)
    default = null
}

variable "log_retention_in_days" {
  type    = number
  default = 30
}

variable "log_level" {
  type    = string
  default = "debug"
}
