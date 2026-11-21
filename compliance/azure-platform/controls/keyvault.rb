rg    = input('resource_group')
vault = input('key_vault_name')

control 'kv-01-rbac-and-recovery' do
  impact 1.0
  title 'Key Vault uses Azure RBAC, soft delete (90 days) and purge protection'
  desc 'Access policies are replaced by Azure RBAC so access is auditable and least-privilege (Secrets User for workloads, Secrets Officer for admins). Purge protection stops a deleted vault or secret from being destroyed before the retention window ends.'
  tag nist: %w[AC-3 CP-9]
  describe azure_key_vault(resource_group: rg, name: vault) do
    it { should exist }
    its('properties.enableRbacAuthorization') { should cmp true }
    its('properties.enableSoftDelete') { should cmp true }
    its('properties.softDeleteRetentionInDays') { should cmp 90 }
    its('properties.enablePurgeProtection') { should cmp true }
  end
end

control 'kv-02-network' do
  impact 1.0
  title 'Key Vault is closed to public networks'
  desc 'The vault firewall defaults to Deny and public network access is off; only the private endpoint and trusted Azure services can reach it.'
  tag nist: %w[SC-7]
  describe azure_key_vault(resource_group: rg, name: vault) do
    its('properties.publicNetworkAccess') { should cmp 'Disabled' }
    its('properties.networkAcls.defaultAction') { should cmp 'Deny' }
  end
end

control 'kv-03-audit-logging' do
  impact 0.7
  title 'Key Vault audit events are shipped to Log Analytics'
  desc 'AuditEvent logs record every secret read/write so CSI driver access by the workload identity can be traced.'
  describe azure_key_vault(resource_group: rg, name: vault) do
    its('diagnostic_settings_logs') { should_not be_empty }
  end
end
