<!-- BEGIN_TF_DOCS -->
# zitadel-oidc

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_zitadel"></a> [zitadel](#requirement\_zitadel) | ~> 2.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |
| <a name="provider_zitadel"></a> [zitadel](#provider\_zitadel) | ~> 2.0 |

## Resources

| Name | Type |
|------|------|
| [aws_secretsmanager_secret.bookstack_oidc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.mattermost_oidc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.zulip_oidc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.bookstack_oidc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.mattermost_oidc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.zulip_oidc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [zitadel_application_oidc.bookstack](https://registry.terraform.io/providers/zitadel/zitadel/latest/docs/resources/application_oidc) | resource |
| [zitadel_application_oidc.mattermost](https://registry.terraform.io/providers/zitadel/zitadel/latest/docs/resources/application_oidc) | resource |
| [zitadel_application_oidc.zulip](https://registry.terraform.io/providers/zitadel/zitadel/latest/docs/resources/application_oidc) | resource |
| [zitadel_project.main](https://registry.terraform.io/providers/zitadel/zitadel/latest/docs/resources/project) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_bookstack_domain"></a> [bookstack\_domain](#input\_bookstack\_domain) | BookStack domain (e.g., docs.dev.example.com) | `string` | n/a | yes |
| <a name="input_mattermost_domain"></a> [mattermost\_domain](#input\_mattermost\_domain) | Mattermost domain (e.g., mm.dev.example.com) | `string` | n/a | yes |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | Zitadel organization ID | `string` | n/a | yes |
| <a name="input_secret_prefix"></a> [secret\_prefix](#input\_secret\_prefix) | Prefix for Secrets Manager secret names | `string` | n/a | yes |
| <a name="input_zulip_domain"></a> [zulip\_domain](#input\_zulip\_domain) | Zulip domain (e.g., chat.dev.example.com) | `string` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Name of the Zitadel project to create | `string` | `"Cochlearis"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_bookstack_client_id"></a> [bookstack\_client\_id](#output\_bookstack\_client\_id) | BookStack OIDC client ID |
| <a name="output_bookstack_oidc_secret_arn"></a> [bookstack\_oidc\_secret\_arn](#output\_bookstack\_oidc\_secret\_arn) | ARN of the BookStack OIDC credentials secret |
| <a name="output_mattermost_client_id"></a> [mattermost\_client\_id](#output\_mattermost\_client\_id) | Mattermost OIDC client ID |
| <a name="output_mattermost_oidc_secret_arn"></a> [mattermost\_oidc\_secret\_arn](#output\_mattermost\_oidc\_secret\_arn) | ARN of the Mattermost OIDC credentials secret |
| <a name="output_project_id"></a> [project\_id](#output\_project\_id) | Zitadel project ID |
| <a name="output_zulip_client_id"></a> [zulip\_client\_id](#output\_zulip\_client\_id) | Zulip OIDC client ID |
| <a name="output_zulip_oidc_secret_arn"></a> [zulip\_oidc\_secret\_arn](#output\_zulip\_oidc\_secret\_arn) | ARN of the Zulip OIDC credentials secret |
<!-- END_TF_DOCS -->