# azure-multi-tenant-dns

## The problem statement
Most organizations leverage a hybrid DNS recursive architecture to be able to resolve private endpoints for Azure PaaS services. There are a few good articles by Microsoft on how to design hybrid DNS with a [forwarder virtual machine in Azure](https://learn.microsoft.com/en-us/azure/architecture/example-scenario/networking/azure-dns-private-resolver#use-a-dns-forwarder-vm) or [Azure private DNS resolver](https://learn.microsoft.com/en-us/azure/architecture/example-scenario/networking/azure-dns-private-resolver#use-dns-private-resolver), so I'm not going to rehash these articles in details here today. 

When organizations have multiple Azure Entra ID tenant's, DNS for Azure native services with private endpoints such as Azure Storage becomes a challenge. The reason for this is that a single DNS private zone can only be forwarded to one Entra ID tenant at the time. 




In this article I'm not going to explain in detail how Azure hybrid private DNS zones work [since this is pretty well documented already](https://learn.microsoft.com/en-us/azure/architecture/hybrid/hybrid-dns-infra), so I'm going to assume that you already have a good understanding of this concept. 



