<!-- BEGIN_TF_DOCS -->
# ecs-service



## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_service.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_lb_listener_rule.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_target_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_id"></a> [cluster\_id](#input\_cluster\_id) | ECS cluster ID | `string` | n/a | yes |
| <a name="input_container_image"></a> [container\_image](#input\_container\_image) | Docker image for the container | `string` | n/a | yes |
| <a name="input_container_port"></a> [container\_port](#input\_container\_port) | Port the container listens on | `number` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (dev, staging, prod) | `string` | n/a | yes |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | List of private subnet IDs for the ECS tasks | `list(string)` | n/a | yes |
| <a name="input_project"></a> [project](#input\_project) | Project name for resource naming | `string` | n/a | yes |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | List of security group IDs for the ECS tasks | `list(string)` | n/a | yes |
| <a name="input_service_name"></a> [service\_name](#input\_service\_name) | Name of the ECS service | `string` | n/a | yes |
| <a name="input_task_execution_role_arn"></a> [task\_execution\_role\_arn](#input\_task\_execution\_role\_arn) | ARN of the task execution role | `string` | n/a | yes |
| <a name="input_task_role_arn"></a> [task\_role\_arn](#input\_task\_role\_arn) | ARN of the task role | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID for the target group | `string` | n/a | yes |
| <a name="input_alb_listener_arn"></a> [alb\_listener\_arn](#input\_alb\_listener\_arn) | ARN of the ALB HTTPS listener | `string` | `null` | no |
| <a name="input_container_command"></a> [container\_command](#input\_container\_command) | Command to run in the container (overrides image CMD) | `list(string)` | `null` | no |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | CPU units for the task (256, 512, 1024, 2048, 4096) | `number` | `256` | no |
| <a name="input_create_alb_target_group"></a> [create\_alb\_target\_group](#input\_create\_alb\_target\_group) | Create an ALB target group for this service | `bool` | `true` | no |
| <a name="input_desired_count"></a> [desired\_count](#input\_desired\_count) | Desired number of tasks | `number` | `1` | no |
| <a name="input_efs_volumes"></a> [efs\_volumes](#input\_efs\_volumes) | EFS volumes to mount in the container | <pre>list(object({<br/>    name            = string<br/>    file_system_id  = string<br/>    access_point_id = string<br/>    container_path  = string<br/>    read_only       = optional(bool, false)<br/>  }))</pre> | `[]` | no |
| <a name="input_environment_variables"></a> [environment\_variables](#input\_environment\_variables) | Environment variables for the container | `map(string)` | `{}` | no |
| <a name="input_health_check"></a> [health\_check](#input\_health\_check) | Container health check configuration | <pre>object({<br/>    command      = list(string)<br/>    interval     = number<br/>    timeout      = number<br/>    retries      = number<br/>    start_period = number<br/>  })</pre> | `null` | no |
| <a name="input_health_check_matcher"></a> [health\_check\_matcher](#input\_health\_check\_matcher) | HTTP status codes for healthy response | `string` | `"200-399"` | no |
| <a name="input_health_check_path"></a> [health\_check\_path](#input\_health\_check\_path) | Health check path for the target group | `string` | `"/"` | no |
| <a name="input_host_header"></a> [host\_header](#input\_host\_header) | Host header for ALB listener rule routing | `string` | `null` | no |
| <a name="input_listener_rule_priority"></a> [listener\_rule\_priority](#input\_listener\_rule\_priority) | Priority for the ALB listener rule | `number` | `100` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | CloudWatch log retention in days | `number` | `30` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Memory in MB for the task | `number` | `512` | no |
| <a name="input_secrets"></a> [secrets](#input\_secrets) | Secrets from Secrets Manager or SSM Parameter Store (key = env var name, value = ARN) | `map(string)` | `{}` | no |
| <a name="input_sidecar_containers"></a> [sidecar\_containers](#input\_sidecar\_containers) | Additional sidecar containers to run alongside the main container | <pre>list(object({<br/>    name                  = string<br/>    image                 = string<br/>    essential             = optional(bool, true)<br/>    port                  = optional(number)<br/>    user                  = optional(string) # User to run the container as (e.g., "999:999")<br/>    environment_variables = optional(map(string), {})<br/>    secrets               = optional(map(string), {})<br/>    command               = optional(list(string))<br/>    health_check = optional(object({<br/>      command      = list(string)<br/>      interval     = number<br/>      timeout      = number<br/>      retries      = number<br/>      start_period = number<br/>    }))<br/>    mount_points = optional(list(object({<br/>      volume_name    = string<br/>      container_path = string<br/>      read_only      = optional(bool, false)<br/>    })), [])<br/>    depends_on = optional(list(object({<br/>      container_name = string<br/>      condition      = string # START, COMPLETE, SUCCESS, HEALTHY<br/>    })), [])<br/>  }))</pre> | `[]` | no |
| <a name="input_target_group_protocol_version"></a> [target\_group\_protocol\_version](#input\_target\_group\_protocol\_version) | Protocol version for the target group (HTTP1, HTTP2, or GRPC). HTTP2 required for gRPC services. | `string` | `"HTTP1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_log_group_arn"></a> [log\_group\_arn](#output\_log\_group\_arn) | The ARN of the CloudWatch log group |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | The name of the CloudWatch log group |
| <a name="output_service_arn"></a> [service\_arn](#output\_service\_arn) | The ARN of the ECS service |
| <a name="output_service_id"></a> [service\_id](#output\_service\_id) | The ID of the ECS service |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | The name of the ECS service |
| <a name="output_target_group_arn"></a> [target\_group\_arn](#output\_target\_group\_arn) | The ARN of the ALB target group |
| <a name="output_task_definition_arn"></a> [task\_definition\_arn](#output\_task\_definition\_arn) | The ARN of the task definition |
| <a name="output_task_definition_family"></a> [task\_definition\_family](#output\_task\_definition\_family) | The family of the task definition |
<!-- END_TF_DOCS -->