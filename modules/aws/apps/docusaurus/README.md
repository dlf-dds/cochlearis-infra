<!-- BEGIN_TF_DOCS -->
# docusaurus

Application module for deploying docusaurus to ECS Fargate.



## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_lb_listener_certificate.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_certificate) | resource |
| [aws_route53_record.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alb_dns_name"></a> [alb\_dns\_name](#input\_alb\_dns\_name) | ALB DNS name for Route53 alias | `string` | n/a | yes |
| <a name="input_alb_listener_arn"></a> [alb\_listener\_arn](#input\_alb\_listener\_arn) | ALB HTTPS listener ARN | `string` | n/a | yes |
| <a name="input_alb_security_group_id"></a> [alb\_security\_group\_id](#input\_alb\_security\_group\_id) | ALB security group ID | `string` | n/a | yes |
| <a name="input_alb_zone_id"></a> [alb\_zone\_id](#input\_alb\_zone\_id) | ALB hosted zone ID for Route53 alias | `string` | n/a | yes |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Base domain name | `string` | n/a | yes |
| <a name="input_ecs_cluster_id"></a> [ecs\_cluster\_id](#input\_ecs\_cluster\_id) | ECS cluster ID | `string` | n/a | yes |
| <a name="input_ecs_tasks_security_group_id"></a> [ecs\_tasks\_security\_group\_id](#input\_ecs\_tasks\_security\_group\_id) | Security group ID for ECS tasks | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name | `string` | n/a | yes |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | Private subnet IDs for ECS tasks | `list(string)` | n/a | yes |
| <a name="input_project"></a> [project](#input\_project) | Project name | `string` | n/a | yes |
| <a name="input_route53_zone_id"></a> [route53\_zone\_id](#input\_route53\_zone\_id) | Route53 hosted zone ID | `string` | n/a | yes |
| <a name="input_task_execution_role_arn"></a> [task\_execution\_role\_arn](#input\_task\_execution\_role\_arn) | ECS task execution role ARN | `string` | n/a | yes |
| <a name="input_task_role_arn"></a> [task\_role\_arn](#input\_task\_role\_arn) | ECS task role ARN | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID | `string` | n/a | yes |
| <a name="input_container_image"></a> [container\_image](#input\_container\_image) | Container image for Docusaurus | `string` | `"nginx:alpine"` | no |
| <a name="input_desired_count"></a> [desired\_count](#input\_desired\_count) | Number of tasks to run | `number` | `1` | no |
| <a name="input_ecs_cpu"></a> [ecs\_cpu](#input\_ecs\_cpu) | CPU units for the task | `number` | `256` | no |
| <a name="input_ecs_memory"></a> [ecs\_memory](#input\_ecs\_memory) | Memory (MB) for the task | `number` | `512` | no |
| <a name="input_listener_rule_priority"></a> [listener\_rule\_priority](#input\_listener\_rule\_priority) | Priority for ALB listener rule | `number` | `400` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_domain"></a> [domain](#output\_domain) | Docusaurus domain |
| <a name="output_url"></a> [url](#output\_url) | Docusaurus URL |
<!-- END_TF_DOCS -->