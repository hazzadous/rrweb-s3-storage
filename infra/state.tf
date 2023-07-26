// Put state to Terraform Cloud. I've not used this before so would be nice to have a play with it.

terraform {
  cloud {
    organization = "harryce2d9a94"

    workspaces {
      name = "rrweb-s3-storage"
    }
  }
}