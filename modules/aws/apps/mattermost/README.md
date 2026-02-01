<!-- BEGIN_TF_DOCS -->
# mattermost

Application module for deploying mattermost to ECS Fargate.



## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_iam_role_policy.secrets_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_route53_record.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_secretsmanager_secret.database_url](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.database_url](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alb_dns_name"></a> [alb\_dns\_name](#input\_alb\_dns\_name) | DNS name of the ALB | `string` | n/a | yes |
| <a name="input_alb_listener_arn"></a> [alb\_listener\_arn](#input\_alb\_listener\_arn) | ARN of the ALB HTTPS listener | `string` | n/a | yes |
| <a name="input_alb_security_group_id"></a> [alb\_security\_group\_id](#input\_alb\_security\_group\_id) | Security group ID of the ALB | `string` | n/a | yes |
| <a name="input_alb_zone_id"></a> [alb\_zone\_id](#input\_alb\_zone\_id) | Route53 zone ID of the ALB | `string` | n/a | yes |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Root domain name (e.g., example.com) | `string` | n/a | yes |
| <a name="input_ecs_cluster_id"></a> [ecs\_cluster\_id](#input\_ecs\_cluster\_id) | ECS cluster ID | `string` | n/a | yes |
| <a name="input_ecs_tasks_security_group_id"></a> [ecs\_tasks\_security\_group\_id](#input\_ecs\_tasks\_security\_group\_id) | Security group ID for ECS tasks | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (dev, staging, prod) | `string` | n/a | yes |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | List of private subnet IDs | `list(string)` | n/a | yes |
| <a name="input_project"></a> [project](#input\_project) | Project name for resource naming | `string` | n/a | yes |
| <a name="input_route53_zone_id"></a> [route53\_zone\_id](#input\_route53\_zone\_id) | Route53 hosted zone ID | `string` | n/a | yes |
| <a name="input_task_execution_role_arn"></a> [task\_execution\_role\_arn](#input\_task\_execution\_role\_arn) | ARN of the ECS task execution role | `string` | n/a | yes |
| <a name="input_task_execution_role_name"></a> [task\_execution\_role\_name](#input\_task\_execution\_role\_name) | Name of the ECS task execution role | `string` | n/a | yes |
| <a name="input_task_role_arn"></a> [task\_role\_arn](#input\_task\_role\_arn) | ARN of the ECS task role | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID | `string` | n/a | yes |
| <a name="input_certificate_arn"></a> [certificate\_arn](#input\_certificate\_arn) | ARN of an existing ACM certificate. Required when create\_certificate is false. | `string` | `null` | no |
| <a name="input_container_image"></a> [container\_image](#input\_container\_image) | Docker image for Mattermost | `string` | `"mattermost/mattermost-team-edition:latest"` | no |
| <a name="input_create_certificate"></a> [create\_certificate](#input\_create\_certificate) | Whether to create a new ACM certificate. Set to false when providing certificate\_arn. | `bool` | `true` | no |
| <a name="input_db_allocated_storage"></a> [db\_allocated\_storage](#input\_db\_allocated\_storage) | Allocated storage in GB | `number` | `20` | no |
| <a name="input_db_deletion_protection"></a> [db\_deletion\_protection](#input\_db\_deletion\_protection) | Enable deletion protection | `bool` | `false` | no |
| <a name="input_db_instance_class"></a> [db\_instance\_class](#input\_db\_instance\_class) | RDS instance class | `string` | `"db.t3.micro"` | no |
| <a name="input_db_multi_az"></a> [db\_multi\_az](#input\_db\_multi\_az) | Enable Multi-AZ deployment | `bool` | `false` | no |
| <a name="input_db_skip_final_snapshot"></a> [db\_skip\_final\_snapshot](#input\_db\_skip\_final\_snapshot) | Skip final snapshot when destroying | `bool` | `true` | no |
| <a name="input_desired_count"></a> [desired\_count](#input\_desired\_count) | Desired number of ECS tasks | `number` | `1` | no |
| <a name="input_ecs_cpu"></a> [ecs\_cpu](#input\_ecs\_cpu) | CPU units for the ECS task | `number` | `512` | no |
| <a name="input_ecs_memory"></a> [ecs\_memory](#input\_ecs\_memory) | Memory in MB for the ECS task | `number` | `1024` | no |
| <a name="input_enable_open_server"></a> [enable\_open\_server](#input\_enable\_open\_server) | Allow open signup (anyone can create an account) | `bool` | `true` | no |
| <a name="input_listener_rule_priority"></a> [listener\_rule\_priority](#input\_listener\_rule\_priority) | Priority for the ALB listener rule | `number` | `250` | no |
| <a name="input_oidc_client_id"></a> [oidc\_client\_id](#input\_oidc\_client\_id) | OIDC client ID | `string` | `""` | no |
| <a name="input_oidc_client_secret_arn"></a> [oidc\_client\_secret\_arn](#input\_oidc\_client\_secret\_arn) | ARN of the Secrets Manager secret containing OIDC client credentials (JSON with 'client\_secret' key) | `string` | `""` | no |
| <a name="input_oidc_issuer"></a> [oidc\_issuer](#input\_oidc\_issuer) | OIDC issuer URL (e.g., https://auth.dev.example.com) | `string` | `""` | no |
| <a name="input_subdomain"></a> [subdomain](#input\_subdomain) | Subdomain for Mattermost (e.g., 'mm' results in mm.dev.example.com) | `string` | `"mm"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_certificate_arn"></a> [certificate\_arn](#output\_certificate\_arn) | ARN of the ACM certificate |
| <a name="output_certificate_validation_arn"></a> [certificate\_validation\_arn](#output\_certificate\_validation\_arn) | ARN of the validated ACM certificate |
| <a name="output_db_address"></a> [db\_address](#output\_db\_address) | Database address |
| <a name="output_db_endpoint"></a> [db\_endpoint](#output\_db\_endpoint) | Database endpoint |
| <a name="output_domain"></a> [domain](#output\_domain) | Domain name for Mattermost |
| <a name="output_url"></a> [url](#output\_url) | URL for Mattermost |
<!-- END_TF_DOCS -->