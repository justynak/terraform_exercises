resource "aws_ecr_repository" "app" {
  name                 = "hello-container"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration { scan_on_push = true }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/app/hello-container"
  retention_in_days = 7
}

# Build & push the image as part of `terraform apply`.
# - Re-runs only when the docker_setup/ sources change (triggers_replace).
# - The instance depends on this, so the image exists before first boot.
resource "terraform_data" "image_push" {
  triggers_replace = {
    # Hash of everything in docker_setup/ so edits trigger a rebuild+push.
    source_hash = sha1(join("", [
      for f in fileset("${path.module}/docker_setup", "*") :
      filesha1("${path.module}/docker_setup/${f}")
    ]))
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      REGISTRY="${regex("^[^/]+", aws_ecr_repository.app.repository_url)}"
      aws ecr get-login-password --region "${data.aws_region.current.name}" \
        | docker login --username AWS --password-stdin "$REGISTRY"
      docker build -t "${aws_ecr_repository.app.repository_url}:v1" \
        "${path.module}/docker_setup"
      docker push "${aws_ecr_repository.app.repository_url}:v1"
    EOT
  }
  depends_on = [aws_ecr_repository.app]
}

