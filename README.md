# Azure Multi tenant DNS Resolution

In this article I'm not going to explain in detail how Azure hybrid private DNS zones work [since this is pretty well documented already](https://learn.microsoft.com/en-us/azure/architecture/hybrid/hybrid-dns-infra), so I'm going to assume that you already have a good understanding of this concept. 

## The problem statement
Most organizations leverage a hybrid DNS recursive architecture to be able to resolve private endpoints for Azure PaaS services. There are a few good articles by Microsoft on how to design hybrid DNS with a [forwarder virtual machine in Azure](https://learn.microsoft.com/en-us/azure/architecture/example-scenario/networking/azure-dns-private-resolver#use-a-dns-forwarder-vm) or [Azure private DNS resolver](https://learn.microsoft.com/en-us/azure/architecture/example-scenario/networking/azure-dns-private-resolver#use-dns-private-resolver), so I'm not going to rehash these articles in details here today. 

When organizations have multiple Azure Entra ID tenant's, DNS for Azure native services with private endpoints such as Azure Storage becomes a challenge. The reason for this is that a single DNS private zone can only be forwarded to one Entra ID tenant at the time. DNS needs to be common infrastructure in the organization for successful DNS resolution and lookups. When you forward the same DNS zone to two different tenant, with two different private DNS zone record sets, the on-premise DNS forwarder doesn't know to resolve the records in tenant Prod or in tenant Development. 

![alt text](https://github.com/pimvandenderen/azure-multi-tenant-dns/blob/226d3515259f25f9b44d248b75503906f24e00db/ProblemStatement.png "DNS Multi tenant problem")



## Possible solutions
Recently I came across a great [Medium article](https://medium.com/sparebank1-digital/multi-tenant-and-hybrid-dns-with-azure-private-dns-6ace8a67b6de) written by Joakim Ellestad that explains this exact issue and how he solved this with Azure Lighthouse and Azure Policy. There are two things that I didn't like about this solution and I wanted to improve upon: 
1. Cross VNET peering: I don't want to use  cross tenant VNET peering between my main/production and remote/development tenants. I want to maintain a network isolation boundry between tenants. There is also a [limit](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/azure-subscription-service-limits#networking-limits) of 500 peerings per virtual network, so this might break down at scale. 
2. If customers are not using Azure Lighthouse, I don't want to incorperate this into the architecture. 

##  solution
To remove the need for cross tenant VNET peering, I tested out to use of [Azure Private Link Service](https://learn.microsoft.com/en-us/azure/private-link/private-link-service-overview). With Azure Private Link Service, we can expose the DNS servers from tenant Production to tenant Development using a private endpoint in tenant Development. Another reason I like this is that we can put the private endpoint on any VNET or subnet in any region in tenant Development. 

![alt text](https://github.com/pimvandenderen/azure-multi-tenant-dns/blob/8bcdffb18306ef3ce175702cede3f3c1f494861f/multitenant-dns-pls.png "DNS Multi Tenant with PLS")

### Step 1: Cross tenant DNS resolution using Azure Private Link Service 
As you can see in the diagram above, I have two DNS servers in my production tenant, acting as a DNS forwarder to the private DNS zones hosted in that tenant. I put both of these private DNS servers behind a standard Azure Load Balancer to be able to use PLS to my development tenant. Configuration steps:
1. Create two virtual machines in tenant production that act as DNS forwarders. For this scenario you cannot use Azure Private DNS Resolver since Azure Private Link Service requires a standard load balancer.
2. Create a private DNS zone for the Azure PaaS service that you want to resolve (such as privatelink.blob.core.windows.net) and link this private DNS zone to the VNET where your DNS forwarders are hosted.
3. Create an Azure PaaS service (such as an Azure Storage Account) with a private endpoint
4. Create an A-Record for the private endpoint of the Azure PaaS service in the private DNS zone. 
5. Create the private endpoint in the second (development) tenant. Assign the private endpoint to a VNET and subnet in this second (development) tenant.
6. Change the DNS servers on the spoke-vnet to custom and assign the IP of the private endpoint as a custom DNS server.
7. Reboot your virtual machine in the spoke VNET in the development
8. Using NSLookup, you can now resolve the A-record hosted in the Production tenant private DNS zone.

### Step 2: Maintaining A-records accross multiple tenants
To keep the DNS records in sync between the production tenant and the development tenant, I'm using an Azure Function to replicate these a-records. The function lists the a-record from the development tenant and creates a duplicate of this a-record in the private DNS zone in the production tenant. Similarly, if you remove the a-record from the development tenant, the Azure function removes the a-record from the production tenant as well. This means that for private endpoints in the development tenant, you still need to register the DNS records in the private DNS zone (in the development tenant). Using the Azure Portal, you get the option during the creation of the private endpoint on the PaaS service. If you are using Terraform, ARM or another IaC, I highly recommend incorperating this in your automation process. There is also a great [article](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/private-link-and-dns-integration-at-scale) as part of the Azure Cloud Adoption Framework that describes how you can use a Azure Policy for this. 



Configuration steps for the Azure Function: 

**1. Create the Application Registration** (Development/remote tenant): 
  - Go to Microsoft Entra ID --> App Registration and click on "New Registration". Give the Application Registration a name (for example: func-cross-tenant-dns). Leave the supported account type as is (Single tenant) and click on "Register".
  - On the application registration, under "Manage" go to "Certificates & Secrets". Make sure "Client Secrets" is selected and click on "New Client secret" to create a new client secret. Optionally, give this secret a description and click on add. Copy the secret ID and secret value, we are going to need these later.
  - Go to "API Permissions, click on "Add a permission". Under Mirosoft API's, click on "Microsoft Graph". Select "Application Permissions" and select the "Sites.ReadWrite.All". Click on "Add Permission"
  - In the API permissions screen, click on "Grant admin consent for Default Directory". The final result looks like this:
   
![alt text](https://github.com/pimvandenderen/azure-multi-tenant-dns/blob/5539dc9c2e59e00e48cdee40b2aa44a1471a0c9b/images/appreg.png)

**2. Assign the application registration permissions on the private DNS zone(s)** (Development/remote tenant):
  - Go to the private DNS zone that you want to copy over to the Production/main tenant (for example: privatelink.blob.core.windows.net) and go to "Access Control (IAM)"
  - Click on Add --> Add Role assignment. Select the "Reader" role and click "next".
  - Under Members, select the service principle you created in step 1 (func-cross-tenant-dns). Click on "Review + Assign" to give the service principle permissions. 

You can use this for multiple DNS zones, you need to repeat step 2 for all Private DNS zones in the environment or set the permissions on the resource group that the Private DNS zones are in (recommended). 

_Please be aware that step 3 and below need to be executed on the Production/main tenant._

**3. Create the Azure Function** (Production / Main tenant):
- Go to Function App --> Create.
- Under Basic, select the subscription and resource group where you want to host the function. Give the function a unique name.
  - Do you want to deploy code or container image: Code
  - Runtime stack: PowerShell Core
  - Version: 7.2
  - Operating system: Windows
  - Hosting options and plans: Consumption
- Storage: Leave as default
- Networking: Leave as default (enable public access: On)
- Monitoring: Leave as default (Enable Application Insights)
- Deployment: Leave as default.
- Click "Review + Create" to create the function

**4. Configure the Azure Function** (Production / main tenant):
PowerShell script for the Azure Function can be found here: https://github.com/pimvandenderen/azure-multi-tenant-dns/tree/master/azure-function-cross-tenant-dns

- Upload the PowerShell script to the Azure Function. Instructions on how to do this are here: https://learn.microsoft.com/en-us/azure/azure-functions/deployment-zip-push
- Enable the Azure Function Managed Identity. Go to the Azure function --> Settings --> Identity. Select "System assigned" and select "Status -> On".
- Set the variables for the Azure Function. On the Azure Function --> under settings --> Click on "Configuration".
- Under Application settings, add the following application settings. 
  

| Name  | Example Value | Description |
| ------------- | ------------- | ----------- | 
| **DNSZONENAME**  | privatelink.blob.core.windows.net  | The name of the Azure Private DNS Zone that you want to synchronize between the remote/development and the main/production tenant | 
| **MAIN_RGNAME**  | privatedns-rg  | The name of the resource group in the **main/production tenant** that contains the Azure Private DNS zone  | 
| **MAIN_SUBSCRIPTIONID**  | 9c244509-16f9-439d-ad2c-ee6df5389311  | The Subscription ID in **main/production tenant** that that contains the Azure Private DNS zone | 
| **REMOTE_CLIENTID**  | fd402476-a32a-4a7c-95ca-0020927eca7e  | The Client ID / Application ID of the Application Registration in the **remote/development tenant** that you created in step 1 | 
| **REMOTE_RGNAME**  | privatedns-rg  | The name of the resource group in the **remote/development tenant** that contains the Azure Private DNS zone | 
| **REMOTE_SECRETID**  | 53461211-eef0-4e1c-a883-51dfe855e0e4  | The Secret ID of the Application Registration in the **remote/development tenant** that you created in step 1 | 
| **REMOTE_SECRETVALUE**  | V_O8Q~vw6n0NFEy7pwL6.BL0XwOt324UwSfYgS64ebB4| The Secret value of the Application Registration in the **remote/development tenant** that you created in step 1 | 
| **REMOTE_SUBSCRIPTIONID**  | 840e13a6-7fd8-4f0d-85e0-2a8812859f96  | The Subscription ID in **remote/development tenant** that contains the Azure Private DNS zone | 
| **REMOTE_TENANT**  | 840e13a6-7fr8-4f0d-85e0-2a8812859f97  | The tenant ID of the remote tenant that contains the Azure Private DNS zone  | 


**5. Give the Managed Identity permissions on the Azure Private DNS Zone** (Production / main tenant): 
- Go to the Private DNS zone that you want to synchronize between between the remote/development and the main/production tenant
- Click on Add --> Add Role assignment. Select the "Private DNS Contributor" role and click "next".
- Under Members, select the service principle you created in step 1 (func-cross-tenant-dns). Click on "Review + Assign" to give the service principle permissions.

**6. Test the Azure Function** (Production / main tenant):
You can test the Azure Function by starting it. The function also runs on a 5 minute timer, so DNS gets updated every 5 minutes. DNS records that are populated in the remote/development tenant, will be automatically copied to the main/production tenant. 












