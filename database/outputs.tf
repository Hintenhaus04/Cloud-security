output "db_endpoint" {
  value = aws_db_instance.cloudsecdb.address
}

output "db_vpc_id" {
  value = aws_vpc.saxit_vpc_db.id
}
