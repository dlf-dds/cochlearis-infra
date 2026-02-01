# Docusaurus Deployment

CI/CD pipeline builds docs and deploys to ECS.

## Architecture

```
docs repo (markdown) → GitHub Actions → ECR → ECS
```

## Setup Steps

### 1. Create Docs Repository

```bash
npx create-docusaurus@latest cochlearis-docs classic
cd cochlearis-docs
```

### 2. Add Dockerfile

```dockerfile
# Build stage
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Production stage
FROM nginx:alpine
COPY --from=builder /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
```

### 3. Add nginx.conf

```nginx
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /health {
        return 200 'ok';
        add_header Content-Type text/plain;
    }
}
```

### 4. GitHub Actions Workflow

`.github/workflows/deploy.yml`:

```yaml
name: Deploy Docs

on:
  push:
    branches: [main]

env:
  AWS_REGION: eu-central-1
  ECR_REPOSITORY: cochlearis-dev-docusaurus
  ECS_CLUSTER: cochlearis-dev
  ECS_SERVICE: docusaurus

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::ACCOUNT_ID:role/github-actions-role
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to ECR
        id: ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and push
        env:
          ECR_REGISTRY: ${{ steps.ecr.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:latest .
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest

      - name: Deploy to ECS
        run: |
          aws ecs update-service \
            --cluster $ECS_CLUSTER \
            --service $ECS_SERVICE \
            --force-new-deployment
```

## Infrastructure Requirements

### ECR Repository

Add to Terraform (or create manually):

```hcl
resource "aws_ecr_repository" "docusaurus" {
  name                 = "${local.name_prefix}-docusaurus"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
```

### GitHub OIDC Role

For keyless auth from GitHub Actions:

```hcl
# See: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
```

## Update Docusaurus Module

Once ECR is set up, update the container image:

```hcl
module "docusaurus" {
  # ...
  container_image = "${aws_ecr_repository.docusaurus.repository_url}:latest"
}
```

## Workflow

1. Edit markdown in docs repo
2. Push to main
3. GitHub Actions builds image
4. Image pushed to ECR
5. ECS pulls new image and deploys

Deployment is automatic on every push to main.
