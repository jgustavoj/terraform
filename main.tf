terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region     = "us-east-1"
}

variable "subnet_prefix" {
  # default     = "10.0.66.0/24" # value if you dont pass anything
  description = "cidr block for the subnet"
  type        =  object({ cidr_block = string, name = string})
}


# Create VPC
resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "production"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.prod-vpc.id

}

# Create Custom Route Table
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "Prod"
  }
}

# Create a Subnet
resource "aws_subnet" "subnet-1" {
  vpc_id            = aws_vpc.prod-vpc.id
  cidr_block        = var.subnet_prefix.cidr_block
  availability_zone = "us-east-1a" # Try to always hard code the availability zone

  tags = {
    Name = var.subnet_prefix.name
  }
}

# Associate subnet with Route Table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}

# Create a Security Group to allow port 22, 80, and 443
resource "aws_security_group" "allow-web" {
  name        = "allow_web_traffic"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id
  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
   ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

# Create a network interface with an IP in the subnet that was previously created
resource "aws_network_interface" "web-server-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow-web.id]
}

# Assign an elastic IP to the network interface
resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.web-server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.gw] # No need to point to ID, you want the whole object
}

# This command will output public_ip information on the console when we do 'terraform apply' command 
# *** careful with this command as it will deploy your infrastructure to aws (this is dangerous if your on a prod environment).
# If you just want the output use 'terraform output' command or 'terraform refresh' command. 
# This avoids writing 'terraform state list' and then 'terraform state show {resource name}' to show specific information on that resource
output "aws_public_ip" {
  value       = aws_eip.one.public_ip
}

# Create Ubuntu server and install/enable apache2
 resource "aws_instance" "web-server-instance" {
  ami               = "ami-007855ac798b5175e"
  instance_type     = "t2.micro"
  availability_zone = "us-east-1a"
  key_name = "main-key"

  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.web-server-nic.id
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install apache2 -y
              sudo systemctl start apache2
              sudo bash -c 'echo Oye Pipo Breno no esta facil > /var/www/html/index.html'
              EOF
  tags = {
    Name = "web-server"
  }
 }

output "server_private_ip" {
  value       = aws_instance.web-server-instance.private_ip
}

output "server_id" {
  value       = aws_instance.web-server-instance.id
}




#### IMPORTANT COMMANDS ###

# terraform init - Start working directory
# terraform validate - Check that your configuration is valid
# teraform plan - Show changes 
# terraform apply - Create or update your infrastructure
# terraform destroy - Destroy your infrastructure
# -- auto-approve flag at the end of the command will pass the 'yes' question

################################################################################################################################

# terraform - shows list of Main commands and All other commands
# terraform show - Show the current state or a saved plan in detail
# terraform state list - show list of resources in your state
# terraform state show {resource name} - Details on one specific resource example: 'terraform state show aws_eip.one' 
# terraform output - Prints out all the outputs
# terraform refresh - Refresh your states and releases outputs without deploying resources
# terraform destroy -target {name_of_resource} - Delete a specific resource, example: 'terraform destory -target aws_instance.web-server-instance' would delete just the web server instance
# terraform apply -target {name_of_resource} - Creates or updates just one resource listed in command
# terraform apply -var-file {example.tfvars} - To apply one specific variable file to resource