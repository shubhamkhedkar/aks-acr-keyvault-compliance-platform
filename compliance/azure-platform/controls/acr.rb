rg  = input('resource_group')
acr = input('acr_name')

control 'acr-01-private-keyless' do
  impact 1.0
  title 'ACR has no admin user, no anonymous pull and no public network access'
  desc 'Registry access must go through Entra ID tokens and RBAC (AcrPull for the kubelet identity, AcrPush for the pipeline). The shared admin credential and public pulls are disabled, and the data plane is unreachable from the Internet.'
  tag nist: %w[AC-3 SC-7], cis_azure: '9.x'
  describe azure_container_registry(resource_group: rg, name: acr) do
    it { should exist }
    its('sku.name') { should cmp 'Premium' }
    its('properties.adminUserEnabled') { should cmp false }
    its('properties.anonymousPullEnabled') { should cmp false }
    its('properties.publicNetworkAccess') { should cmp 'Disabled' }
    its('properties.policies.exportPolicy.status') { should cmp 'disabled' }
    its('properties.zoneRedundancy') { should cmp 'Enabled' }
  end
end

control 'acr-02-private-endpoint' do
  impact 0.7
  title 'ACR is reached through an approved private endpoint'
  desc 'Pulls from AKS and pushes from the self-hosted pipeline agents resolve privatelink.azurecr.io to the private endpoint inside the VNet.'
  describe azure_container_registry(resource_group: rg, name: acr) do
    its('properties.privateEndpointConnections.first.properties.privateLinkServiceConnectionState.status') { should cmp 'Approved' }
  end
end
