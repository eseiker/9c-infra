resource "aws_vpc" "default" {
  count                            = var.create_vpc ? 1 : 0
  cidr_block                       = var.vpc_cidr_block
  enable_dns_hostnames             = true
  assign_generated_ipv6_cidr_block = true

  tags = {
    Name                                = "vpc-${var.vpc_name}"
    "kubernetes.io/cluster/${var.name}" = "shared"
  }
}

resource "aws_internet_gateway" "default" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = aws_vpc.default[0].id

  tags = {
    Name = "igw-${var.vpc_name}"
  }
}

resource "aws_eip" "nat" {
  count = var.create_vpc ? length(var.availability_zones) : 0
  vpc   = true

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_nat_gateway" "nat" {
  count = var.create_vpc ? length(var.availability_zones) : 0

  allocation_id = element(aws_eip.nat.*.id, count.index)

  subnet_id = element(aws_subnet.public.*.id, count.index)

  tags = {
    Name = "NAT-GW${count.index}-${var.vpc_name}"
  }

}

# PUBLIC SUBNETS
# The public subnet is where the bastion, NATs and ELBs reside. In most cases,
# there should not be any servers in the public subnet.

resource "aws_subnet" "public" {
  count  = var.create_vpc ? length(var.availability_zones) : 0
  vpc_id = aws_vpc.default[0].id

  cidr_block              = element(var.public_subnet_cidr_blocks, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name                                = "public${count.index}-${var.vpc_name}"
    Network                             = "Public"
	"kubernetes.io/role/elb"            = "1"
	"kubernetes.io/cluster/${var.name}"  = "shared"
  }
}

# PUBLIC SUBNETS - Default route
resource "aws_route_table" "public" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = aws_vpc.default[0].id

  tags = {
    Name = "publicrt-${var.vpc_name}"
  }
}

resource "aws_route_table_association" "public" {
  count          = var.create_vpc ? length(var.availability_zones) : 0
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public[0].id
}


# PRIVATE SUBNETS
# Route Tables in a private subnet will not have Route resources created
# statically for them as the NAT instances are responsible for dynamically
# managing them on a per-AZ level using the Network=Private tag.

resource "aws_subnet" "private" {
  count  = var.create_vpc ? length(var.availability_zones) : 0
  vpc_id = aws_vpc.default[0].id

  cidr_block        = element(var.private_subnet_cidr_blocks, count.index)
  availability_zone = element(var.availability_zones, count.index)

  tags = {
    Name                                = "private${count.index}-${var.vpc_name}"
    immutable_metadata                  = "{ \"purpose\": \"internal_${var.vpc_name}\", \"target\": null }"
    Network                             = "Private"
  }
}

resource "aws_route_table" "private" {
  count  = var.create_vpc ? length(var.availability_zones) : 0
  vpc_id = aws_vpc.default[0].id

  tags = {
    Name    = "private${count.index}rt-${var.vpc_name}"
    Network = "Private"
  }
}

resource "aws_route_table_association" "private" {
  count          = var.create_vpc ? length(var.availability_zones) : 0
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.private.*.id, count.index)
}

resource "aws_route" "public_internet_gateway" {
  count                  = var.create_vpc ? 1 : 0
  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.default[0].id
}

resource "aws_route" "private_nat" {
  count                  = var.create_vpc ? length(var.availability_zones) : 0
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[count.index].id
}

