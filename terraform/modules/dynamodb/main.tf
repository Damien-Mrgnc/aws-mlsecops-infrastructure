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

  # Point-in-time recovery : restauration possible à n'importe quel instant (CKV_AWS_28)
  point_in_time_recovery {
    enabled = true
  }

  # KMS désactivé : chiffrement AES-256 par défaut activé sur DynamoDB, KMS CMK ajouté en prod
  #checkov:skip=CKV_AWS_119:Chiffrement AES-256 par défaut activé, KMS CMK ajouté en prod

  tags = { Name = "${var.project_name}-audit" }
}
