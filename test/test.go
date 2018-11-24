package test

import (
	"fmt"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/ssh"
	"github.com/gruntwork-io/terratest/modules/terraform"
)

// Pritunl the pritunl terraform
func Pritunl(t *testing.T) {
	t.Parallel()

	// A unique ID we can use to namespace resources so we don't clash with anything already in the AWS account or
	// tests running in parallel
	uniqueID := random.UniqueId()

	// Give this EC2 Instance and other resources in the Terraform code a name with a unique ID so it doesn't clash
	// with anything else in the AWS account.
	instanceName := fmt.Sprintf("terratest-http-example-%s", uniqueID)

	// Specify the text the EC2 Instance will return when we make HTTP requests to it.
	instanceText := fmt.Sprintf("Hello, %s!", uniqueID)

	// Pick a random AWS region to test in. This helps ensure your code works in all regions.
	awsRegion := aws.GetRandomRegion(t, nil, nil)

	awsKeyName := "key"
	amiID := "ami-403e2524"
	tags := map[string]string{
		"env":     "test",
		"service": "pritunl",
		"notes":   "test",
	}

	terraformOptions := &terraform.Options{
		// The path to where our Terraform code is located
		TerraformDir: "../",

		// Variables to pass to our Terraform code using -var options
		Vars: map[string]interface{}{
			"aws_region":   awsRegion,
			"aws_key_name": awsKeyName,
			"ami_id":       amiId,
			"tags":         tags,
		},
	}

	// At the end of the test, run `terraform destroy` to clean up any resources that were created
	defer terraform.Destroy(t, terraformOptions)

	// This will run `terraform init` and `terraform apply` and fail the test if there are any errors
	terraform.InitAndApply(t, terraformOptions)

	// Run `terraform output` to get the value of an output variable
	instancePrivateIP := terraform.Output(t, terraformOptions, "vpn_instance_private_ip_address")

	instancePublicIP := terraform.Output(t, terraformOptions, "vpn_public_ip_address")

	vpnManagementUI := terraform.Output(t, terraformOptions, "vpn_management_ui")

	// It can take a minute or so for the Instance to boot up, so retry a few times
	maxRetries := 30
	timeBetweenRetries := 5 * time.Second

	// Verify that we get back a 200 OK from the management UI
	http_helper.HttpGetWithRetry(t, vpnManagementUI, 200, instanceText, maxRetries, timeBetweenRetries)

	// Set up key pair for ssh checks

	ec2KeyPair := aws.CreateAndImportEC2KeyPair(t, awsRegion, fmt.Sprintf("pritunl-test-key-%s", uniqueID))

	// Set up host for ssh checks
	host := ssh.Host{
		Hostname:    instancePublicIP,
		SshUserName: "ec2-user",
		SshKeyPair:  *ec2KeyPair,
	}

	// Verify that we can ssh to the instance
	ssh.CheckSSHConnection(t, host)

	// Verify outbound internet access on the instance
	ssh.CheckSSHCommand(t, host, "curl google.com")

	// Check if the pritunl package is installed
	ssh.CheckSSHCommand(t, host, "rpm -q pritunl")

	// Check if the mongodb package is installed
	ssh.CheckSSHCommand(t, host, "rpm -q mongodb-org")

	// Check if the AWS SSM agent is running
	ssh.CheckSSHCommand(t, host, "aws ssm describe-instance-information")

	// Check if the logrotate configuration is valid
	ssh.CheckSSHCommand(t, host, "logrotate -d '/etc/logrotate.d/pritunl'")
}
