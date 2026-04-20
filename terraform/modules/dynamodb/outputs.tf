output "table_arn" {
  value = aws_dynamodb_table.audit.arn
}

output "table_name" {
  value = aws_dynamodb_table.audit.name
}
