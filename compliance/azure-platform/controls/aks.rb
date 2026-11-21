rg  = input('resource_group')
aks = input('aks_name')

control 'aks-01-private-api' do
  impact 1.0
  title 'AKS API server is private with no public FQDN'
  desc 'The Kubernetes API is only reachable from inside the VNet (self-hosted agents or peered networks).'
  tag nist: %w[SC-7]
  describe azure_aks_cluster(resource_group: rg, name: aks) do
    it { should exist }
    its('properties.apiServerAccessProfile.enablePrivateCluster') { should cmp true }
    its('properties.apiServerAccessProfile.enablePrivateClusterPublicFQDN') { should cmp false }
  end
end

control 'aks-02-identity' do
  impact 1.0
  title 'Only Entra ID identities with Azure RBAC; local accounts disabled; Workload Identity on'
  desc 'Cluster access uses Entra ID groups with Azure RBAC; static local admin kubeconfigs are disabled. The OIDC issuer and Workload Identity let pods exchange service-account tokens for Entra tokens with no stored credentials.'
  tag nist: %w[IA-2 AC-2]
  describe azure_aks_cluster(resource_group: rg, name: aks) do
    its('properties.disableLocalAccounts') { should cmp true }
    its('properties.aadProfile.managed') { should cmp true }
    its('properties.aadProfile.enableAzureRBAC') { should cmp true }
    its('properties.oidcIssuerProfile.enabled') { should cmp true }
    its('properties.securityProfile.workloadIdentity.enabled') { should cmp true }
  end
end

control 'aks-03-addons' do
  impact 0.7
  title 'Azure Policy, Key Vault CSI (with rotation) and Container Insights add-ons are on'
  desc 'Azure Policy enforces pod security at admission, the Key Vault CSI driver mounts secrets with rotation, and Container Insights ships logs and metrics to Log Analytics.'
  describe azure_aks_cluster(resource_group: rg, name: aks) do
    its('properties.addonProfiles.azurepolicy.enabled') { should cmp true }
    its('properties.addonProfiles.azureKeyvaultSecretsProvider.enabled') { should cmp true }
    its('properties.addonProfiles.azureKeyvaultSecretsProvider.config.enableSecretRotation') { should cmp 'true' }
    its('properties.addonProfiles.omsagent.enabled') { should cmp true }
  end
end

control 'aks-04-network-and-upgrades' do
  impact 0.5
  title 'Cilium network policy, NAT egress, automatic patch upgrades'
  desc 'Cilium enforces NetworkPolicies, egress leaves through a NAT gateway with a known public IP, and the patch channel keeps the control plane current inside the maintenance window.'
  describe azure_aks_cluster(resource_group: rg, name: aks) do
    its('properties.networkProfile.networkPolicy') { should cmp 'cilium' }
    its('properties.networkProfile.outboundType') { should cmp 'userAssignedNATGateway' }
    its('properties.autoUpgradeProfile.upgradeChannel') { should cmp 'patch' }
  end
end

control 'aks-05-node-pools' do
  impact 0.5
  title 'Every node pool autoscales across three zones with encryption at host'
  desc 'Pools spread across three availability zones, scale automatically, keep nodes off public IPs and encrypt temp and cache disks at the host.'
  azure_aks_cluster(resource_group: rg, name: aks).properties.agentPoolProfiles.each do |pool|
    describe "node pool #{pool.name}" do
      subject { pool }
      its('enableAutoScaling') { should cmp true }
      its('availabilityZones.length') { should cmp 3 }
      its('enableEncryptionAtHost') { should cmp true }
      its('enableNodePublicIP') { should cmp false }
    end
  end
end
