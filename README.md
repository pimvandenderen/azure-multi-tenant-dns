# Azure Multi tenant DNS Resolution

In this article I'm not going to explain in detail how Azure hybrid private DNS zones work [since this is pretty well documented already](https://learn.microsoft.com/en-us/azure/architecture/hybrid/hybrid-dns-infra), so I'm going to assume that you already have a good understanding of this concept. 

## The problem statement
Most organizations leverage a hybrid DNS recursive architecture to be able to resolve private endpoints for Azure PaaS services. There are a few good articles by Microsoft on how to design hybrid DNS with a [forwarder virtual machine in Azure](https://learn.microsoft.com/en-us/azure/architecture/example-scenario/networking/azure-dns-private-resolver#use-a-dns-forwarder-vm) or [Azure private DNS resolver](https://learn.microsoft.com/en-us/azure/architecture/example-scenario/networking/azure-dns-private-resolver#use-dns-private-resolver), so I'm not going to rehash these articles in details here today. 

When organizations have multiple Azure Entra ID tenant's, DNS for Azure native services with private endpoints such as Azure Storage becomes a challenge. The reason for this is that a single DNS private zone can only be forwarded to one Entra ID tenant at the time. DNS needs to be common infrastructure in the organization for successful DNS resolution and lookups. When you forward the same DNS zone to two different tenant, with two different private DNS zone record sets, the on-premise DNS forwarder doesn't know to resolve the records in tenant Prod or in tenant Development. 

![alt text](https://github.com/pimvandenderen/azure-multi-tenant-dns/blob/226d3515259f25f9b44d248b75503906f24e00db/ProblemStatement.png "DNS Multi tenant problem")

## Possible solutions
Recently I came across a great [Medium article](https://medium.com/sparebank1-digital/multi-tenant-and-hybrid-dns-with-azure-private-dns-6ace8a67b6de) written by Joakim Ellestad that explains this exact issue and how he solved this with Azure Lighthouse and Azure Policy. I shared this with my customer, but they didn't like this for two reasons: 
1. They didn't want to use cross tenant VNET peering between their production tenant and their development tenant. They want to maintain a network isolation boundry between their production and development tenants.
2. They didn't want to adopt Azure Lighthouse for just this problem.

## Another solution
To remove the need for cross tenant VNET peering, I tested out to use of [Azure Private Link Service](https://learn.microsoft.com/en-us/azure/private-link/private-link-service-overview). With Azure Private Link Service, we can expose the DNS servers from tenant Production to tenant Development using a private endpoint in tenant Development. Another reason I like this is that we can put the private endpoint on any VNET or subnet in any region in tenant Development. 

![alt text](https://github.com/pimvandenderen/azure-multi-tenant-dns/blob/8bcdffb18306ef3ce175702cede3f3c1f494861f/multitenant-dns-pls.png "DNS Multi Tenant with PLS")









