Goal architecture:
- Docker image registered in ECR
- EC2 initialised from the Docker
- EC2 in the private subnet
- Endpoint to the ECR, so that EC2 can pull the image