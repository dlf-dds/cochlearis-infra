<!-- BEGIN_TF_DOCS -->
# governance



## Providers

| Name | Version |
|------|---------|
| <a name="provider_archive"></a> [archive](#provider\_archive) | n/a |
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_budgets_budget.monthly](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/budgets_budget) | resource |
| [aws_cloudwatch_event_rule.weekly_governance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.lifecycle_lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_log_group.lifecycle_lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_role.lifecycle_lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.lifecycle_lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_lambda_function.lifecycle_manager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_permission.eventbridge](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_sns_topic.governance_alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_subscription.email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [archive_file.lifecycle_lambda](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.lambda_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.lifecycle_lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name | `string` | n/a | yes |
| <a name="input_owner_email"></a> [owner\_email](#input\_owner\_email) | Infrastructure owner email for alerts | `string` | n/a | yes |
| <a name="input_project"></a> [project](#input\_project) | Project name | `string` | n/a | yes |
| <a name="input_cost_alert_thresholds"></a> [cost\_alert\_thresholds](#input\_cost\_alert\_thresholds) | Budget thresholds for cost alerts (percentages) | `list(number)` | <pre>[<br/>  50,<br/>  80,<br/>  100,<br/>  120<br/>]</pre> | no |
| <a name="input_enable_auto_termination"></a> [enable\_auto\_termination](#input\_enable\_auto\_termination) | Enable automatic termination of expired resources | `bool` | `false` | no |
| <a name="input_lifecycle_termination_days"></a> [lifecycle\_termination\_days](#input\_lifecycle\_termination\_days) | Days after creation to terminate temporary resources | `number` | `60` | no |
| <a name="input_lifecycle_warning_days"></a> [lifecycle\_warning\_days](#input\_lifecycle\_warning\_days) | Days before expiry to start sending warnings | `number` | `30` | no |
| <a name="input_monthly_budget_limit"></a> [monthly\_budget\_limit](#input\_monthly\_budget\_limit) | Monthly budget limit in USD | `number` | `200` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_budget_name"></a> [budget\_name](#output\_budget\_name) | Name of the monthly budget |
| <a name="output_eventbridge_rule_arn"></a> [eventbridge\_rule\_arn](#output\_eventbridge\_rule\_arn) | ARN of the weekly governance EventBridge rule |
| <a name="output_governance_tags"></a> [governance\_tags](#output\_governance\_tags) | Standard governance tags to apply to all resources |
| <a name="output_lambda_function_arn"></a> [lambda\_function\_arn](#output\_lambda\_function\_arn) | ARN of the lifecycle manager Lambda function |
| <a name="output_lambda_function_name"></a> [lambda\_function\_name](#output\_lambda\_function\_name) | Name of the lifecycle manager Lambda function |
| <a name="output_sns_topic_arn"></a> [sns\_topic\_arn](#output\_sns\_topic\_arn) | ARN of the governance alerts SNS topic |
| <a name="output_sns_topic_name"></a> [sns\_topic\_name](#output\_sns\_topic\_name) | Name of the governance alerts SNS topic |
<!-- END_TF_DOCS -->