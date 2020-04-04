#!/bin/bash

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

ECR_IMAGE_PREFIX=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com

deploy_images() {
    echo "Deploying Grpc Color Client and Color Server images to ECR..."
    for app in grpc_color_client grpc_color_server; do
        aws ecr describe-repositories --repository-name ${app} >/dev/null 2>&1 || aws ecr create-repository --repository-name ${app}
        docker build -t ${ECR_IMAGE_PREFIX}/${app} "${DIR}/../src/${app}" --build-arg GO_PROXY=${GO_PROXY:-"https://proxy.golang.org"}
        $(aws ecr get-login --no-include-email)
        docker push ${ECR_IMAGE_PREFIX}/${app}
    done
}

deploy_app() {
    echo "Deploying Cloud Formation stack: \"${ENVIRONMENT_NAME}-grpc-ecs-service\""
    aws --region "${AWS_DEFAULT_REGION}" \
        cloudformation deploy \
        --stack-name "${ENVIRONMENT_NAME}-grpc-ecs-service" \
        --capabilities CAPABILITY_IAM \
        --template-file "${DIR}/grpc-ecs-service.yaml"  \
        --parameter-overrides \
        EnvironmentName="${ENVIRONMENT_NAME}" \
        ECSServicesDomain="${SERVICES_DOMAIN}" \
        AppMeshMeshName="${MESH_NAME}" \
        EnvoyImage="${ENVOY_IMAGE}" \
        GrpcColorClientImage="${ECR_IMAGE_PREFIX}/grpc_color_client" \
        GrpcColorServerImage="${ECR_IMAGE_PREFIX}/grpc_color_server" \
        AppMeshXdsEndpoint="${APPMESH_XDS_ENDPOINT}"
}

print_bastion() {
    echo "Bastion endpoint:"
    ip=$(aws cloudformation describe-stacks \
        --stack-name="${ENVIRONMENT_NAME}-ecs-cluster" \
        --query="Stacks[0].Outputs[?OutputKey=='BastionIP'].OutputValue" \
        --output=text)
    echo "${ip}"
}

deploy_stacks() {
    deploy_images
    deploy_app

    print_bastion
}

deploy_stacks