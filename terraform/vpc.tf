# 현재 Region에서 사용 가능한 가용영역 목록을 조회한다.
# 특정 가용영역 이름을 코드에 고정하지 않기 위해 사용한다.
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # AWS 리소스 이름에 공통으로 사용할 접두사
  # 결과 예시: ecommerce-dev-vpc
  name_prefix = "${var.project_name}-${var.environment}"

  # 고가용성을 위해 현재 Region의 가용영역 중 2개 사용
  availability_zones = slice(
    data.aws_availability_zones.available.names,
    0,
    2
  )

  # ALB와 NAT Gateway를 배치할 Public Subnet CIDR
  public_subnet_cidrs = [
    "10.0.1.0/24",
    "10.0.2.0/24"
  ]

  # EKS Worker Node와 RDS를 배치할 Private Subnet CIDR
  private_subnet_cidrs = [
    "10.0.11.0/24",
    "10.0.12.0/24"
  ]
}

# 프로젝트에서 사용할 독립된 AWS 네트워크
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  # EKS와 RDS Endpoint를 DNS 이름으로 조회할 수 있도록 활성화
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# Public Subnet이 인터넷과 통신할 수 있도록 VPC에 연결
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# 외부 ALB와 NAT Gateway를 배치할 Public Subnet
resource "aws_subnet" "public" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.public_subnet_cidrs[count.index]
  availability_zone = local.availability_zones[count.index]

  # Public Subnet에서 생성되는 리소스에 Public IP 자동 할당
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-${count.index + 1}"

    # AWS Load Balancer Controller가 외부 ALB용 Subnet으로 식별하는 태그
    "kubernetes.io/role/elb" = "1"
  }
}

# EKS Worker Node와 RDS를 외부에 직접 노출하지 않기 위한 Private Subnet
resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.availability_zones[count.index]

  tags = {
    Name = "${local.name_prefix}-private-${count.index + 1}"

    # 내부 Load Balancer용 Subnet으로 식별하는 태그
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Public Subnet에서 사용할 Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

# Public Subnet의 외부 트래픽을 Internet Gateway로 전달
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# Public Subnet 2개에 Public Route Table 연결
resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway에 할당할 고정 Public IP
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip"
  }

  # Internet Gateway가 생성된 후 EIP를 구성
  depends_on = [
    aws_internet_gateway.main
  ]
}

# Private Subnet의 EKS Worker Node가 인터넷으로 나갈 때 사용하는 NAT Gateway
# 3일 프로젝트의 비용을 줄이기 위해 Public Subnet 1에 1개만 배치한다.
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${local.name_prefix}-nat"
  }

  depends_on = [
    aws_internet_gateway.main
  ]
}

# Private Subnet에서 사용할 Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-private-rt"
  }
}

# Private Subnet의 외부 트래픽을 NAT Gateway로 전달
resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

# Private Subnet 2개에 Private Route Table 연결
resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}