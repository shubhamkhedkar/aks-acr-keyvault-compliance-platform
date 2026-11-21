rg   = input('resource_group')
vnet = input('vnet_name')
law  = input('log_analytics_name')

control 'net-01-subnets-have-nsgs' do
  impact 0.7
  title 'Every subnet in the platform VNet has an NSG'
  desc 'A subnet without an NSG has no network-layer filtering.'
  azure_virtual_network(resource_group: rg, name: vnet).subnets.each do |subnet_name|
    describe azure_subnet(resource_group: rg, vnet: vnet, name: subnet_name) do
      its('nsg') { should_not be_nil }
    end
  end
end

control 'net-02-no-internet-inbound' do
  impact 1.0
  title 'No platform NSG allows SSH or RDP from the Internet'
  desc 'Management ports must never be open to the Internet; administration goes through Entra ID-authenticated, private paths.'
  azure_network_security_groups(resource_group: rg).names.each do |nsg|
    describe azure_network_security_group(resource_group: rg, name: nsg) do
      it { should_not allow_ssh_from_internet }
      it { should_not allow_rdp_from_internet }
    end
  end
end

control 'mon-01-log-analytics' do
  impact 0.5
  title 'Log Analytics keeps at least 90 days and refuses shared-key ingestion'
  desc 'Retention covers incident investigation windows and ingestion requires Entra ID authentication.'
  describe azure_generic_resource(resource_group: rg, name: law, resource_provider: 'Microsoft.OperationalInsights/workspaces') do
    it { should exist }
    its('properties.retentionInDays') { should be >= 90 }
    its('properties.features.disableLocalAuth') { should cmp true }
  end
end
