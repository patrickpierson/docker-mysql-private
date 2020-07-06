locals {
  nat_gateways_count = var.nat_gateway_enabled ? length(var.availability_zones) : 0
}

resource "aws_eip" "default" {
  count = local.nat_gateways_count
  vpc   = true

  tags = merge(
    var.private_tags,
    {
      "Name" = format(
        "%s%s%s",
        var.private_id,
        var.delimiter,
        replace(
          element(var.availability_zones, count.index),
          "-",
          var.delimiter
        )
      )
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_nat_gateway" "default" {
  count         = local.nat_gateways_count
  allocation_id = element(aws_eip.default.*.id, count.index)
  subnet_id     = element(aws_subnet.public.*.id, count.index)

  tags = merge(
    var.nat_tags,
    {
      "Name" = format(
        "%s%s%s",
        var.nat_id,
        var.delimiter,
        replace(
          element(var.availability_zones, count.index),
          "-",
          var.delimiter
        )
      )
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route" "default" {
  count                  = local.nat_gateways_count
  route_table_id         = element(aws_route_table.private.*.id, count.index)
  nat_gateway_id         = element(aws_nat_gateway.default.*.id, count.index)
  destination_cidr_block = "0.0.0.0/0"
  depends_on             = [aws_route_table.private]
}
