package test

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/ssh"
	"github.com/gruntwork-io/terratest/modules/terraform"
)

// Pritunl the pritunl terraform
func TestPritunl(t *testing.T) {
	t.Parallel()

	// A unique ID we can use to namespace resources so we don't clash with anything already in the AWS account or
	// tests running in parallel
	uniqueID := strings.ToLower(random.UniqueId())

	// Give this EC2 Instance and other resources in the Terraform code a name with a unique ID so it doesn't clash
	// with anything else in the AWS account.
	// instanceName := fmt.Sprintf("terratest-http-example-%s", uniqueID)

	// Specify the text the EC2 Instance will return when we make HTTP requests to it.
	// instanceText := fmt.Sprintf("Hello, %s!", uniqueID)

	// Pick a random AWS region to test in. This helps ensure your code works in all regions.
	//awsRegion := aws.GetRandomRegion(t, nil, nil)
	awsRegion := "us-east-1"

	// Set up key pair for ssh checks
	ec2KeyPair := aws.CreateAndImportEC2KeyPair(t, awsRegion, fmt.Sprintf("pritunl-test-key-%s", uniqueID))
	defer aws.DeleteEC2KeyPair(t, ec2KeyPair)

	vpcID := "vpc-10569769"
	amiID := "ami-009d6802948d06e52"
	publcSubnetID := "subnet-282be672"
	whitelist := []string{"0.0.0.0/0"}
	tags := map[string]string{
		"env":     "test",
		"service": "pritunl",
		"Name":    fmt.Sprintf("pritunl-instance-%s", uniqueID),
	}

	bucketName := fmt.Sprintf("pritunl-backups-%s", uniqueID)

	terraformOptions := &terraform.Options{
		// The path to where our Terraform code is located
		TerraformDir: "../",

		// Variables to pass to our Terraform code using -var options
		Vars: map[string]interface{}{
			"aws_region":       awsRegion,
			"aws_key_name":     ec2KeyPair.Name,
			"vpc_id":           vpcID,
			"ami_id":           amiID,
			"public_subnet_id": publcSubnetID,
			"whitelist":        whitelist,
			"tags":             tags,
			"s3_bucket_name":   bucketName,
		},
	}

	// At the end of the test, run `terraform destroy` to clean up any resources that were created
	defer terraform.Destroy(t, terraformOptions)

	// This will run `terraform init` and `terraform apply` and fail the test if there are any errors
	terraform.InitAndApply(t, terraformOptions)

	// Run `terraform output` to get the value of an output variable
	// instancePrivateIP := terraform.Output(t, terraformOptions, "vpn_instance_private_ip_address")

	instancePublicIP := terraform.Output(t, terraformOptions, "vpn_public_ip_address")

	// vpnManagementUI := terraform.Output(t, terraformOptions, "vpn_management_ui")

	bucketID := terraform.Output(t, terraformOptions, "s3_bucket_name")

	// It can take a minute or so for the Instance to boot up, so retry a few times
	maxRetries := 30
	timeBetweenRetries := 5 * time.Second

	// Verify that we get back a 200 OK from the management UI
	// http_helper.HttpGetWithRetry(t, vpnManagementUI, 200, instanceText, maxRetries, timeBetweenRetries)

	// Set up host for ssh checks
	host := ssh.Host{
		Hostname:    instancePublicIP,
		SshUserName: "ec2-user",
		SshKeyPair:  ec2KeyPair.KeyPair,
	}

	// Verify that we can ssh to the instance
	retry.DoWithRetry(t, "Check SSH connection", maxRetries, timeBetweenRetries, func() (string, error) {
		err := ssh.CheckSshConnectionE(t, host)
		if err != nil {
			return "", fmt.Errorf("Could not connect to instance")
		}
		return "", nil
	})

	// Verify outbound internet access on the instance
	ssh.CheckSshCommand(t, host, "curl google.com")

	// Check if the AWS SSM agent is running
	ssh.CheckSshCommand(t, host, "sudo systemctl status amazon-ssm-agent")

	// Check if the s3 bucket has been created
	aws.AssertS3BucketExists(t, awsRegion, bucketID)

	// Check if the instance can list the contents of the s3 bucket
	ssh.CheckSshCommand(t, host, fmt.Sprintf("aws s3 ls s3://%s", bucketID))

	// Check if the instance can write to the s3 bucket
	ssh.CheckSshCommand(t, host, fmt.Sprintf("echo test > test.file && aws s3 cp test.file s3://%s/test.file", bucketID))

	// Check if the instance can delete from the s3 bucket
	ssh.CheckSshCommand(t, host, fmt.Sprintf("aws s3 rm s3://%s/test.file", bucketID))
}
