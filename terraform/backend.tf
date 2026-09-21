terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket       = "k8s-platform-lab-tfstate-328265692537"  
    key          = "eks/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true   
    encrypt      = true
  }
}