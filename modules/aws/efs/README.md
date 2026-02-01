<!-- BEGIN_TF_DOCS -->
# efs



## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_efs_access_point.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_access_point) | resource |
| [aws_efs_file_system.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_file_system) | resource |
| [aws_efs_mount_target.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_mount_target) | resource |
| [aws_security_group.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allowed_security_group_ids"></a> [allowed\_security\_group\_ids](#input\_allowed\_security\_group\_ids) | Security group IDs allowed to access EFS | `list(string)` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (dev, staging, prod) | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name identifier for the EFS filesystem | `string` | n/a | yes |
| <a name="input_project"></a> [project](#input\_project) | Project name for resource naming | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | List of subnet IDs for mount targets | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID | `string` | n/a | yes |
| <a name="input_performance_mode"></a> [performance\_mode](#input\_performance\_mode) | EFS performance mode (generalPurpose or maxIO) | `string` | `"generalPurpose"` | no |
| <a name="input_posix_user_gid"></a> [posix\_user\_gid](#input\_posix\_user\_gid) | POSIX group ID for the access point | `number` | `1000` | no |
| <a name="input_posix_user_uid"></a> [posix\_user\_uid](#input\_posix\_user\_uid) | POSIX user ID for the access point | `number` | `1000` | no |
| <a name="input_provisioned_throughput_in_mibps"></a> [provisioned\_throughput\_in\_mibps](#input\_provisioned\_throughput\_in\_mibps) | Provisioned throughput in MiB/s (only used if throughput\_mode is provisioned) | `number` | `null` | no |
| <a name="input_root_directory_path"></a> [root\_directory\_path](#input\_root\_directory\_path) | Path for the access point root directory | `string` | `"/data"` | no |
| <a name="input_root_directory_permissions"></a> [root\_directory\_permissions](#input\_root\_directory\_permissions) | Permissions for the root directory | `string` | `"755"` | no |
| <a name="input_throughput_mode"></a> [throughput\_mode](#input\_throughput\_mode) | EFS throughput mode (bursting, provisioned, or elastic) | `string` | `"bursting"` | no |
| <a name="input_transition_to_ia"></a> [transition\_to\_ia](#input\_transition\_to\_ia) | Lifecycle policy for transitioning to Infrequent Access | `string` | `"AFTER_30_DAYS"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access_point_arn"></a> [access\_point\_arn](#output\_access\_point\_arn) | ARN of the EFS access point |
| <a name="output_access_point_id"></a> [access\_point\_id](#output\_access\_point\_id) | ID of the EFS access point |
| <a name="output_dns_name"></a> [dns\_name](#output\_dns\_name) | DNS name of the EFS filesystem |
| <a name="output_file_system_arn"></a> [file\_system\_arn](#output\_file\_system\_arn) | ARN of the EFS filesystem |
| <a name="output_file_system_id"></a> [file\_system\_id](#output\_file\_system\_id) | ID of the EFS filesystem |
| <a name="output_mount_target_ids"></a> [mount\_target\_ids](#output\_mount\_target\_ids) | IDs of the EFS mount targets |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group ID for EFS mount targets |
<!-- END_TF_DOCS -->