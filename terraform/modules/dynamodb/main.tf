resource "aws_dynamodb_table" "audit" {
  name         = "${var.project_name}-audit"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_id"

  attribute {
    name = "event_id"
    type = "S"
  }

  attribute {
    name = "api_key_hash"
    type = "S"
  }

  global_secondary_index {
    name            = "api_key_hash-index"
    hash_key        = "api_key_hash"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = { Name = "${var.project_name}-audit" }
}
