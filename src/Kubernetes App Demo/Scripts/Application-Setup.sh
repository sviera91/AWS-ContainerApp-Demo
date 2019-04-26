#!/bin/bash
#Variables
echo "Setting Variables"
ECRStackName=ECR-Demo-01
VPCStackName=EKS-VPC-Demo-01
EKSNodesStackName=EKS-Nodes-Demo-01
EKSRoleARN=arn:aws:iam::068572557387:role/EKS-ManagementRole
Region=us-east-1
EKSClusterName=demo-cluster-01
NodeImageId=ami-0abcb9f9190e867ab
NodeGroupName=WorkerNG
NodeAutoScalingGroupMinSize=1
NodeAutoScalingGroupDesiredCapacity=2
NodeAutoScalingGroupMaxSize=3
NodeInstanceType=t3.medium
KeyName=EKS-Demo-01

#Deploy ECR --------------------------------------------------------------------------------------
echo "Deploying Elastic Container Registry (ECR)."
echo "Checking if ECR stack exists."
CheckECRStack=$(aws cloudformation describe-stacks --stack-name $ECRStackName) 2> /dev/null

if [ -n "$CheckECRStack" ]; then
    echo "ECR Stack already exists. Continuing."
    #echo "Applying any updates to ECR stack if available."
    #aws cloudformation update-stack --stack-name $ECRStackName --template-body file://"/Users/stewvier/Amazon WorkDocs Drive/My Documents/Repos/Master-Repo/src/Kubernetes App Demo/CloudFormation/ecr.yaml" --parameters ParameterKey=ECRRepositoryName,ParameterValue=container-demo/webapp 
    #aws cloudformation wait stack-update-complete --stack-name $ECRStackName
else
    echo "No ECR stack existent. Deploying a new stack."
    aws cloudformation create-stack --stack-name $ECRStackName --template-body file://"/Users/stewvier/Amazon WorkDocs Drive/My Documents/Repos/Master-Repo/src/Kubernetes App Demo/CloudFormation/ecr.yaml" --parameters ParameterKey=ECRRepositoryName,ParameterValue=container-demo/webapp
    aws cloudformation wait stack-create-complete --stack-name $ECRStackName
fi

ECRRepositoryName=$(aws cloudformation describe-stacks --stack-name $ECRStackName \
--query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryName`].OutputValue' \
--output text)
URI=$(aws cloudformation describe-stacks --stack-name $ECRStackName \
--query 'Stacks[0].Outputs[?OutputKey==`Uri`].OutputValue' \
--output text)
#Create and push container image --------------------------------------------------------------------------------------

echo "Logging to ECR."
eval $(aws ecr get-login --region $Region --no-include-email --profile default)
echo "Building & pushing container image."
docker build -f webapp-demo.dockerfile -t $ECRRepositoryName:v1 .
docker tag $ECRRepositoryName:v1 $URI/$ECRRepositoryName:v1
docker push $URI/$ECRRepositoryName:v1

#Deploy EKS VPC --------------------------------------------------------------------------------------

echo "Deploying VPC."
echo "Checking if VPC stack exists."
CheckVPCStack=$(aws cloudformation describe-stacks --stack-name $VPCStackName) 2> /dev/null

if [ -n "$CheckVPCStack" ]; then
    echo "VPC Stack already exists. Continuing."
    #echo "Applying any updates to VPC stack if available."
    #aws cloudformation update-stack --stack-name $VPCStackName --template-url https://amazon-eks.s3-us-west-2.amazonaws.com/cloudformation/2019-02-11/amazon-eks-vpc-sample.yaml
    #aws cloudformation wait stack-update-complete --stack-name $VPCStackName
else
    echo "No VPC stack existent. Deploying a new stack."
    aws cloudformation create-stack --stack-name $VPCStackName --template-url https://amazon-eks.s3-us-west-2.amazonaws.com/cloudformation/2019-02-11/amazon-eks-vpc-sample.yaml
    aws cloudformation wait stack-create-complete --stack-name $VPCStackName
fi

SubnetIds=$(aws cloudformation describe-stacks --stack-name $VPCStackName \
--query 'Stacks[0].Outputs[?OutputKey==`SubnetIds`].OutputValue' \
--output text)
SecurityGroups=$(aws cloudformation describe-stacks --stack-name $VPCStackName \
--query 'Stacks[0].Outputs[?OutputKey==`SecurityGroups`].OutputValue' \
--output text)
VpcId=$(aws cloudformation describe-stacks --stack-name $VPCStackName \
--query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' \
--output text)

#Create EKS cluster --------------------------------------------------------------------------------------

echo "Deploying Elastic Kubernetes Server (EKS)."
CheckEKSCluster=$(aws eks describe-cluster --name $EKSClusterName) 2> /dev/null

if [ -z "$CheckEKSCluster" ]; then
    echo "No existing EKS cluster. Deploying new EKS cluster."
    aws eks create-cluster --name $EKSClusterName --role-arn $EKSRoleARN --resources-vpc-config subnetIds=$SubnetIds,securityGroupIds=$SecurityGroups
    aws eks wait cluster-active --name $EKSClusterName
else
    echo "EKS cluster already exists. Continue."
fi

echo "Setting Kubernetes Config."
aws eks --region $Region update-kubeconfig --name $EKSClusterName

#Deploy Kubernetes Nodes --------------------------------------------------------------------------------------

echo "Deploying Kubernetes Nodes."
echo "Checking if EKS Nodes stack exists."
CheckEKSNodesStack=$(aws cloudformation describe-stacks --stack-name $EKSNodesStackName) 2> /dev/null

if [ -n "$CheckEKSNodesStack" ]; then
    echo "EKS Nodes Stack already exists. Continuing."
    #echo "Applying any updates to EKS Nodes stack if available."
    #aws cloudformation update-stack --stack-name $EKSNodesStackName --capabilities CAPABILITY_IAM --template-url https://amazon-eks.s3-us-west-2.amazonaws.com/cloudformation/2019-02-11/amazon-eks-nodegroup.yaml --parameters ParameterKey=ClusterName,ParameterValue=$EKSClusterName ParameterKey=ClusterControlPlaneSecurityGroup,ParameterValue=$SecurityGroups ParameterKey=NodeGroupName,ParameterValue=$NodeGroupName ParameterKey=NodeAutoScalingGroupMinSize,ParameterValue=$NodeAutoScalingGroupMinSize ParameterKey=NodeAutoScalingGroupDesiredCapacity,ParameterValue=$NodeAutoScalingGroupDesiredCapacity ParameterKey=NodeAutoScalingGroupMaxSize,ParameterValue=$NodeAutoScalingGroupMaxSize ParameterKey=NodeInstanceType,ParameterValue=$NodeInstanceType ParameterKey=NodeImageId,ParameterValue=$NodeImageId ParameterKey=KeyName,ParameterValue=$KeyName ParameterKey=VpcId,ParameterValue=$VpcId ParameterKey=Subnets,ParameterValue=$(echo \"$SubnetIds\") 
    #aws cloudformation wait stack-update-complete --stack-name $EKSNodesStackName
else
    echo "No EKS Nodes stack existent. Deploying a new stack."
    aws cloudformation create-stack --stack-name $EKSNodesStackName --capabilities CAPABILITY_IAM --template-url https://amazon-eks.s3-us-west-2.amazonaws.com/cloudformation/2019-02-11/amazon-eks-nodegroup.yaml --parameters ParameterKey=ClusterName,ParameterValue=$EKSClusterName ParameterKey=ClusterControlPlaneSecurityGroup,ParameterValue=$SecurityGroups ParameterKey=NodeGroupName,ParameterValue=$NodeGroupName ParameterKey=NodeAutoScalingGroupMinSize,ParameterValue=$NodeAutoScalingGroupMinSize ParameterKey=NodeAutoScalingGroupDesiredCapacity,ParameterValue=$NodeAutoScalingGroupDesiredCapacity ParameterKey=NodeAutoScalingGroupMaxSize,ParameterValue=$NodeAutoScalingGroupMaxSize ParameterKey=NodeInstanceType,ParameterValue=$NodeInstanceType ParameterKey=NodeImageId,ParameterValue=$NodeImageId ParameterKey=KeyName,ParameterValue=$KeyName ParameterKey=VpcId,ParameterValue=$VpcId ParameterKey=Subnets,ParameterValue=$(echo \"$SubnetIds\") 
    aws cloudformation wait stack-create-complete --stack-name $EKSNodesStackName
fi

NodeInstanceRole=$(aws cloudformation describe-stacks --stack-name $EKSNodesStackName \
--query 'Stacks[0].Outputs[?OutputKey==`NodeInstanceRole`].OutputValue' \
--output text)

#Connect nodes to cluster --------------------------------------------------------------------------------------

cd ~/.kube
curl -o aws-auth-cm.yaml https://amazon-eks.s3-us-west-2.amazonaws.com/cloudformation/2019-02-11/aws-auth-cm.yaml
sed -i -e "s~<ARN of instance role (not instance profile)>~$NodeInstanceRole~" aws-auth-cm.yaml
kubectl apply -f aws-auth-cm.yaml

#Launch container webapp --------------------------------------------------------------------------------------

cd "/Users/stewvier/Amazon WorkDocs Drive/My Documents/Repos/Master-Repo/src/Kubernetes App Demo/Kubernetes Files"
CWDeployment=$(kubectl get deployments container-webapp)

if [ -n "$CWDeployment" ]; then
    echo "Deployment already exists."
    echo "Downloading deployment data."
    kubectl describe svc container-webapp
else
    echo "Creating container-webapp deployment."
    kubectl create -f container-webapp.yaml
    kubectl create -f container-webapp-service.yaml
    kubectl describe svc container-webapp
fi
