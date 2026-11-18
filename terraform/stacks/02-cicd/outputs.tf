output "codebuild_project_name" {
  description = "Name of the CodeBuild runner project."
  value       = aws_codebuild_project.runner.name
}

output "runs_on_label" {
  description = "Label to use in GitHub Actions workflows (runs-on)."
  value       = "codebuild-${aws_codebuild_project.runner.name}-$${{ github.run_id }}-$${{ github.run_attempt }}"
}

output "runner_role_arn" {
  description = "ARN of the IAM role assumed by the runner."
  value       = aws_iam_role.runner.arn
}

output "runner_security_group_id" {
  description = "ID of the runner security group."
  value       = aws_security_group.runner.id
}
