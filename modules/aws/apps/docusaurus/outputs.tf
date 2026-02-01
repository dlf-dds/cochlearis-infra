output "url" {
  description = "Docusaurus URL"
  value       = "https://${local.domain}"
}

output "domain" {
  description = "Docusaurus domain"
  value       = local.domain
}
